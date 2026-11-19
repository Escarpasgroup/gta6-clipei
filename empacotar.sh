#!/usr/bin/env bash
# Gera o .zip da skill para passar a outra pessoa ou outro PC, sem nada local:
# tira operacao.local (caminho da sua operação) e assets/fonts (fontes do Windows, não redistribuir).
# Dados, memória, moldura, fila e segredos já ficam fora da skill (na pasta da operação) e não entram.
#   bash empacotar.sh <destino.zip>
set -euo pipefail
SK="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?uso: empacotar.sh <destino.zip>}"
TMP="$(mktemp -d)"; mkdir -p "$TMP/gta6-clipei"
cp -r "$SK/." "$TMP/gta6-clipei/"
rm -f "$TMP/gta6-clipei/operacao.local"; rm -rf "$TMP/gta6-clipei/assets/fonts"; mkdir -p "$TMP/gta6-clipei/assets/fonts"
# Confere que não vai segredo nem caminho pessoal.
if grep -rIl -E '[R]2_SECRET_ACCESS_KEY=[A-Za-z0-9]|[R]2_ACCESS_KEY_ID=[A-Za-z0-9]' "$TMP/gta6-clipei"; then echo "ABORTADO: segredo no pacote" >&2; exit 1; fi
DW="$(cygpath -w "$(cd "$(dirname "$DEST")" && pwd)")\\$(basename "$DEST")"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$TMP/gta6-clipei")' -DestinationPath '$DW' -Force"
echo "pacote: $DW ($(find "$TMP/gta6-clipei" -type f | wc -l) arquivos)"
