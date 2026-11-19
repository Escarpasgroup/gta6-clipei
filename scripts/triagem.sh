#!/usr/bin/env bash
# Primeira passada barata sobre os blocos JÁ PRONTOS de uma gravação (bNNN/candidatos.txt do editar-video).
#   triagem.sh <pasta_gravacao> [--preparar <layout.sh>]
# Só lê arquivos de texto (candidatos.txt, volume.txt, transcricao.srt, info.txt). Não abre imagens nem vídeo.
# --preparar roda blocos_live.sh uma vez antes. NÃO use se outra sessão já vigia essa gravação (processaria o
#   mesmo bloco duas vezes).
# Cache/cursor: um arquivo por (origem + bloco + versão da triagem) em $DADOS/cache. Bloco já triado é pulado,
#   então rodar de novo com a live aberta só trata os blocos novos.
# Saída: fichas curtas (TSV) na tela e em $DADOS/triagem/<origem>.tsv; consumo em $DADOS/consumo.jsonl.
#   tipo=forte  : até FORTES_POR_HORA janelas por hora nova (as melhores do candidatos.sh)
#   tipo=amostra: ~AMOSTRA_FRACAO das fortes, de sinais fracos (silêncio seguido de reação) fora das fortes
#   borda=1     : janela a menos de 15 s do limite do bloco → abrir também o bloco vizinho (sobreposição)
set -euo pipefail
. "$(dirname "$0")/_comum.sh"
G="${1:?uso: triagem.sh <pasta_gravacao> [--preparar <layout.sh>]}"; G="$(cd "$G" && pwd)"
if [ "${2:-}" = --preparar ]; then bash "$SK/scripts/blocos_live.sh" "$G" "${3:?falta layout}" uma_vez || true; fi
ORIGEM="$(basename "$G")_$(tr -dc '0-9' < "$G/inicio.txt" 2>/dev/null || echo semdata)"
mkdir -p "$DADOS/triagem"; OUT="$DADOS/triagem/$ORIGEM.tsv"
[ -f "$OUT" ] || printf 'origem\tbloco\ttipo\tini_s\tfim_s\tini_origem_s\tborda\tsinal\tsinais\ttexto\n' > "$OUT"

