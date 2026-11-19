#!/usr/bin/env bash
# Pré-seleção barata de momentos de uma live (só texto, sem imagens), pra olhar quadros apenas dos melhores.
#   candidatos.sh <pasta_analisada> [N=12] [janela_s=25]
# Usa transcricao.srt + volume.txt gerados pelo analisar.sh. Pontua janelas de tempo por:
#   reação na fala (palavrões, "meu deus", "que isso", "não!"...), risadas marcadas pelo Whisper,
#   picos de volume acima da mediana da live, e quantidade de fala. Imprime as N melhores janelas sem
#   sobreposição, com o texto, pra decidir quais conferir com `detalhe.sh quadros`.
# É só um filtro: a escolha final segue references/padroes-gta.md (precisa de virada e desfecho).
W="$1"; N="${2:-12}"; J="${3:-25}"
cd "$W" || exit 1
[ -f transcricao.srt ] && [ -f volume.txt ] || { echo "rode analisar.sh antes"; exit 1; }
LC_ALL=C.UTF-8 awk -v N="$N" -v J="$J" '
function hms(t){ return sprintf("%d:%02d:%02d", int(t/3600), int(t%3600/60), int(t%60)) }
FNR==NR { V[++nv]=$2+0; VT[nv]=$1+0; next }           # volume.txt: tempo dB
FNR==1 { # mediana do volume
  for(i=1;i<=nv;i++) S[i]=V[i]; n=nv
  for(i=2;i<=n;i++){k=S[i]; j=i-1; while(j>0&&S[j]>k){S[j+1]=S[j]; j--} S[j+1]=k}
  MED=S[int(n/2)+1]
}
{ # bloco do SRT: n / tempo / texto
  split($2,a," --> "); split(a[1],h,":"); gsub(",",".",h[3]); t=h[1]*3600+h[2]*60+h[3]
  txt=""; for(i=3;i<=NF;i++) txt=txt " " $i
  low=tolower(txt)
  if (low ~ /m[uú]sica|music|som de/) next
  nl++; LT[nl]=t; LX[nl]=txt
  s=0; why=""
  if (low ~ /risos|risada|kkk|haha|\*ri/) { s+=3; why=why "risada " }
  if (low ~ /caralho|porra|meu deus|que isso|n[aã]o,? n[aã]o|socorro|nossa|caraca|eita|vixi|mano do c|puta|fudeu|ai,? meu/) { s+=2.5; why=why "reação " }
  if (low ~ /!/) s+=0.5
  if (low ~ /consegui|ganhei|perdi|morri|bateu|capot|explod|fugi|pol[ií]cia|olha isso|n[aã]o acredito/) { s+=1.5; why=why "evento " }
  LS[nl]=s+0.4; LW[nl]=why
}
END {
  last = (nl ? LT[nl] : 0); if (VT[nv]>last) last=VT[nv]
  nw=0
  for (st=0; st+J<=last+J; st+=5) {
    sc=0; why=""; txt=""
    for (i=1;i<=nl;i++) if (LT[i]>=st && LT[i]<st+J) { sc+=LS[i]; if (LW[i]!="" && index(why,LW[i])==0) why=why LW[i]; txt=txt LX[i] " |" }
    lo=0; for (i=1;i<=nv;i++) if (VT[i]>=st && VT[i]<st+J && V[i]>MED+8) lo++
    sc+=lo/10; if (lo>0) why=why "pico(" lo ") "
    nw++; WS[nw]=st; WC[nw]=sc; WY[nw]=why; WT[nw]=txt
  }
  printf "volume mediano %.1f dB · janelas de %ds · melhores %d sem sobreposição:\n\n", MED, J, N
  for (k=1;k<=N;k++) {
    b=0; for (i=1;i<=nw;i++) if (!USED[i] && (b==0 || WC[i]>WC[b])) b=i
    if (b==0 || WC[b]<2) break
    for (i=1;i<=nw;i++) if (WS[i]>WS[b]-J && WS[i]<WS[b]+J) USED[i]=1
    printf "#%d  %s–%s (%d–%d s)  nota %.1f  [%s]\n   %s\n\n", k, hms(WS[b]), hms(WS[b]+J), WS[b], WS[b]+J, WC[b], WY[b], substr(WT[b],1,400)
  }
}' volume.txt RS= 'FS=\n' transcricao.srt
