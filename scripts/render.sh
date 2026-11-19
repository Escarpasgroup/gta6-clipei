#!/usr/bin/env bash
# Renderiza uma edição a partir de um plano (veja assets/modelo-plano.sh).
#   render.sh <pasta>/plano.sh            -> renderiza <pasta>/final.mp4 (ou $OUT do plano)
#   render.sh <pasta>/plano.sh --mapa     -> só imprime o mapa tempo-original -> tempo-de-saída
# Etapa 1: cada trecho vira um arquivo com seu efeito (evita estourar memória).
# Etapa 2: concat + emojis + legendas ASS + áudio (voz, cortes, SFX) num passe só.
set -e
PLANO="$1"; MODO="$2"
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
cd "$(dirname "$PLANO")"

# valores padrão (o plano pode sobrescrever)
SRC=src.mp4; OUT=final.mp4; LEGENDAS=legendas.ass; FC_H=575; FPS=60
GANHO=1   # ganho geral do áudio final (ex.: 1.6 ≈ +4 dB quando o trecho sai baixo, alvo ~-12 LUFS)
SEGS=(); VOZ=(); SFX=(); EMOJI=(); IMG=(); VMEME=()
# Vídeo de origem HORIZONTAL (ex.: gravação 4K com a facecam sobreposta num canto):
#   LAYOUT = filtro que transforma cada quadro no vertical 1080x1920 (facecam em cima, jogo embaixo).
#            Use rótulos únicos que comecem com "l" ([lc][lg][lcam][lgm]) pra não colidir com os efeitos.
#   DEC    = opções de decodificação, ex.: DEC=(-hwaccel cuda) pra 4K.
#   AUDIO  = arquivo só com o áudio (extraído uma vez) pra não reler um vídeo gigante na etapa 2.
LAYOUT=""; DEC=(); AUDIO=""
MOLDURA=""; OPF="$SKILL/operacao.local"; [ -f "$OPF" ] && MOLDURA="$(tr -d '[:cntrl:]' < "$OPF")/marca/moldura.png"   # moldura da operação (instalar.sh grava operacao.local)
BASEFX=""  # filtro extra no áudio original antes dos memes, ex.: gravação baixa -> "dynaudnorm=f=150:g=15:m=30,volume=1.5"
. "$SKILL/scripts/_comum.sh"; pesado_inicio   # fila: um render por vez, prioridade baixa, modo FiveM (THREADS)
source "$(basename "$PLANO")"
command -v nvidia-smi >/dev/null 2>&1 || DEC=()   # sem placa NVIDIA (ex.: notebook): decodifica na CPU
[ -n "${GTA6_SEM_GPU:-}" ] && DEC=()   # FiveM aberto (modo leve): GPU fica para o jogo
[ -n "$AUDIO" ] || AUDIO="$SRC"
PRE="setpts=PTS-STARTPTS,fps=$FPS"; [ -n "$LAYOUT" ] && PRE="$PRE,$LAYOUT"

mkdir -p seg
mkdir -p fonts; cp -n "$SKILL/assets/fonts/"*.ttf fonts/ 2>/dev/null || true

# geometria: facecam em cima (0..FC_H), gameplay embaixo (FC_H..1920)
FC_CH=$(( (640*FC_H/1080)/2*2 ))          # recorte da facecam p/ zoom ~1.7x (640 x FC_CH)
GAME_H=$((1920-FC_H))
GAME_CH=$(( (720*GAME_H/1080)/2*2 ))      # recorte do gameplay p/ zoom 1.5x (720 x GAME_CH)
NORM="setsar=1,fps=$FPS,format=yuv420p"

