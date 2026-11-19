#!/usr/bin/env bash
# Ferramentas de detalhe pra acertar timing e enquadramento.
#
#   detalhe.sh quadros <pasta> <inicio> <duracao> [fps=10] [area=tudo|facecam|gameplay] [FC_H=575]
#       -> detalhe_<inicio>.jpg: grade de quadros com o tempo ORIGINAL escrito (achar a batida exata etc.)
#
#   detalhe.sh rosto <pasta> <FC_H> <t1> [t2 ...]
#       -> rosto.jpg: a facecam nesses tempos com grade de 100px (rótulos em px reais).
#          Ache o centro do rosto (nariz) em px reais: cx, cy. Para o efeito "face X Y":
#          X = cx - 320,  Y = cy - (altura_recorte/2), altura_recorte = (640*FC_H/1080) arredondado p/ par.
#          Mantenha 0 <= X <= 440 e 0 <= Y <= FC_H - altura_recorte.
#
#   detalhe.sh fala <pasta> <inicio> <duracao>
#       -> transcreve só esse trecho com janelas de 1s (timing fino das legendas), em tempo ORIGINAL.
#
#   detalhe.sh saida <pasta> <video> <t1> [t2 ...]
#       -> revisao.jpg: quadros do vídeo FINAL nesses tempos (conferir legendas/zooms antes de entregar)
#
#   detalhe.sh mapa <pasta> [passo=5]
#       -> mapa_NNN.jpg: o vídeo inteiro, 1 quadro a cada <passo> s, 36 por folha (12x3), com o tempo.
#          Pra vídeos longos: é o jeito de ver a história toda e achar os momentos. Pula trechos pretos.
#
#   detalhe.sh sinc <pasta> <inicio> [dur=6]
#       -> sinc_<inicio>.mp4: o trecho 5 vezes com a voz deslocada (-240..+240 ms). Quando a voz da live do streamer
#          vem atrasada/adiantada (OBS dele), escolha a que casa com a boca e grave AV_MS=<valor> no layout.
set -e
CMD="$1"; W="$2"; shift 2
cd "$W"
FONT=fonts/arialbd.ttf
LA=$(cygpath -m "$LOCALAPPDATA"); MODEL_FF="'${LA%%:*}\\:${LA#*:}/gta6-clipei/ggml-small.bin'"

