#!/usr/bin/env bash
# Grava uma live do YouTube (ou outro site aceito pelo yt-dlp) em 1080p60.
#   gravar_live.sh <url> <pasta> [segundos=21600] [inicio=-3] [bloco_s]
# bloco_s: grava em blocos parte_000.mp4, parte_001.mp4... de bloco_s segundos. Cada bloco fechado já abre e
#          pode ser cortado com a live no ar (um .mp4 único dá "moov atom not found" até a gravação terminar).
# inicio: -3 = a partir de agora (padrão; grava até a live acabar ou até "segundos");
#          0 = desde o começo da janela que o YouTube guarda (~15 min atrás).
# Dica de economia: grave a live INTEIRA e analise no fim (menos rodadas com o Claude, mesmos cortes).
# Rode em segundo plano. Se a live cair e voltar, rode de novo noutra pasta.
export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Links"
URL="$1"; W="$2"; T="${3:-21600}"; IDX="${4:--3}"; BLOCO="$5"
[ -n "$URL" ] && [ -n "$W" ] || { echo "uso: gravar_live.sh <url> <pasta> [segundos] [inicio] [bloco_s]"; exit 1; }
RES="$(cd "$(dirname "$0")" && pwd)/lives_reserva.sh"
mkdir -p "$W"; cd "$W" || exit 1
# Reserva do streamer (lives_reserva.sh): se outra sessão já grava este canal, não grava (exit 3).
# GTA6_STREAMER força a chave; sem ela, a chave vem do canal da URL.
CH="${GTA6_STREAMER:-$(bash "$RES" chave "$URL")}"
if [ -z "$CH" ]; then echo "AVISO: canal da live não identificado; gravando SEM reserva" >&2
else
  bash "$RES" reservar "$CH" "$PWD"; rc=$?
  [ $rc -eq 3 ] && { echo "STREAMER JA EM GRAVACAO: escolha outra live"; exit 3; }
  if [ $rc -eq 0 ]; then
    ( while sleep 120; do bash "$RES" renovar "$CH" "$PWD" >/dev/null 2>&1; done ) & BATIDA=$!
    trap 'kill $BATIDA 2>/dev/null; bash "$RES" liberar "$CH" "$PWD" >/dev/null 2>&1' EXIT
  else echo "AVISO: reserva falhou (código $rc); gravando SEM reserva" >&2; fi
fi
yt-dlp --no-warnings -g -f "312+234/301+234/b[height<=1080][vcodec!=none][acodec!=none]/bv*[height<=1080]+ba" "$URL" > urls.txt || { echo "LIVE INDISPONIVEL"; exit 2; }
V=$(sed -n 1p urls.txt); A=$(sed -n 2p urls.txt)
# Twitch entrega video+audio juntos (1 URL): usa o audio do proprio video.
if [ -n "$A" ]; then AIN="-live_start_index $IDX -i $A"; AMAP=1:a; else AIN=; AMAP=0:a; fi
date "+%Y-%m-%d %H:%M:%S" > inicio.txt
echo "$URL" > origem.txt   # link da live (ficha: origem_url; inicio.txt = origem_inicio)
ffmpeg -v error -nostdin -live_start_index "$IDX" -i "$V" $AIN \
  -map 0:v -map $AMAP -c copy -t "$T" \
  $( [ -n "$BLOCO" ] && echo "-f segment -segment_time $BLOCO -reset_timestamps 1 -segment_format_options movflags=+frag_keyframe+empty_moov -y parte_%03d.mp4" || echo "-movflags +frag_keyframe+empty_moov -y live.mp4" )
# MP4 fragmentado: se a gravação cair, o bloco aberto continua legível até onde gravou.
touch FIM   # sinal para blocos_live.sh
echo "gravacao terminou:$(ls parte_*.mp4 live.mp4 2>/dev/null | tr '\n' ' ')"
