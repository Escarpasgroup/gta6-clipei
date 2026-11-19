#!/usr/bin/env bash
# QA técnico de um corte renderizado (não muda o arquivo).
#   qa.sh <corte.mp4> [t_quadro_s saida.jpg]
# Confere 1080x1920, duração 15–45 s, fps e volume (-12,5 a -11 LUFS integrado, com folga de 0,5).
# Com t_quadro_s: grava um quadro com as áreas cobertas pela interface das redes desenhadas por cima
# (vermelho = TikTok, amarelo = Reels, azul = Shorts; medidas aproximadas, conferir no celular quando mudar o layout).
# Sai 0 se tudo passou; imprime "FALHA ..." para cada problema.
set -uo pipefail
F="${1:?uso: qa.sh <corte.mp4> [t saida.jpg]}"; r=0
IFS=, read -r w h fps < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 "$F" | tr -d '\r')
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$F")
lufs=$(ffmpeg -nostdin -hide_banner -i "$F" -af ebur128 -f null - 2>&1 | awk '/Integrated loudness/{f=1} f&&/I:/{print $2; exit}')
echo "resolução ${w}x${h} · fps $fps · duração ${dur%.*} s · volume ${lufs} LUFS"
[ "$w" = 1080 ] && [ "$h" = 1920 ] || { echo "FALHA resolução"; r=1; }
awk -v d="$dur" 'BEGIN{exit !(d>=15 && d<=45)}' || { echo "FALHA duração fora de 15–45 s"; r=1; }
awk -v l="$lufs" 'BEGIN{exit !(l>=-13 && l<=-10.5)}' || { echo "FALHA volume fora de -12,5 a -11 LUFS"; r=1; }
if [ -n "${2:-}" ]; then
  ffmpeg -v error -nostdin -ss "$2" -i "$F" -frames:v 1 -vf "\
drawbox=x=900:y=700:w=180:h=800:color=red@0.35:t=fill,drawbox=x=0:y=1600:w=1080:h=320:color=red@0.25:t=fill,\
drawbox=x=940:y=1100:w=140:h=600:color=yellow@0.35:t=fill,drawbox=x=0:y=1550:w=1080:h=370:color=yellow@0.2:t=fill,\
drawbox=x=930:y=900:w=150:h=700:color=blue@0.3:t=fill,drawbox=x=0:y=1500:w=1080:h=420:color=blue@0.15:t=fill,\
scale=540:-1" -y "$3" && echo "quadro com áreas da interface: $3"
fi
[ $r = 0 ] && echo "QA OK"; exit $r