case "$CMD" in
  mapa)
    passo=${1:-5}
    rm -rf _mapa; mkdir _mapa
    ffmpeg -v error -hwaccel cuda -i src.mp4 -vf "fps=1/$passo,scale=180:320,drawtext=fontfile=$FONT:text='%{pts\:hms}':x=3:y=3:fontsize=16:fontcolor=yellow:box=1:boxcolor=black" -q:v 5 _mapa/f_%04d.jpg
    # descarta quadros quase pretos (gravação vazia) e renumera
    k=0
    for f in _mapa/f_*.jpg; do
      m=$(ffmpeg -v error -i "$f" -vf "format=gray,scale=1:1" -f rawvideo - | od -An -tu1 | tr -d ' ')
      if [ "${m:-0}" -gt 12 ]; then k=$((k+1)); mv "$f" "$(printf _mapa/g_%04d.jpg $k)"; else rm -f "$f"; fi
    done
    rm -f mapa_*.jpg; n=0
    for ((s=1; s<=k; s+=36)); do
      ffmpeg -v error -start_number $s -i _mapa/g_%04d.jpg -frames:v 1 -vf "tile=12x3" -update 1 -y "$(printf mapa_%03d.jpg $n)"; n=$((n+1))
    done
    rm -rf _mapa
    echo "$n folhas (mapa_000.jpg ...), $k quadros com conteúdo" ;;
  quadros)
    a=$1; d=$2; fps=${3:-10}; area=${4:-tudo}; fch=${5:-575}
    case $area in
      facecam)  crop="crop=1080:$fch:0:0,scale=360:-2" ;;
      gameplay) crop="crop=1080:$((1920-fch)):0:$fch,scale=240:-2" ;;
      *)        crop="scale=180:320" ;;
    esac
    ffmpeg -v error -ss "$a" -t "$d" -i src.mp4 -vf "fps=$fps,$crop,drawtext=fontfile=$FONT:text='%{pts\:flt\:$a}':x=4:y=4:fontsize=18:fontcolor=yellow:box=1:boxcolor=black,tile=8x3" -frames:v 1 -update 1 -y "detalhe_$a.jpg"
    echo "detalhe_$a.jpg (até 24 quadros a partir de $a s)" ;;
  rosto)
    fch=$1; shift; k=0
    for t in "$@"; do
      ffmpeg -v error -ss "$t" -i src.mp4 -frames:v 1 -vf "crop=1080:$fch:0:0,drawgrid=w=100:h=100:t=2:c=yellow@0.7,drawtext=fontfile=$FONT:text='t=$t   grade=100px':x=8:y=8:fontsize=34:fontcolor=white:box=1:boxcolor=black,scale=540:-2" -update 1 -y "$(printf _r%02d.jpg $k)"
      k=$((k+1))
    done
    ffmpeg -v error -i _r%02d.jpg -vf "tile=2x$(( (k+1)/2 ))" -frames:v 1 -update 1 -y rosto.jpg
    rm -f _r*.jpg
    echo "rosto.jpg (cada quadro reduzido à metade: px real = px na imagem x 2; linhas da grade a cada 100px reais)" ;;
  fala)
    a=$1; d=$2
    WL="${WHISPER_IDIOMA:-${IDIOMA:-pt}}"; WL="${WL%%-*}"   # Whisper só aceita o código curto ("pt"); "pt-BR" gera transcrição lixo
    MSYS_NO_PATHCONV=1 ffmpeg -v error -ss "$a" -t "$d" -i src.mp4 -vn -af "aresample=16000,whisper=model=$MODEL_FF:language=$WL:queue=1:destination=_fala.srt:format=srt" -f null -
    awk -v off="$a" 'BEGIN{RS="";FS="\n"} {split($2,t," --> "); split(t[1],x,/[:,]/); s=x[1]*3600+x[2]*60+x[3]+x[4]/1000+off; printf "%6.2f  %s\n", s, $3}' _fala.srt
    rm -f _fala.srt ;;
  saida)
    vid=$1; shift; files=(); k=0
    for t in "$@"; do
      ffmpeg -v error -ss "$t" -i "$vid" -frames:v 1 -vf "scale=300:533,drawtext=fontfile=$FONT:text='$t':x=4:y=4:fontsize=20:fontcolor=yellow:box=1:boxcolor=black" -update 1 -y "_s$k.jpg"
      files+=(-i "_s$k.jpg"); k=$((k+1))
    done
    if [ $k -gt 1 ]; then ffmpeg -v error "${files[@]}" -filter_complex "hstack=inputs=$k" -update 1 -y revisao.jpg; else cp _s0.jpg revisao.jpg; fi
    rm -f _s*.jpg
    echo "revisao.jpg" ;;
  sinc)   # sinc <inicio> [dur=6]: o mesmo trecho do src.mp4 5 vezes, com a voz deslocada. Escolha no olho
          # (fone, boca do streamer falando de frente) a versão em que a boca bate e anote AV_MS no layout.
    t0=$1; du=${2:-6}; rm -f _sinc_*.mp4 _sinc.txt
    for o in -240 -120 0 120 240; do
      at=$(awk "BEGIN{x=$t0+$o/1000; print (x<0?0:x)}")
      ffmpeg -v error -nostdin -ss "$t0" -t "$du" -i src.mp4 -ss "$at" -t "$du" -i src.mp4 -map 0:v -map 1:a \
        -vf "scale=540:-2,drawtext=fontfile=$FONT:text='AV_MS=$o':x=10:y=10:fontsize=36:fontcolor=yellow:box=1:boxcolor=black" \
        -c:v libx264 -preset veryfast -crf 23 -r 30 -c:a aac -ar 44100 -ac 2 -y "_sinc_$o.mp4"
      echo "file '_sinc_$o.mp4'" >> _sinc.txt
    done
    ffmpeg -v error -nostdin -f concat -safe 0 -i _sinc.txt -c copy -y "sinc_$t0.mp4"; rm -f _sinc_*.mp4 _sinc.txt
    echo "$(pwd)/sinc_$t0.mp4: 5 versões de ${du}s, na ordem AV_MS = -240, -120, 0, +120, +240 ms" ;;
  *) echo "comando: quadros | rosto | fala | saida | mapa | sinc"; exit 1 ;;
esac
