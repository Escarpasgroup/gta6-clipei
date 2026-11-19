#!/usr/bin/env bash
# Análise inicial de um vídeo novo. Cria a pasta de trabalho e gera:
#   info (resolução/fps/duração), quadros_NN.jpg (tiras de 8 quadros com tempo),
#   volume.txt (volume a cada 0,25s), trechos pretos/silêncio, transcricao.srt (Whisper),
#   e um palpite da linha que separa facecam e gameplay.
# Uso: analisar.sh <video> <pasta_de_trabalho>
# A pasta de trabalho precisa ter caminho CURTO (ex.: $LOCALAPPDATA/Temp/vedit-nome).
set -e
VID="$1"; W="$2"
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
. "$SKILL/scripts/_comum.sh"; pesado_inicio   # Whisper é pesado: entra na mesma fila do render
# modelo em %LOCALAPPDATA%\editar-video (funciona com qualquer nome de usuário)
LA=$(cygpath -m "$LOCALAPPDATA")
MODEL="$(cygpath -u "$LOCALAPPDATA")/gta6-clipei/ggml-small.bin"
MODEL_FF="'${LA%%:*}\\:${LA#*:}/gta6-clipei/ggml-small.bin'"

mkdir -p "$W"
[ "$(realpath "$VID")" = "$(realpath "$W/src.mp4" 2>/dev/null)" ] || cp "$VID" "$W/src.mp4"
cd "$W"
[ -d fonts ] || cp -r "$SKILL/assets/fonts" fonts
[ -f plano.sh ] || cp "$SKILL/modelos/plano-exemplo.sh" plano.sh
[ -f legendas.ass ] || cp "$SKILL/modelos/legendas-exemplo.ass" legendas.ass

echo "== info"
ffprobe -v error -show_entries format=duration:stream=codec_type,width,height,r_frame_rate -of default=nw=1 src.mp4 | tee info.txt
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 src.mp4)

# quadros: 1 por segundo (ou espaçados p/ caber em ~96 quadros em vídeos longos)
STEP=$(awk "BEGIN{s=$DUR/96; print (s<1?1:int(s+0.999))}")
echo "== quadros: 1 a cada ${STEP}s -> quadros_NN.jpg (8 por tira)"
rm -f q_*.jpg quadros_*.jpg
ffmpeg -v error -i src.mp4 -vf "fps=1/$STEP:round=down,scale=360:640,drawtext=fontfile=fonts/arialbd.ttf:text='%{pts\:hms}':x=8:y=8:fontsize=30:fontcolor=yellow:box=1:boxcolor=black" -q:v 4 q_%03d.jpg
N=$(ls q_*.jpg | wc -l); r=0
for ((s=1; s<=N; s+=8)); do
  ffmpeg -v error -start_number $s -i q_%03d.jpg -vf "tile=8x1" -frames:v 1 -update 1 -y "$(printf quadros_%02d.jpg $r)"; r=$((r+1))
done
rm -f q_*.jpg
ls quadros_*.jpg | tr '\n' ' '; echo

echo "== trechos pretos (>=1s) e silêncios (>=2s)"
ffmpeg -i src.mp4 -vf "fps=5,scale=135:240,blackdetect=d=1:pix_th=0.10" -af "silencedetect=n=-45dB:d=2" -f null - 2>&1 \
  | grep -oE "black_start:[0-9.]+ black_end:[0-9.]+|silence_(start|end): [0-9.]+" | tr '\n' ' '; echo

echo "== volume a cada 0,25s -> volume.txt"
ffmpeg -v error -i src.mp4 -vn -af "asetnsamples=11025,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-" -f null - \
  | awk '/pts_time/{split($3,a,":");t=a[2]} /RMS/{split($0,b,"=");v=b[2]; if(v=="-inf")v=-90; printf "%6.2f %6.1f ",t,v; n=int((v+60)/2); for(i=0;i<n;i++)printf "#"; print ""}' > volume.txt
echo "(abra volume.txt; voz baixa ~-30dB, fala normal ~-18dB, gritos/explosões ~-8dB)"

echo "== divisa facecam/gameplay (maior salto de brilho entre linhas, média de 5 quadros)"
for p in 0.15 0.35 0.5 0.65 0.85; do
  ffmpeg -v error -ss $(awk "BEGIN{print $DUR*$p}") -i src.mp4 -frames:v 1 -vf "format=gray,scale=1:1920" -f rawvideo - | od -An -tu1 -w1 -v
done | awk '{r=(NR-1)%1920; v[r]+=$1} END{best=0;row=0; for(i=200;i<1500;i++){d=v[i]-v[i-1]; if(d<0)d=-d; if(d>best){best=d;row=i}} print "FC_H provável:", row, "(salto", best/5, ") — confira olhando um quadro"}'

echo "== transcrição (Whisper small, pt) -> transcricao.srt"
if [ -f "$MODEL" ]; then
  WL="${WHISPER_IDIOMA:-${IDIOMA:-pt}}"; WL="${WL%%-*}"   # Whisper só aceita o código curto ("pt"); "pt-BR" gera transcrição lixo
  MSYS_NO_PATHCONV=1 ffmpeg -v error -i src.mp4 -vn -af "aresample=16000,whisper=model=$MODEL_FF:language=$WL:queue=2:destination=transcricao.srt:format=srt" -f null -
  awk 'BEGIN{RS="";FS="\n"} {split($2,t," --> "); printf "%s  %s\n", substr(t[1],4,9), $3}' transcricao.srt
else
  echo "MODELO NÃO ENCONTRADO em $MODEL. Peça permissão ao usuário e baixe (~466 MB):"
  echo "  curl -L -o \"$MODEL\" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
fi
