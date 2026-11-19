#!/usr/bin/env bash
# Cria a moldura do canal: PNG 1080x1920 transparente que o render.sh põe por cima de todo corte (embaixo das legendas).
#   criar_moldura.sh <saida.png> <@arroba> [cor_destaque=FF2E63] [cor_selo=111827] [previa_video.mp4 t_s previa.jpg]
# Desenho: cantoneiras finas nos 4 cantos na cor de destaque + selo escuro no alto à esquerda com uma barra de
# destaque e o @ do canal. Fica fora do centro (onde vão rosto, gancho e legenda) e fora da faixa de baixo
# (onde as redes põem a legenda do post). Troque as cores para criar a identidade do canal.
# Com previa_video: grava um quadro do vídeo com a moldura aplicada, para conferir antes de usar.
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?uso: criar_moldura.sh <saida.png> <@arroba> [cor_destaque] [cor_selo] [video t previa.jpg]}"
AR="$(printf '%s' "${2:?falta o @ do canal}" | tr -dc '@A-Za-z0-9._-')"
C1="${3:-FF2E63}"; C2="${4:-111827}"
[ -f "$SK/assets/fonts/seguibl.ttf" ] || { echo "Falta assets/fonts/seguibl.ttf (rode instalar.sh)" >&2; exit 1; }
OUTW="$(cygpath -m "$(cd "$(dirname "$OUT")" && pwd)")/$(basename "$OUT")"
L=130; T=8; M=28   # cantoneira: comprimento, espessura, margem
W=$((96 + 33*${#AR}))   # largura do selo cresce com o texto
cantos="drawbox=x=$M:y=$M:w=$L:h=$T:color=0x$C1:t=fill:replace=1,drawbox=x=$M:y=$M:w=$T:h=$L:color=0x$C1:t=fill:replace=1"
cantos+=",drawbox=x=$((1080-M-L)):y=$M:w=$L:h=$T:color=0x$C1:t=fill:replace=1,drawbox=x=$((1080-M-T)):y=$M:w=$T:h=$L:color=0x$C1:t=fill:replace=1"
cantos+=",drawbox=x=$M:y=$((1920-M-T)):w=$L:h=$T:color=0x$C1:t=fill:replace=1,drawbox=x=$M:y=$((1920-M-L)):w=$T:h=$L:color=0x$C1:t=fill:replace=1"
cantos+=",drawbox=x=$((1080-M-L)):y=$((1920-M-T)):w=$L:h=$T:color=0x$C1:t=fill:replace=1,drawbox=x=$((1080-M-T)):y=$((1920-M-L)):w=$T:h=$L:color=0x$C1:t=fill:replace=1"
selo="drawbox=x=58:y=58:w=$W:h=96:color=0x$C2@0.88:t=fill:replace=1,drawbox=x=58:y=58:w=12:h=96:color=0x$C1:t=fill:replace=1"
selo+=",drawtext=fontfile=fonts/seguibl.ttf:text='$AR':x=92:y=76:fontsize=52:fontcolor=white:shadowcolor=black@0.6:shadowx=2:shadowy=2"
cd "$SK/assets"
ffmpeg -v error -f lavfi -i "color=c=black@0.0:s=1080x1920,format=rgba" -frames:v 1 -vf "$cantos,$selo" -y "$OUTW"
echo "moldura: $OUTW"
if [ -n "${5:-}" ]; then
  ffmpeg -v error -ss "${6:-3}" -i "$5" -i "$OUTW" -frames:v 1 -filter_complex "[0:v]scale=1080:1920[v];[v][1:v]overlay,scale=540:-1" -y "$7"
  echo "prévia: $7"
fi