# ---- zoom com movimento suave (subpixel, sem tremer) ----
# persp S CX CY: mostra a janela (W/S x H/S) centrada em (CX,CY) — presa dentro do quadro — na tela toda.
# S é uma expressão do fator de zoom; nela, "in" = número do quadro dentro do trecho (tempo = in/FPS).
persp() {
  local S="$1" cx="$2" cy="$3"
  local L="clip($cx-W/(2*$S),0,W-W/$S)" T="clip($cy-H/(2*$S),0,H-H/$S)"
  printf "perspective=x0='%s':y0='%s':x1='%s+W/%s':y1='%s':x2='%s':y2='%s+H/%s':x3='%s+W/%s':y3='%s+H/%s':interpolation=cubic:eval=frame" \
    "$L" "$T" "$L" "$S" "$T" "$L" "$T" "$S" "$L" "$S" "$T" "$S"
}
# curvas de zoom (d = duração do trecho na saída)
ease()  { local P="clip(in/($3*$FPS),0,1)"; echo "($1+($2-$1)*$P*$P*(3-2*$P))"; }          # z0 -> z1, suave nas duas pontas
punch() { local Q="clip(in/(0.6*$FPS),0,1)" z0="${3:-1}"; echo "($z0+($1-$z0)*(1-pow(1-$Q,3))+0.04*in/($2*$FPS))"; }  # de Z0 (padrão 1) até Z em 0,6 s, suave, e segue avançando bem devagar
# aplica o zoom só numa faixa: facecam (0..FC_H) ou jogo (FC_H..1920)
nafacecam() { echo "split[b][f];[f]crop=1080:$FC_H:0:0,$1[z];[b][z]overlay=0:0"; }
nojogo()    { echo "split[b][g];[g]crop=1080:$GAME_H:0:$FC_H,$1[z];[b][z]overlay=0:$FC_H"; }

dur_of() { # duração do trecho na saída
  case $3 in
    freeze|freezeface|freezepb|trava|travazoom|externo) echo "$2" ;;
    lento)      awk "BEGIN{print ($2-$1)*${4:-2}}" ;;   # câmera lenta: F vezes mais lento (padrão 2)
    rapido)     awk "BEGIN{print ($2-$1)/${4:-4}}" ;;   # acelerado (time-lapse): F vezes mais rápido (padrão 4)
    lentoface)  awk "BEGIN{print ($2-$1)*${5:-2}}" ;;
    wasted)     awk "BEGIN{print ($2-$1)*2}" ;;
    *) awk "BEGIN{print $2-$1}" ;;
  esac
}

# ---- mapa de tempos ----
t=0
echo "Mapa (original -> saída):"
for s in "${SEGS[@]}"; do
  read -r a b fx px py pz pw <<<"$s"
  d=$(dur_of "$a" "$b" "$fx" "$px" "$pw")
  e=$(awk "BEGIN{print $t+$d}")
  case $fx in freeze|freezeface|freezepb|trava|travazoom) src="congela @$a por ${d}s" ;; externo) src="$(basename "$a") ${d}s" ;; *) src="$a-$b" ;; esac
  printf "  %-24s %-11s -> %6.2f - %6.2f\n" "$src" "$fx" "$t" "$e"
  t=$e
done
TOTAL=$t
echo "  duração total: ${TOTAL}s"
[ "$MODO" = "--mapa" ] && exit 0

