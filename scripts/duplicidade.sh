#!/usr/bin/env bash
# Detecção de duplicidade no NOSSO histórico: impede repostar sem querer o mesmo vídeo, o mesmo áudio ou o mesmo
# trecho de live. NÃO serve para alterar um vídeo até ele "passar": se acusar duplicado, o corte não sai.
#
#   duplicidade.sh impressao <mp4>
#       → JSON {sha256, dur, vhash:[16 hex/seg], afp:[int]} (imagem: dHash 64 bits 1 quadro/s; áudio: Chromaprint)
#   duplicidade.sh checar <mp4> [event_id] [origem_chave ini_s fim_s]
#       → JSON {resultado, com, arquivo, video, audio}; sai 0 = nenhuma, 3 = duplicado (mesmo_arquivo|video|audio),
#         4 = trecho (mesmo momento da live já usado em outro corte: revisão manual)
#   duplicidade.sh registrar <mp4> <event_id> [origem_chave ini_s fim_s]
#       → grava no histórico (o publicador chama na entrega; histórico = tudo que já foi para a fila)
#   duplicidade.sh legado
#       → registra no histórico os cortes já agendados/postados (publicacoes.jsonl) que ainda não estão lá
# origem_chave = link da live (ou a pasta da gravação, sem link); ini_s/fim_s = tempo absoluto (epoch) ou relativo.
# Limiares: imagem ≥60% dos quadros com distância ≤10/64; áudio ≥0,80 de semelhança em ≥5 s; trecho ≥50% do menor.
set -euo pipefail
. "$(dirname "$0")/_comum.sh"
HIST="$DADOS/historico.jsonl"; touch "$HIST"

impressao() {
  local f="$1" sha dur vh af
  sha=$(sha256sum "$f" | cut -c1-64)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" | tr -d '\r')
  # dHash: 9x8 cinza, compara vizinhos na linha → 64 bits, em 2 metades de 32 (o awk usa double)
  vh=$(ffmpeg -v error -nostdin -i "$f" -an -vf "fps=1,scale=9:8:flags=area,format=gray" -f rawvideo - \
    | od -An -tu1 -v -w72 | awk '{h=0;l=0; for(r=0;r<8;r++)for(c=0;c<8;c++){b=($(r*9+c+1)<$(r*9+c+2)); k=r*8+c;
        if(k<32)h=h*2+b; else l=l*2+b} printf "%s\"%08x%08x\"", (NR>1?",":""), h, l}')
  af=$(ffmpeg -v error -nostdin -i "$f" -vn -ac 1 -f chromaprint -fp_format raw - 2>/dev/null \
    | od -An -tu4 -v -w4 | awk 'NF{printf "%s%s", (n++?",":""), $1}')
  printf '{"sha256":"%s","dur":%s,"vhash":[%s],"afp":[%s]}\n' "$sha" "${dur:-0}" "$vh" "$af"
}

# Compara a impressão nova (arquivo $1) com cada linha do histórico; imprime "idx video audio" (melhores notas).
comparar() {
  jq -s . "$HIST" | jq -r --slurpfile n "$1" --arg ev "$2" '
    def lin(i; o): "V \(i) \(o.vhash|join(" "))", "A \(i) \(o.afp|map(tostring)|join(" "))";
    lin(0; $n[0]), (to_entries[]|select(.value.event_id!=$ev)|lin(.key+1; .value))' \
  | awk '
    function pc(x){return T[x%65536]+T[int(x/65536)]}
    BEGIN{T[0]=0; for(i=1;i<65536;i++)T[i]=T[int(i/2)]+i%2}
    function hx(s){return strtonum("0x" s)}
    $1=="V"{ i=$2; nv[i]=NF-2; for(k=3;k<=NF;k++){ vh[i,k-3]=hx(substr($k,1,8)); vl[i,k-3]=hx(substr($k,9,8)) } ids[i]=1 }
    $1=="A"{ i=$2; na[i]=NF-2; for(k=3;k<=NF;k++) ap[i,k-3]=$k+0 }
    END{
      for(i in ids){ if(i==0)continue; bv=0; ba=0
        # imagem: melhor alinhamento por segundo
        for(o=-nv[i]; o<=nv[0]; o++){ m=0; t=0
          for(x=0;x<nv[0];x++){ y=x-o; if(y<0||y>=nv[i])continue; t++
            d=pc(xor(vh[0,x],vh[i,y]))+pc(xor(vl[0,x],vl[i,y])); if(d<=10)m++ }
          mn=(nv[0]<nv[i]?nv[0]:nv[i]); if(t>=5 && mn>0 && m/mn>bv) bv=m/mn }
        # áudio: semelhança média de bits no melhor alinhamento, sobreposição mínima ~5 s (40 itens)
        for(o=-na[i]; o<=na[0]; o+=1){ s=0; t=0
          for(x=0;x<na[0];x++){ y=x-o; if(y<0||y>=na[i])continue; t++; s+=32-pc(xor(ap[0,x],ap[i,y])) }
          if(t>=40){ v=s/(32*t); if(v>ba) ba=v } }
        printf "%d %.3f %.3f\n", i, bv, ba }
    }'
}

