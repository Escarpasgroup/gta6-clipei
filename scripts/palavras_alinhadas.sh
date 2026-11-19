#!/usr/bin/env bash
# Legenda UMA PALAVRA POR VEZ, sincronizada com a VOZ de verdade (2026-10-11: ele reclamou que a legenda
# aparecia antes de ele falar). Substitui o palavras.sh quando existe voz.wav.
#   palavras_alinhadas.sh falas.txt voz.wav [Y] >> legendas.ass
# falas.txt: "inicio fim [y=NNN] TEXTO" em tempo de SAÍDA (o início/fim podem ser aproximados, ±0,5 s).
# voz.wav: áudio base da saída (voz + jogo, SEM efeitos), gerado pelo render.sh a cada render.
# Como funciona: envelope de volume a cada 20 ms na faixa da voz (250–3500 Hz); em cada frase acha onde a fala
# realmente começa/termina e os trechos falados (pausas > 0,15 s ficam sem palavra), e distribui as palavras
# por sílabas SÓ dentro dos trechos falados. A palavra nunca aparece antes da fala.
F="$1"; W="$2"; Y="${3:-703}"
ENV=$(mktemp)
ffmpeg -v error -i "$W" -af "highpass=f=250,lowpass=f=3500,asetnsamples=320,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-" -f null - \
  | awk '/pts_time/{split($3,a,":");t=a[2]} /RMS/{split($0,b,"=");v=b[2]; if(v=="-inf")v=-90; printf "%.2f %.1f\n", t, v}' > "$ENV"
LC_ALL=C.UTF-8 awk -v Y="$Y" '
function sil(w,   n,i,c,prev,v){ w=tolower(w); n=0; prev=0
  for(i=1;i<=length(w);i++){ c=substr(w,i,1); v=(index("aeiouáéíóúâêôãõày",c)>0); if(v&&!prev)n++; prev=v }
  return (n<1?1:n) }
function ts(t,  h,m,s){ h=int(t/3600); m=int((t-h*3600)/60); s=t-h*3600-m*60; return sprintf("%d:%02d:%05.2f",h,m,s) }
function pct(arr,n,p,   i,j,tmp,k){ for(i=1;i<=n;i++) tmp[i]=arr[i]; for(i=2;i<=n;i++){k=tmp[i]; j=i-1; while(j>0&&tmp[j]>k){tmp[j+1]=tmp[j]; j--} tmp[j+1]=k} return tmp[int((n-1)*p)+1] }
FNR==NR { T[NR]=$1; P[NR]=10^($2/10); NE=NR; next }
FNR==1 { for(i=1;i<=NE;i++){ s=0;c=0; for(j=i-2;j<=i+2;j++) if(j>=1&&j<=NE){s+=P[j];c++} V[i]=10*log(s/c)/log(10) }   # média de 100 ms
           GF=pct(V,NE,0.10) }   # ruído de fundo do vídeo todo
NF>=3 { nf++; A[nf]=$1+0; B[nf]=$2+0; yy=Y; first=3
  if ($3 ~ /^y=[0-9]+$/) { yy=substr($3,3)+0; first=4 }
  YY[nf]=yy; txt=""; for(k=first;k<=NF;k++) txt=txt (k>first?" ":"") $k; TX[nf]=txt }
END {
  last=0
  for(f=1; f<=nf; f++){
    ws=A[f]-0.40; we=B[f]+0.60; if(f<nf && we>A[f+1]+0.10) we=A[f+1]+0.10; if(ws<last) ws=last
    # quadros da janela
    n=0; for(i=1;i<=NE;i++) if(T[i]>=ws && T[i]<=we){ n++; tt[n]=T[i]; vv[n]=V[i] }
    if(n<5){ on=A[f]; off=B[f]; nseg=1; s0[1]=on; s1[1]=off }
    else {
      pk=pct(vv,n,0.95); fl=pct(vv,n,0.20); if(fl>pk-10) fl=pk-10; thr=fl+(pk-fl)*0.25; if(thr<-50) thr=-50
      nseg=0; inside=0; gap=0
      for(i=1;i<=n;i++){
        if(vv[i]>thr){ if(!inside){ if(nseg>0 && tt[i]-s1[nseg]<0.15){ inside=1 } else { nseg++; s0[nseg]=tt[i]; inside=1 } } s1[nseg]=tt[i]+0.02 }
        else inside=0 }
      # descarta trechos muito curtos (cliques) e fora da frase
      m=0; for(k=1;k<=nseg;k++) if(s1[k]-s0[k]>=0.06){ m++; s0[m]=s0[k]; s1[m]=s1[k] } nseg=m
      if(nseg==0){ nseg=1; s0[1]=A[f]; s1[1]=B[f] }
      # nunca ANTES do início marcado (o problema era legenda adiantada): corta o que vier antes de A-0,05
      lim=A[f]-0.05; m=0; for(k=1;k<=nseg;k++){ if(s1[k]<=lim+0.06) continue; if(s0[k]<lim) s0[k]=lim; m++; s0[m]=s0[k]; s1[m]=s1[k] } if(m>0) nseg=m
    }
    tot=0; for(k=1;k<=nseg;k++) tot+=s1[k]-s0[k]
    nw=split(TX[f], w, " "); S=0; for(k=1;k<=nw;k++){ sy[k]=sil(w[k]); S+=sy[k] }
    acc=0
    for(k=1;k<=nw;k++){
      a=acc/S*tot; b=(acc+sy[k])/S*tot; acc+=sy[k]
      # mapeia tempo "falado" -> tempo real (pulando as pausas)
      st=-1; en=-1; run=0
      for(q=1;q<=nseg;q++){ d=s1[q]-s0[q]
        if(st<0 && a<=run+d+1e-6){ st=s0[q]+(a-run) }
        if(en<0 && b<=run+d+1e-6){ en=s0[q]+(b-run) }
        run+=d }
      if(st<0) st=s1[nseg]-0.16; if(en<0) en=s1[nseg]
      if(st<last) st=last; if(en<st+0.16) en=st+0.16
      word=toupper(w[k]); gsub(/[,.;:!?]+$/,"",word); gsub(/\.\.\.$/,"",word); if(w[k] ~ /[?!]$/) word=word substr(w[k],length(w[k]),1)
      printf "Dialogue: 1,%s,%s,Fala,,0,0,0,,{\\pos(540,%d)\\fscx88\\fscy88\\t(0,70,\\fscx104\\fscy104)\\t(70,130,\\fscx100\\fscy100)}%s\n", ts(st), ts(en), YY[f], word
      last=en }
  }
}' "$ENV" "$F"
rm -f "$ENV"