# ---- etapa 1: trechos ----
: > seg/list.txt
i=0
for s in "${SEGS[@]}"; do
  read -r a b fx px py pz pw <<<"$s"
  d=$(dur_of "$a" "$b" "$fx" "$px" "$pw")
  frames=$(awk "BEGIN{printf \"%d\", $d*$FPS-1}")
  # X Y dos efeitos de rosto = canto do recorte 640xFC_CH (como medido pelo detalhe.sh rosto) -> centro do rosto
  # (lento/rapido usam px como fator decimal, ex.: 1.8 — aí X/Y não existem e o cálculo é pulado)
  fcx=0; fcy=0; [[ "${px:-220}" =~ ^-?[0-9]+$ ]] && fcx=$(( ${px:-220} + 320 )); [[ "${py:-0}" =~ ^-?[0-9]+$ ]] && fcy=$(( ${py:-0} + FC_CH/2 ))
  TRAVA="trim=end_frame=1,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop=$frames"
  case $fx in
    none)       f="null" ;;
    boom)       f="scale=1188:2112,crop=1080:1920:x='54+45*sin(t*70)*max(0,1-t/0.6)':y='96+45*cos(t*55)*max(0,1-t/0.6)'" ;;
    face)       # aproxima SUAVE no rosto (0,6 s) de Z0 (padrão 1) até Z (padrão 1.35) e continua avançando bem devagar.
                # Use Z0 = zoom em que o trecho anterior terminou, pra não dar pulo (ex.: "face 280 86 1.4 1.12")
                f=$(nafacecam "$(persp "$(punch "${pz:-1.35}" "$d" "${pw:-1}")" $fcx $fcy)") ;;
    motion)     # movimento leve contínuo no rosto: zoom de Z0 até Z1 ao longo do trecho (ex.: 1 1.12 ou 1.3 1)
                f=$(nafacecam "$(persp "$(ease "${pz:-1}" "${pw:-1.12}" "$d")" $fcx $fcy)") ;;
    cabecudo)   # CABEÇUDO: cabeça dele 1,55x maior (máscara oval suave) balançando de leve + VOZ DE ESQUILO.
                # X Y = mesmo do face (centro do rosto); Z0 = zoom do trecho anterior, que se desfaz em 0,5 s sem pulo
                hx=$(( fcx - 160 )); hy=$(( fcy - 240 )); [ $hy -lt 0 ] && hy=0
                f="split[b][f];[f]crop=1080:$FC_H:0:0,split[fb][fh];[fh]crop=320:360:$hx:$hy,scale=496:558:flags=lanczos,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*clip((1-pow((X-W/2)/(W/2),2)-pow((Y-H/2)/(H/2),2))*4,0,1)',fade=t=in:st=0:d=0.15:alpha=1[hd];[fb][hd]overlay=x=$(( fcx - 248 )):y='$(( fcy - 262 ))+7*sin(t*10)':format=auto,format=yuv420p,$(persp "(1+(${pz:-1}-1)*(1-clip(in/(0.5*$FPS),0,1)))" $fcx $fcy)[z];[b][z]overlay=0:0" ;;
    fina)       # zoom no rosto com a cara inchada/distorcida (lente) + cor forte; o áudio fica com voz fina
                f="split[b][f];[f]crop=640:$FC_CH:$px:$py,scale=1350:-2,crop=1080:$FC_H,lenscorrection=k1=-0.7:k2=0.15:i=bilinear,eq=saturation=1.3[z];[b][z]overlay=0:0" ;;
    game)       # aproxima suave no jogo de Z0 (padrão 1) até Z (padrão 1.4); X Y = canto do recorte 720xGAME_CH no quadro inteiro.
                # Pra afastar de volta sem pulo: "game X Y 1.0 1.9". Ex. legenda do jogo (y≈1700): "game 180 1263 1.9"
                f=$(nojogo "$(persp "$(punch "${pz:-1.4}" "$d" "${pw:-1}")" $(( px + 360 )) $(( py - FC_H + GAME_CH/2 )))") ;;
    slowzoom)   # tensão: zoom que vai acelerando 1.0 -> 1.2 SÓ NO JOGO (a facecam fica inteira: o rosto dele é o conteúdo)
                f=$(nojogo "$(persp "(1+0.2*pow(clip(in/($d*$FPS),0,1),2))" 540 "(H*0.45)")") ;;
    fim)        # FINAL: aproxima acelerando no rosto (de Z0 até 3x) com rastro de movimento e escurece no fim.
                # Use com um whoosh no começo (pedido dele: "transição de final e um smooth com som")
                f="$(nafacecam "$(persp "(${pz:-1}+(3-${pz:-1})*pow(clip(in/($d*$FPS),0,1),2))" $fcx $fcy)"),tmix=frames=3,fade=t=out:st=$(awk "BEGIN{print $d-0.3}"):d=0.3" ;;
    crash)      f="scale=1242:2208,crop=1080:1920:x='81+75*sin(t*67)*max(0,1-t/1.3)':y='144+75*cos(t*53)*max(0,1-t/1.3)',fade=t=in:st=0:d=0.35:color=white" ;;
    freeze)     # congela, tira cor e dá zoom 1.1x só no jogo (a facecam fica intacta)
                gz=$(( (GAME_H*10/11)/2*2 )); gy=$(( FC_H + (GAME_H-gz)/2 ))
                f="$TRAVA,eq=saturation=0.35:contrast=1.15,split[fb][fg];[fg]crop=982:$gz:49:$gy,scale=1080:$GAME_H[fz];[fb][fz]overlay=0:$FC_H" ;;
    freezeface) f="$TRAVA,$(nafacecam "$(persp "$(punch "${pz:-1.6}" "$d" "${pw:-1}")" $fcx $fcy)")" ;;
    freezepb)   f="$TRAVA,$(nafacecam "$(persp "$(punch "${pz:-1.6}" "$d")" $fcx $fcy)"),hue=s=0,vignette=PI/4" ;;
    trava)      f="$TRAVA" ;;   # congela puro (colorido, sem zoom): meme "trava a tela"
    travazoom)  # trava + zoom de Z vezes no recorte que começa em (X,Y) do quadro inteiro, com leve avanço contínuo
                f="$TRAVA,$(persp "($pz*(1+0.08*in/($d*$FPS)))" "($px+540/$pz)" "($py+960/$pz)")" ;;
    pb)         f="hue=s=0,vignette=PI/4" ;;
    rapido)     f="setpts=PTS/${px:-4},fps=$FPS" ;;   # "rapido [F]": time-lapse F vezes mais rápido (2026-10-12); áudio acelerado junto, mais baixo
    lento)      f="setpts=${px:-2}*PTS,fps=$FPS" ;;   # "lento [F]": F vezes mais lento (1.5 = dá pra entender a fala; 2 = bem lento)
    lentoface)  # "lentoface X Y Z F": câmera lenta F vezes com o rosto num zoom fixo Z (replay de uma frase dele)
                f="setpts=${pw:-2}*PTS,fps=$FPS,$(nafacecam "$(persp "(${pz:-1.4}+0.04*in/($d*$FPS))" $fcx $fcy)")" ;;
    flash)      # "flash X Y Z": lembrança/reprise de uma frase dele — preto e branco, vinheta, rosto em zoom Z, voz com eco
                f="$(nafacecam "$(persp "(${pz:-1.3}+0.05*in/($d*$FPS))" $fcx $fcy)"),hue=s=0,vignette=PI/4" ;;
    wasted)     f="setpts=2*PTS,fps=$FPS,eq=saturation=0.12:contrast=1.12:brightness=-0.04,colorbalance=rs=0.12:gs=-0.04:bs=-0.04,$(nojogo "$(persp "$(ease 1 1.12 "$d")" 540 "(H*0.45)")")" ;;
    externo)    f="null" ;;   # "arquivo.mp4 DUR externo": trecho de OUTRO vídeo já vertical 1080x1920 (ex.: replay de uma live antiga), com o áudio dele
    *) echo "efeito desconhecido: $fx"; exit 1 ;;
  esac
  case $fx in
    freeze|freezeface|freezepb|trava|travazoom) inopt=("${DEC[@]}" -ss "$a" -t 0.2 -i "$SRC") ;;
    externo)           inopt=(-t "$b" -i "$a") ;;
    *)                 inopt=("${DEC[@]}" -ss "$a" -t "$(awk "BEGIN{print $b-$a}")" -i "$SRC") ;;
  esac
  name=$(printf "s%02d.mp4" $i)
  P1="${PRE//@A@/$a}"; [ "$fx" = externo ] && P1="setpts=PTS-STARTPTS,fps=$FPS,scale=1080:1920"
  ffmpeg -v error -filter_complex_threads "$THREADS" -y "${inopt[@]}" -an -filter_complex "[0:v]$P1,$f,$NORM" \
    -c:v libx264 -preset veryfast -crf 12 -threads "$THREADS" "seg/$name"
  # 03/11: o Windows às vezes trava o list.txt por um instante ("Device or resource busy") e o render morria -> tenta de novo
  for _ in 1 2 3 4 5 6 7 8 9 10; do { echo "file '$name'" >> seg/list.txt; } 2>/dev/null && break; sleep 1; done
  i=$((i+1))
