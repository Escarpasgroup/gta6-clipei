#!/usr/bin/env bash
# Envia um vídeo para o Cloudflare R2 e imprime o link público (o Buffer exige URL pública e direta).
# Uso: bash enviar_r2.sh <video.mp4>
# Lê as chaves de <operação>/config/segredos.env (ou de R2_ENV). Só usa o curl do sistema (--aws-sigv4, curl >= 7.75).
set -euo pipefail

OPF="$(dirname "$0")/../operacao.local"
ENVF="${R2_ENV:-$( [ -f "$OPF" ] && tr -d '[:cntrl:]' < "$OPF")/config/segredos.env}"
[ -f "$ENVF" ] || { echo "Falta $ENVF (copie modelos/segredos.env.example)" >&2; exit 1; }
# tr tira o \r que o Bloco de Notas deixa no fim das linhas.
set -a; . <(tr -d '\r' < "$ENVF"); set +a
for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_URL; do
  [ -n "${!v:-}" ] || { echo "Variável $v vazia no .env" >&2; exit 1; }
done

ARQ="${1:?Uso: bash enviar_r2.sh <video.mp4>}"
[ -f "$ARQ" ] || { echo "Arquivo não encontrado: $ARQ" >&2; exit 1; }

# Nome único e seguro para URL: data-hora + nome original sem acentos/espaços.
BASE="$(basename "$ARQ" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || basename "$ARQ")"
BASE="$(printf '%s' "$BASE" | tr -c 'A-Za-z0-9._-' '_')"
CHAVE="$(date +%Y%m%d-%H%M%S)_$BASE"

curl -sS --fail-with-body -X PUT -T "$ARQ" \
  --aws-sigv4 "aws:amz:auto:s3" \
  --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" \
  -H "x-amz-content-sha256: UNSIGNED-PAYLOAD" \
  -H "Content-Type: video/mp4" \
  "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com/$R2_BUCKET/$CHAVE" >/dev/null

URL="${R2_PUBLIC_URL%/}/$CHAVE"
# Confere se o link público abre antes de entregar ao Buffer.
curl -sSfI "$URL" >/dev/null || { echo "Enviado, mas o link público não abriu: $URL (acesso público do bucket ligado?)" >&2; exit 1; }
echo "$URL"
