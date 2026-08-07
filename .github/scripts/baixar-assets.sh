#!/usr/bin/env bash
# Baixa cada imagem listada em .github/assets-sources.txt para assets/.
#
# A regra central: se o download falhar OU a resposta parecer um card de erro,
# o arquivo que já está no repositório é MANTIDO. É isso que impede o README
# de ficar sem gráfico quando a API de terceiros cai.
#
# Nunca sai com erro — uma API fora do ar é o caso esperado, não uma falha do
# workflow. Ele só registra um aviso.

set -uo pipefail

MANIFESTO='.github/assets-sources.txt'
DESTINO='assets'
TENTATIVAS=3
ESPERA=15

falhas=0
mkdir -p "$DESTINO"

# As APIs devolvem HTTP 200 mesmo quando dão erro — o corpo é um SVG de erro.
# Então validar "é SVG?" não basta; precisa olhar o conteúdo.
valido() {
  local novo="$1" antigo="$2" bytes antes

  bytes=$(wc -c < "$novo")

  if [ "$bytes" -lt 500 ]; then
    echo "    resposta curta demais ($bytes bytes)"
    return 1
  fi

  if ! grep -q '<svg' "$novo"; then
    echo '    não é um SVG'
    return 1
  fi

  # "Error lable" (com o typo) é o marcador do card de erro do streak-stats.
  if grep -qiE 'error lable|error label|maximum retries|rate limit|went wrong' "$novo"; then
    echo '    a API devolveu um card de erro'
    return 1
  fi

  # Rede de segurança para formatos de erro que ainda não conhecemos: o card
  # real nunca encolhe para menos da metade do tamanho anterior.
  if [ -f "$antigo" ]; then
    antes=$(wc -c < "$antigo")
    if [ "$antes" -gt 0 ] && [ $((bytes * 2)) -lt "$antes" ]; then
      echo "    encolheu demais ($antes -> $bytes bytes), suspeito"
      return 1
    fi
  fi

  return 0
}

while IFS='|' read -r nome url || [ -n "${nome:-}" ]; do
  # tr também remove o \r de arquivos salvos com quebra de linha do Windows
  nome=$(printf '%s' "${nome:-}" | tr -d '[:space:]')
  url=$(printf '%s' "${url:-}" | tr -d '[:space:]')

  [ -z "$nome" ] && continue
  case "$nome" in \#*) continue ;; esac

  if [ -z "$url" ]; then
    echo "$nome: sem URL no manifesto, ignorando"
    continue
  fi

  arquivo="$DESTINO/$nome"
  echo "$nome"

  ok=0
  for tentativa in $(seq 1 "$TENTATIVAS"); do
    tmp=$(mktemp)
    if curl -sfL --max-time 30 "$url" -o "$tmp" && valido "$tmp" "$arquivo"; then
      mv "$tmp" "$arquivo"
      echo "    atualizado ($(wc -c < "$arquivo") bytes)"
      ok=1
      break
    fi
    rm -f "$tmp"
    if [ "$tentativa" -lt "$TENTATIVAS" ]; then
      echo "    tentativa $tentativa falhou, esperando ${ESPERA}s"
      sleep "$ESPERA"
    fi
  done

  if [ "$ok" -eq 0 ]; then
    falhas=$((falhas + 1))
    if [ -f "$arquivo" ]; then
      echo "::warning::$nome não atualizou — mantendo a versão em cache"
    else
      echo "::error::$nome não atualizou e não existe versão em cache"
    fi
  fi
done < "$MANIFESTO"

echo
if [ "$falhas" -gt 0 ]; then
  echo "$falhas imagem(ns) não atualizaram. O README continua funcionando com o cache."
else
  echo 'Todas as imagens foram atualizadas.'
fi

exit 0