done
echo "trechos renderizados: $i"

# ---- etapa 2: montagem ----
inputs=(-f concat -safe 0 -i seg/list.txt -i "$AUDIO")
fc=""
cur="0:v"; n=2
declare -A EXTIN; k=0
for s in "${SEGS[@]}"; do read -r a b fx _ <<<"$s"; [ "$fx" = externo ] && { inputs+=(-i "$a"); EXTIN[$k]=$n; n=$((n+1)); }; k=$((k+1)); done
for s in "${EMOJI[@]}"; do   # "arquivo.png tamanho x y_expr inicio fim"
  read -r png size ex ey t0 t1 <<<"$s"
  inputs+=(-loop 1 -t "$TOTAL" -framerate $FPS -i "$SKILL/assets/emoji/$png")
  fc+="[$n:v]scale=$size:$size:flags=lanczos,format=rgba[e$n];[$cur][e$n]overlay=x=$ex:y='$ey':enable='between(t,$t0,$t1)'[o$n];"
  cur="o$n"; n=$((n+1))
done
for s in "${IMG[@]}"; do     # imagem pronta (ex.: quadro congelado com zoom na legenda do jogo): "arquivo.png x y inicio fim"
  read -r png ix iy t0 t1 <<<"$s"
  inputs+=(-loop 1 -t "$TOTAL" -framerate $FPS -i "$png")
  fc+="[$n:v]format=rgba[i$n];[$cur][i$n]overlay=x=$ix:y=$iy:enable='between(t,$t0,$t1)'[o$n];"
  cur="o$n"; n=$((n+1))