novos=(); dur_total=0; offset=0; lacunas="chat: não capturado"
for B in "$G"/b[0-9][0-9][0-9]; do
  [ -d "$B" ] || continue
  # Blocos já triados podem ter sido apagados (limpeza do bruto): o início vem do número do bloco.
  # shortcut: supõe blocos de BLOCO_S (padrão 1200 s, o do gravar_live); mude BLOCO_S se gravar com outro tamanho.
  n=$(basename "$B"); offset=$(( 10#${n#b} * ${BLOCO_S:-1200} ))
  d=$(sed -n 's/^duration=//p' "$B/info.txt" 2>/dev/null | head -1 || true); d=${d%.*}  # bloco ainda em preparo não tem info.txt; d=${d:-1200}
  if [ -f "$B/candidatos.txt" ]; then
    k=$(printf '%s|%s|%s' "$ORIGEM" "$(basename "$B")" "$TRIAGEM_VERSAO" | sha1sum | cut -c1-16)
    if [ ! -f "$DADOS/cache/$k" ]; then novos+=("$B|$offset|$d|$k"); dur_total=$((dur_total + d)); fi
  fi
  offset=$((offset + d))
done
[ ${#novos[@]} -gt 0 ] || { echo "nada novo em $ORIGEM (cursor em dia)"; exit 0; }

fortes_bloco() { awk -v d="$1" -v h="$FORTES_POR_HORA" 'BEGIN{n=h*d/3600; print (n==int(n)?n:int(n)+1)}'; }
tmp=$(mktemp); n_fortes=0
for item in "${novos[@]}"; do
  IFS='|' read -r B off d k <<<"$item"; b=$(basename "$B"); nf=$(fortes_bloco "$d")
  [ -s "$B/transcricao.srt" ] || lacunas="$lacunas; $b: sem transcrição"
  [ -s "$B/volume.txt" ] || lacunas="$lacunas; $b: sem volume"
  # Fortes: linhas "#N  h:mm:ss–h:mm:ss (ini–fim s)  nota X  [sinais]" + linha de texto.
  awk -v o="$ORIGEM" -v b="$b" -v off="$off" -v d="$d" -v nf="$nf" '
    /^#[0-9]+ / && c<nf { match($0,/\(([0-9]+)–([0-9]+) s\)/,m); match($0,/nota ([0-9.]+)/,s); match($0,/\[(.*)\]/,w)
      i=m[1]; f=m[2]; c++; getline t; gsub(/\t/," ",t); sub(/^ +/,"",t)
      printf "%s\t%s\tforte\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n", o,b,i,f,off+i,(i<15||f>d-15),s[1],w[1],substr(t,1,120) }
  ' "$B/candidatos.txt" >> "$tmp"
  n_fortes=$((n_fortes + nf))
  # Sinal fraco: ≥4 s de silêncio (mediana-6 dB) seguido em até 2 s de pico (mediana+8 dB). Pode ser falso positivo.
  [ -s "$B/volume.txt" ] && awk -v o="$ORIGEM" -v b="$b" -v off="$off" -v d="$d" '
    { T[NR]=$1+0; V[NR]=$2+0; S[NR]=$2+0 } END {
      n=asort(S); med=S[int(n/2)+1]; q=0
      for(i=1;i<=NR;i++){ if(V[i]<med-6){q++; continue}
        if(q>=16){ for(j=i;j<=i+8&&j<=NR;j++) if(V[j]>med+8){ t=T[j]; i0=(t-12<0?0:t-12)
          printf "%s\t%s\tamostra_cand\t%d\t%d\t%d\t%d\t%.1f\tsilencio>reacao\t(sem texto: conferir quadros)\n", o,b,i0,t+13,off+i0,(i0<15||t+13>d-15),V[j]-med; break } }
        q=0 } }' "$B/volume.txt" >> "$tmp"
done

# Amostra: ~AMOSTRA_FRACAO das fortes (mín. 1), maior sinal, sem cobrir janela forte do mesmo bloco.
n_am=$(awk -v n="$n_fortes" -v f="$AMOSTRA_FRACAO" 'BEGIN{x=n*f; x=(x==int(x)?x:int(x)+1); print (x<1?1:x)}')
{ grep -P '\tforte\t' "$tmp" || true
  awk -F'\t' '$3=="forte"{F[$2]=F[$2] " " $4 "-" $5} $3=="amostra_cand"{ ok=1; split(F[$2],L," ")
      for(x in L){ split(L[x],r,"-"); if($4<r[2] && $5>r[1]) ok=0 } if(ok) print }' "$tmp" \
    | sort -t$'\t' -k8,8gr | head -n "$n_am" | sed 's/\tamostra_cand\t/\tamostra\t/'
} | tee -a "$OUT"
rm -f "$tmp"

for item in "${novos[@]}"; do IFS='|' read -r B off d k <<<"$item"; date +%s > "$DADOS/cache/$k"; done
jq -nc --arg o "$ORIGEM" --argjson n ${#novos[@]} --argjson s "$dur_total" --arg l "$lacunas" --arg ts "$(agora)" --arg m "$MAQUINA" \
  '{ts:$ts,maquina:$m,origem:$o,blocos_novos:$n,duracao_analisada_s:$s,tokens:null,
    etapas_caras:"proxy+Whisper por bloco (preparar_live.sh, fora do contexto); triagem só leu texto",lacunas:$l}' >> "$DADOS/consumo.jsonl"
echo "triados ${#novos[@]} blocos ($((dur_total/60)) min) de $ORIGEM · fortes ≤$n_fortes · amostra $n_am · lacunas: $lacunas" >&2
