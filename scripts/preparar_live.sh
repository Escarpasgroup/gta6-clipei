#!/usr/bin/env bash
# Prepara uma gravação horizontal de live pra edição: proxy vertical leve + analisar.sh + candidatos.sh.
#   preparar_live.sh <pasta_com_live.mp4> <comum.sh>
# comum.sh = layout do streamer (SRC, FC_H, LAYOUT, DEC). Exemplo pronto: assets/layouts/max-vianna.sh.
# Pra outro streamer: copie o exemplo, meça a câmera (references/tecnico.md, "Vídeo HORIZONTAL") e ajuste o crop.
# Saída: src.mp4 (vertical), análise completa e candidatos.txt (os 12 melhores momentos, só texto).
SK="$(cd "$(dirname "$0")/.." && pwd)"
. "$SK/scripts/_comum.sh"; pesado_inicio   # proxy + análise: um por vez
W="$(cd "$1" && pwd)"; C="$2"
[ -f "$W/live.mp4" ] && [ -f "$C" ] || { echo "uso: preparar_live.sh <pasta_com_live.mp4> <comum.sh>"; exit 1; }
sed "s#^SRC=.*#SRC=$W/live.mp4#" "$C" > "$W/comum.sh"
cd "$W"; source comum.sh
touch plano.sh legendas.ass
mkdir -p fonts; cp -n "$SK/assets/fonts/"*.ttf fonts/ 2>/dev/null
# DEC (decodificar na GPU) só se houver NVIDIA; senão roda na CPU.
command -v nvidia-smi >/dev/null 2>&1 || DEC=(); [ -n "${GTA6_SEM_GPU:-}" ] && DEC=()
ffmpeg -v error -nostdin "${DEC[@]}" -i live.mp4 -filter_complex "[0:v]fps=30,$LAYOUT" \
  -c:v libx264 -preset ultrafast -crf 28 -threads "$THREADS" -c:a aac -b:a 128k -y src.mp4 || exit 1
bash "$SK/scripts/analisar.sh" src.mp4 . > analise.log 2>&1
bash "$SK/scripts/candidatos.sh" . 12 > candidatos.txt
echo "pronto: $W/candidatos.txt"