done
# MEME EM VÍDEO por cima (assets/memes_video, ver INDICE.md lá):
#   "arquivo inicio_no_clipe duracao momento_na_saida x y largura chave vol [entrada]"
#   chave = cor do fundo verde em hex (ex.: 00ff00) ou "nao" (clipe sem fundo verde, entra como janelinha)
#   vol = volume do áudio do próprio meme (0 = mudo) · entrada = desliza (padrão) | pop
VMA=()
for s in "${VMEME[@]}"; do
  read -r vf vi vd vt vx vy vw vk vv ve <<<"$s"
  if [ "$vk" = "-" ]; then   # pronto (transparente e recortado por preparar_memes.sh)
    inputs+=(-i "$SKILL/assets/memes_video/prontos/$vf.mov"); key=""; borda=""
  else
    inputs+=(-i "$SKILL/assets/memes_video/$vf.mp4")
    key=""; [ "$vk" != "nao" ] && key="chromakey=0x$vk:0.26:0.08,"
    borda=""; [ "$vk" = "nao" ] && borda="pad=iw+16:ih+16:8:8:white,"
  fi
  if [ "${ve:-desliza}" = "pop" ]; then
    ent="scale=w='trunc($vw*min(1,0.3+0.7*(t-$vt)/0.18)/2)*2':h=-2:eval=frame,"
    ox="'$vx+($vw-overlay_w)/2'"; oy="'$vy+($vw*0.56-overlay_h)/2'"
  else
    ent="scale=$vw:-2,"; ox="'$vx+max(0,1-(t-$vt)/0.22)*1200'"; oy="$vy"
  fi
  fc+="[$n:v]trim=start=$vi:duration=$vd,setpts=PTS-STARTPTS+$vt/TB,fps=$FPS,${key}${borda}format=yuva420p,${ent}format=yuva420p[v$n];[$cur][v$n]overlay=x=$ox:y=$oy:eof_action=pass:enable='between(t,$vt,$vt+$vd)'[o$n];"
  [ "${vv:-0}" != "0" ] && VMA+=("$n $vi $vd $vt $vv")
  cur="o$n"; n=$((n+1))
done
# MOLDURA da operação (<operação>/marca/moldura.png): PNG 1080x1920 transparente por cima do vídeo, embaixo das legendas.
# Plano pode trocar (MOLDURA=outro.png) ou desligar (MOLDURA="").
if [ -n "$MOLDURA" ] && [ -f "$MOLDURA" ]; then
  inputs+=(-loop 1 -t "$TOTAL" -framerate $FPS -i "$MOLDURA")
  fc+="[$n:v]format=rgba[m$n];[$cur][m$n]overlay=0:0[o$n];"; cur="o$n"; n=$((n+1))
fi
fc+="[$cur]subtitles=$LEGENDAS:fontsdir=fonts[vout];"