cmd_checar() {
  local f="$1" ev="${2:-}" ok="${3:-}" ini="${4:-}" fim="${5:-}" tmp; tmp=$(mktemp)
  impressao "$f" > "$tmp"
  local sha; sha=$(jq -r .sha256 "$tmp")
  local r; r=$(jq -cs --arg s "$sha" --arg ev "$ev" '[.[]|select(.sha256==$s and .event_id!=$ev)]|first//empty' "$HIST")
  if [ -n "$r" ]; then
    echo "$r" | jq -c '{resultado:"mesmo_arquivo",com:.event_id,arquivo,video:1,audio:1}'; rm -f "$tmp"; return 3
  fi
  local melhor; melhor=$(comparar "$tmp" "$ev" | awk '{s=($2>$3?$2:$3); if(s>b){b=s;l=$0}} END{print l}')
  rm -f "$tmp"
  if [ -n "$melhor" ]; then
    read -r i v a <<<"$melhor"
    local e; e=$(jq -cs --argjson i "$((i-1))" '.[$i]|{com:.event_id,arquivo}' "$HIST")
    if awk -v v="$v" -v a="$a" 'BEGIN{exit !(v>=0.6 || a>=0.80)}'; then
      local tipo=video; awk -v v="$v" -v a="$a" 'BEGIN{exit !(a>=0.80 && v<0.6)}' && tipo=audio
      echo "$e" | jq -c --arg t "$tipo" --argjson v "$v" --argjson a "$a" '{resultado:$t}+.+{video:$v,audio:$a}'; return 3
    fi
  fi
  if [ -n "$ok" ] && [ -n "$ini" ] && [ -n "$fim" ]; then
    r=$(jq -cs --arg k "$ok" --argjson i "$ini" --argjson f "$fim" --arg ev "$ev" '
      [.[]|select(.origem_chave==$k and .event_id!=$ev and .ini_s!=null)
        |select(([.fim_s,$f]|min)-([.ini_s,$i]|max) >= 0.5*([.fim_s-.ini_s,$f-$i]|min))]|first//empty' "$HIST")
    if [ -n "$r" ]; then echo "$r" | jq -c '{resultado:"trecho",com:.event_id,arquivo,video:null,audio:null}'; return 4; fi
  fi
  jq -nc --argjson v "${v:-0}" --argjson a "${a:-0}" '{resultado:"nenhuma",com:null,arquivo:null,video:$v,audio:$a}'
}

cmd_registrar() {
  local f="$1" ev="$2" ok="${3:-}" ini="${4:-null}" fim="${5:-null}" imp; imp=$(impressao "$f")
  travar
  echo "$imp" | jq -c --arg ev "$ev" --arg a "$(basename "$f")" --arg k "$ok" --argjson i "$ini" --argjson fm "$fim" \
    --arg ts "$(agora)" --arg m "$MAQUINA" \
    '{event_id:$ev,arquivo:$a,origem_chave:(if $k=="" then null else $k end),ini_s:$i,fim_s:$fm,ts:$ts,maquina:$m}+.' >> "$HIST"
  echo "histórico: $ev $(basename "$f")"
}

cmd_legado() {
  local PUB="$DADOS/publicacoes.jsonl" a ev f n=0
  while IFS=$'\t' read -r ev a; do
    jq -e --arg e "$ev" 'select(.event_id==$e)' "$HIST" >/dev/null 2>&1 && continue
    f="$FILA/postados/$a"; [ -f "$f" ] || f="$FILA/$a"; [ -f "$f" ] || { echo "sem arquivo: $a" >&2; continue; }
    cmd_registrar "$f" "$ev" >/dev/null; n=$((n+1)); trap - EXIT; rmdir "$DADOS/.trava" 2>/dev/null || true
  # arquivo: o primeiro não nulo do evento (as linhas "agendado" do registro podem vir sem ele)
  done < <(jq -rs 'group_by(.event_id)[]|select(any(.[]; .estado=="agendado" or .estado=="publicado"))
      |[.[0].event_id, ((map(.arquivo)|map(select(.!=null))|first) // (.[0].event_id|sub("^legado_";"")+".mp4"))]|@tsv' \
      "$PUB" | tr -d '\r')
  echo "legado: $n cortes registrados no histórico"
}

case "${1:-}" in
  impressao) impressao "$2" ;;
  checar) cmd_checar "$2" "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
  registrar) cmd_registrar "$2" "$3" "${4:-}" "${5:-null}" "${6:-null}" ;;
  legado) cmd_legado ;;
  *) sed -n '2,18p' "$0"; exit 1 ;;
esac
