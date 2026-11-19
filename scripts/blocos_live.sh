#!/usr/bin/env bash
# Prepara os blocos de uma live gravada com `gravar_live.sh ... <bloco_s>` assim que cada bloco fecha.
#   blocos_live.sh <pasta_da_gravacao> <layout.sh> [uma_vez]
# Para cada parte_NNN.mp4 já fechada (existe a parte seguinte, ou a gravação terminou), cria <pasta>/bNNN/
# com live.mp4 (link para a parte) e roda preparar_live.sh nela. Imprime "PRONTO <pasta>/bNNN" a cada bloco.
# Sem "uma_vez", fica vigiando até a gravação terminar (rode em segundo plano / Monitor).
SK="$(cd "$(dirname "$0")/.." && pwd)"
W="$1"; C="$2"; ONCE="$3"
[ -d "$W" ] && [ -f "$C" ] || { echo "uso: blocos_live.sh <pasta_da_gravacao> <layout.sh> [uma_vez]"; exit 1; }
while :; do
  ativo=1; [ -f "$W/FIM" ] && ativo=0   # gravar_live.sh cria FIM quando a gravação termina
  for p in "$W"/parte_*.mp4; do
    [ -f "$p" ] || continue
    n=$(basename "$p" .mp4); n=${n#parte_}
    prox="$W/parte_$(printf %03d $((10#$n + 1))).mp4"
    # bloco ainda sendo escrito: só a última parte enquanto grava
    [ -f "$prox" ] || [ $ativo = 0 ] || continue
    B="$W/b$n"
    [ -f "$B/candidatos.txt" ] && continue
    mkdir -p "$B"; ln -f "$p" "$B/live.mp4" 2>/dev/null || cp "$p" "$B/live.mp4"
    bash "$SK/scripts/preparar_live.sh" "$B" "$C" >/dev/null 2>&1 && echo "PRONTO $B" || echo "FALHOU $B (veja $B/analise.log)"
  done
  [ -n "$ONCE" ] || [ $ativo = 0 ] && break
  sleep 60
done