# áudio base acompanha os trechos: congelamentos ficam em silêncio
nseg=${#SEGS[@]}
fc+="[1:a]asplit=$nseg"; for ((k=0;k<nseg;k++)); do fc+="[sa$k]"; done; fc+=";"
alabels=""
k=0
for s in "${SEGS[@]}"; do
  read -r a b fx px py pz pw <<<"$s"
  d=$(dur_of "$a" "$b" "$fx" "$px" "$pw")
  # AV_MS (layout/plano): voz atrasada em relação à boca na live do streamer (ms). Positivo = pega o áudio mais tarde.
  aa=$(awk "BEGIN{x=$a+${AV_MS:-0}/1000; print (x<0?0:x)}"); bb=$(awk "BEGIN{print $b+${AV_MS:-0}/1000}")
  case $fx in
    freeze|freezeface|freezepb|trava|travazoom) fc+="[sa$k]anullsink;anullsrc=r=44100:cl=stereo,atrim=0:$d[ab$k];" ;;
    externo) fc+="[sa$k]anullsink;[${EXTIN[$k]}:a]atrim=0:$d,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,afade=t=in:d=0.02,afade=t=out:st=$(awk "BEGIN{print $d-0.05}"):d=0.05[ab$k];" ;;
    rapido) F=${px:-4}; AT=$(awk -v f="$F" 'BEGIN{s=""; while(f>2.0001){s=s "atempo=2,"; f/=2} printf "%satempo=%.4f", s, f}')
      fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,$AT,volume=0.5,afade=t=in:d=0.015,afade=t=out:st=$(awk "BEGIN{print $d-0.015}"):d=0.015[ab$k];" ;;
    lento|lentoface|wasted) F=2; [ "$fx" = lento ] && F=${px:-2}; [ "$fx" = lentoface ] && F=${pw:-2}
      fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,atempo=$(awk "BEGIN{print 1/$F}"),afade=t=in:d=0.015,afade=t=out:st=$(awk "BEGIN{print $d-0.015}"):d=0.015[ab$k];" ;;
    flash) fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,aecho=0.8:0.6:140|260:0.35|0.2,afade=t=in:d=0.015,afade=t=out:st=$(awk "BEGIN{print $d-0.05}"):d=0.05[ab$k];" ;;
    fim) fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,afade=t=in:d=0.015,afade=t=out:d=$d[ab$k];" ;;
    fina|cabecudo) fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,asetrate=44100*1.45,aresample=44100,atempo=1/1.45,afade=t=in:d=0.015,afade=t=out:st=$(awk "BEGIN{print $d-0.015}"):d=0.015[ab$k];" ;;
    *) fc+="[sa$k]atrim=$aa:$bb,asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,afade=t=in:d=0.015,afade=t=out:st=$(awk "BEGIN{print $d-0.015}"):d=0.015[ab$k];" ;;
  esac
  alabels+="[ab$k]"; k=$((k+1))
done
fc+="${alabels}concat=n=$nseg:v=0:a=1"
for s in "${VOZ[@]}"; do      # "inicio fim ganho" (tempo de saída)
  read -r v0 v1 g <<<"$s"
  fc+=",volume=$g:enable='between(t,$v0,$v1)'"
done
[ -n "$BASEFX" ] && fc+=",$BASEFX"
fc+=",asplit=2[base][vozst];"   # vozst = só a voz/jogo (sem SFX) -> voz.wav, usado pelo alinhador de legendas

mix="[base]"; j=0
for s in "${VMA[@]}"; do      # áudio dos memes em vídeo
  read -r vn vi vd vt vv <<<"$s"; ms=$(awk "BEGIN{printf \"%d\", $vt*1000}")
  fc+="[$vn:a]atrim=$vi:$(awk "BEGIN{print $vi+$vd}"),asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,afade=t=out:st=$(awk "BEGIN{x=$vd-0.2; print (x<0?0:x)}"):d=0.2,volume=$vv,adelay=$ms|$ms[x$j];"
  mix+="[x$j]"; j=$((j+1))
done
for s in "${SFX[@]}"; do      # "arquivo inicio_no_arquivo duracao momento_na_saida volume"
  read -r name ss dur at vol fin <<<"$s"   # fin (opcional) = fade in em segundos
  inputs+=(-i "$SKILL/assets/sfx/$name.mp3")
  ms=$(awk "BEGIN{printf \"%d\", $at*1000}")
  fo=$(awk "BEGIN{x=$dur-0.4; print (x<0?0:x)}")
  fc+="[$n:a]atrim=$ss:$(awk "BEGIN{print $ss+$dur}"),asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo,${fin:+afade=t=in:d=$fin,}afade=t=out:st=$fo:d=0.4,volume=$vol,adelay=$ms|$ms[x$j];"
  mix+="[x$j]"; n=$((n+1)); j=$((j+1))
done
fc+="${mix}amix=inputs=$((j+1)):normalize=0:duration=first,volume=$GANHO,alimiter=limit=0.93[aout]"

printf '%s' "$fc" > graph.txt
ffmpeg -v error -stats -filter_complex_threads "$THREADS" -y "${inputs[@]}" -/filter_complex graph.txt \
  -map "[vout]" -map "[aout]" -shortest \
  -c:v libx264 -preset slow -crf 16 -profile:v high -pix_fmt yuv420p -r $FPS -threads "$THREADS" \
  -c:a aac -b:a 256k -movflags +faststart "$OUT" \
  -map "[vozst]" -ac 1 -ar 16000 voz.wav
echo "pronto: $(pwd)/$OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")s)"
