#!/usr/bin/env bash
# Registro da operação: fichas de candidatos, estado de publicação por rede, métricas.
# Arquivos JSONL em $DADOS (só acrescenta; o estado atual é a última linha de cada chave).
#
#   registro.sh candidato '<json>'                 ficha nova → imprime event_id, nota e decisão
#   registro.sh decidir <event_id> <decisao> <motivo>   revisão humana (ex.: revisao → fila)
#   registro.sh elegivel <event_id> <plataforma|todas>  sai 0 se pode entrar na fila nessa(s) rede(s)
#   registro.sh entregar <event_id> <arquivo.mp4>  marca "pendente" nas redes (depois de gravar .mp4 + .txt na fila)
#   registro.sh estado <event_id> <plataforma> <estado> [id_externo] [--conciliado]   só no PC publicador
#   registro.sh enviar <arquivo.mp4> <plataforma>  rodada de postagem: marca em_envio e imprime o event_id;
#                                                  sai ≠0 se já foi/está sendo enviado (não poste)
#   registro.sh importar                           lê os .feito da fila (só leitura) e marca "agendado"
#   registro.sh metrica <event_id> <plataforma> <1h|24h|72h> '<json>'
#   registro.sh ficha <event_id> | resumo | exportar | juntar <arquivo.jsonl>
#
# Conformidade (originalidade, direitos, duplicidade) — só corte "aprovado" na rede segue para postagem automática:
#   registro.sh autorizacao '<json>'               cadastro do streamer (modelos/autorizacao-exemplo.json)
#   registro.sh direitos <@canal> <plataforma>     → "aprovado|revisao_manual|bloqueado<TAB>motivo"
#   registro.sh editorial <event_id> '<json>'      análise criativa antes do render (modelos/editorial-exemplo.json)
#   registro.sh avaliar <event_id> <arquivo.mp4>   decide por rede: aprovado | revisao_manual | bloqueado (+ motivos)
#   registro.sh revisar <event_id> <plataforma|todas> <aprovado|bloqueado> "<motivo>"   decisão humana na revisão
#   registro.sh revisao                            fila de revisão manual (o que espera decisão e por quê)
#   registro.sh auditoria [event_id]               painel por corte (TSV em dados/auditoria.tsv)
#   registro.sh relatorio                          formatos/streamers com restrição, bloqueio ou baixa distribuição
#
# Estados de publicação: pendente, em_envio, agendado, publicado, revisao, falha, envio_incerto, restrito
# (restrito = a rede limitou/sinalizou o post depois de publicado; registre para o relatório).
# envio_incerto (timeout, resposta perdida) bloqueia nova tentativa: consulte a plataforma (list_posts) e só então
# marque agendado/publicado com o id externo, ou falha com --conciliado se confirmou que não existe post.
set -euo pipefail
. "$(dirname "$0")/_comum.sh"
CAND="$DADOS/candidatos.jsonl"; PUB="$DADOS/publicacoes.jsonl"; MET="$DADOS/metricas.jsonl"
AUT="$DADOS/autorizacoes.jsonl"; CTL="$DADOS/controle.jsonl"
touch "$CAND" "$PUB" "$MET" "$AUT" "$CTL"

erro() { echo "ERRO: $*" >&2; exit 1; }
# Ficha ativa do evento = a de maior nota (o melhor arco do mesmo acontecimento); empate = a mais recente
# (é assim que a análise editorial, gravada depois, vira a ficha ativa).
ativa() { jq -cs --arg e "$1" '[.[]|select(.event_id==$e and .decisao!="duplicado")]
  | if length==0 then empty else (map(.nota)|max) as $m | map(select(.nota==$m)) | last end' "$CAND"; }
ctl_estado() { jq -rs --arg e "$1" --arg p "$2" '[.[]|select(.event_id==$e and .plataforma==$p)]|last|.estado//"nenhum"' "$CTL"; }
ultimo_estado() { jq -rs --arg k "$1" '[.[]|select(.chave==$k)]|last|.estado//"nenhum"' "$PUB"; }
redes() { [ "$1" = todas ] && echo $PLATAFORMAS || echo "$1"; }

cmd_candidato() {
  local in="$1"
  echo "$in" | jq -e 'has("fonte") and has("criador") and has("categoria") and has("origem_ini_ms") and has("origem_fim_ms")
    and has("gancho") and has("contexto") and has("desfecho") and has("fatores") and has("confianca") and has("direitos")
    and has("risco_spoiler") and (.fatores|has("gancho") and has("compreensao") and has("novidade") and has("progressao")
    and has("legibilidade") and has("compartilhamento")) and ([.fatores[]]|all(type=="number" and .>=0 and .<=5))' >/dev/null \
    || erro "ficha incompleta (veja references/2-selecao.md)"
  travar
  # Mesmo acontecimento = mesma fonte e intervalos que se cobrem em ≥50% do menor (corte deslocado alguns segundos).
  local ev
  ev=$(jq -rs --argjson n "$in" '[.[]|select(.fonte==$n.fonte)
      |select(([.origem_fim_ms,$n.origem_fim_ms]|min)-([.origem_ini_ms,$n.origem_ini_ms]|max)
              >= 0.5*([.origem_fim_ms-.origem_ini_ms,$n.origem_fim_ms-$n.origem_ini_ms]|min))]|first|.event_id//empty' "$CAND")
  [ -n "$ev" ] || ev="ev_$(printf '%s|%s' "$(echo "$in"|jq -r .fonte)" "$(echo "$in"|jq -r .origem_ini_ms)" | sha1sum | cut -c1-10)"
  local melhor; melhor=$(ativa "$ev" | jq -r '.nota//-1'); [ -n "$melhor" ] || melhor=-1
  echo "$in" | jq -c --arg ev "$ev" --arg ts "$(agora)" --arg maq "$MAQUINA" --arg conta "$CONTA" \
      --argjson lf "$LIMIAR_FILA" --argjson lr "$LIMIAR_REVISAO" --argjson melhor "$melhor" '
    .event_id=$ev | .ts=$ts | .maquina=$maq | .destino=(.destino//$conta)
    | .duracao_ms=(.origem_fim_ms-.origem_ini_ms)
    | .nota=((.fatores.gancho*20 + .fatores.compreensao*15 + .fatores.novidade*15 + .fatores.progressao*25
              + .fatores.legibilidade*15 + .fatores.compartilhamento*10)/5 | round)
    | (.riscos//[]) as $r
    | if (.desfecho//"")=="" then .decisao="aguardando_desfecho" | .motivo="sem desfecho visível ainda"
      elif ((.contexto_faltante//"")!="" and .fatores.compreensao<=2) then .decisao="retido" | .motivo="sem contexto: "+.contexto_faltante
      elif ($r|index("dado_pessoal")) or ($r|index("autenticidade")) then .decisao="retido" | .motivo="risco: "+($r|join(","))
      elif .nota>=$lf and .direitos!="ok" then .decisao="retido" | .motivo="direitos: "+.direitos
      elif .nota>=$lf then .decisao="fila" | .motivo="nota ≥ \($lf), aguarda QA"
      elif .nota>=$lr then .decisao="revisao" | .motivo="nota \($lr)–\($lf-1): segunda leitura"
      elif (.amostra//false) then .decisao="calibracao" | .motivo="amostra exploratória abaixo de \($lr)"
      else .decisao="descarte" | .motivo="nota < \($lr)" end
    | if $melhor>=0 and .nota<=$melhor then .decisao="duplicado" | .motivo="mesmo evento já tem arco com nota \($melhor)" else . end
  ' >> "$CAND"
  tail -1 "$CAND" | jq -r '"\(.event_id)\tnota \(.nota)\t\(.decisao)\t\(.motivo)"'
}

cmd_decidir() {
  local f; f=$(ativa "$1"); [ -n "$f" ] || erro "evento $1 não existe"
  travar
  # +0.001 na nota: a decisão humana passa a ser a ficha ativa do evento.
  echo "$f" | jq -c --arg d "$2" --arg m "$3" --arg ts "$(agora)" --arg maq "$MAQUINA" \
    '.decisao=$d | .motivo="humano: "+$m | .ts=$ts | .maquina=$maq | .nota=(.nota+0.001)' >> "$CAND"
  echo "$1 → $2"
}

# Sai 0 se ao menos uma rede pode receber o corte: controle "aprovado" nela e nada enviado ainda.
# Imprime "sim: <redes>" e um "não: ..." por rede recusada.
cmd_elegivel() {
  local f; f=$(ativa "$1"); [ -n "$f" ] || { echo "não: evento desconhecido"; return 1; }
  local p e c sim=""
  for p in $(redes "$2"); do
    c=$(ctl_estado "$1" "$p"); e=$(ultimo_estado "$1|$CONTA|$p")
    if [ "$c" != aprovado ]; then echo "não: $p está '$c' no controle (registro.sh avaliar/revisar)"
    elif [ "$e" != nenhum ]; then echo "não: $p já está '$e'"
    else sim+=" $p"; fi
  done
  [ -n "$sim" ] && { echo "sim:$sim"; return 0; }; return 1
}

# ---- Conformidade ----
cmd_autorizacao() {
  echo "$1" | jq -e '(.apelido|type=="string" and length>0) and (.canal|type=="string" and startswith("@"))
    and (.plataformas|type=="array") and (.edicao|type=="boolean") and (.republicacao|type=="boolean")
    and (.monetizacao|IN("sim","nao","desconhecido")) and (.evidencia|type=="object")' >/dev/null 2>&1 \
    || erro "autorização incompleta (veja modelos/autorizacao-exemplo.json)"
  travar
  echo "$1" | jq -c --arg ts "$(agora)" --arg m "$MAQUINA" '{nome:"",restricoes:"",validade:null}+.+{ts:$ts,maquina:$m}' >> "$AUT"
  echo "autorização gravada: $(echo "$1" | jq -r .canal) (vale a mais recente)"
}

cmd_direitos() {
  local a; a=$(jq -cs --arg c "$1" '[.[]|select((.canal|ascii_downcase)==($c|ascii_downcase))]|last//empty' "$AUT")
  [ -n "$a" ] || { printf 'bloqueado\tsem autorização cadastrada para %s\n' "$1"; return; }
  echo "$a" | jq -r --arg r "$2" --arg hoje "$(TZ="${FUSO_POSIX:-<-03>3}" date +%F)" --arg mon " ${MONETIZA:-} " '
    ($mon|contains(" "+$r+" ")) as $m
    | if (.validade!=null and .validade < $hoje) then "bloqueado\tautorização vencida em \(.validade)"
      elif (any(.plataformas[]; .==$r)|not) then "bloqueado\tautorização não cobre \($r)"
      elif (.edicao!=true or .republicacao!=true) then "bloqueado\tsem permissão de edição e republicação"
      elif $m and .monetizacao=="nao" then "bloqueado\tmonetização não autorizada (conta monetizada em \($r))"
      elif ((.evidencia.ref//"")=="") then "revisao_manual\tautorização sem evidência registrada"
      elif $m and .monetizacao!="sim" then "revisao_manual\tmonetização não confirmada (conta monetizada em \($r))"
      else "aprovado\tautorizado (\(.evidencia.tipo//"evidência") \(.evidencia.data//""))"
        + (if (.restricoes//"")!="" then "; condição: \(.restricoes)" else "" end) end'
}

# Legenda, zoom, transição, velocidade, borda, moldura e marca-d'água NÃO contam como contribuição editorial.
cmd_editorial() {
  local f; f=$(ativa "$1"); [ -n "$f" ] || erro "evento $1 não existe"
  echo "$2" | jq -e '(.contexto|type=="string") and (.historia|type=="boolean") and (.abertura|type=="string")
    and (.contribuicoes|type=="array") and (.fala_preservada|type=="boolean")' >/dev/null 2>&1 \
    || erro "editorial incompleto (veja modelos/editorial-exemplo.json)"
  travar
  echo "$f" | jq -c --argjson e "$2" --arg ts "$(agora)" --arg m "$MAQUINA" '
    ["contexto","analise","comentario","explicacao","humor","narracao"] as $subst
    | ["contexto","analise","explicacao","narracao"] as $info
    | ($e.contribuicoes|map(select((.tipo|IN($subst[])) and (.texto//"")!="" and (.base//"")!=""))) as $ok
    | ($e.contribuicoes|map(select((.tipo|IN($subst[]))|not)|.tipo)) as $cosm
    | ($ok|map(select(.tipo|IN($info[])))|length) as $ni
    | .editorial=($e + {validas:($ok|length), informativas:$ni, ignoradas:$cosm,
        nivel:(if ($e.fala_preservada|not) or ($e.inventado//false) then "bloqueado"
               elif ($ok|length)>=2 and $ni>=1 and $e.abertura!="" then "editorial"
               elif ($ok|length)>=1 then "leve" else "reutilizado" end)})
    | .ts=$ts | .maquina=$m' >> "$CAND"
  tail -1 "$CAND" | jq -r '"\(.event_id)\teditorial: \(.editorial.nivel) (\(.editorial.validas) contribuições, \(.editorial.informativas) informativas)"
    + (if (.editorial.ignoradas|length)>0 then "; não contam: "+(.editorial.ignoradas|join(",")) else "" end)'
}

cmd_avaliar() {
  local ev="$1" mp4="$2" f; f=$(ativa "$ev"); [ -n "$f" ] || erro "evento $ev não existe"
  [ -f "$mp4" ] || erro "arquivo não encontrado: $mp4"
  local G="" dec mot riscos nivel url ini0 ok ini fim dup rcd q rcq dur
  add() { G+="$1"$'\t'"$2"$'\n'; }
  dec=$(jq -r .decisao <<<"$f"); mot=$(jq -r '.motivo//""' <<<"$f"); riscos=$(jq -r '(.riscos//[])|join(",")' <<<"$f")
  case "$dec" in
    fila|aprovado) ;;
    revisao) add revisao_manual "nota $(jq -r .nota <<<"$f"): segunda leitura" ;;
    retido) case "$mot" in direitos:*) ;;   # direito agora vem do cadastro, por rede
              *) if grep -qE 'dado_pessoal|autenticidade' <<<"$riscos"; then add bloqueado "retido: $mot"; else add revisao_manual "retido: $mot"; fi ;; esac ;;
    *) add bloqueado "decisão da seleção: $dec ($mot)" ;;
  esac
  nivel=$(jq -r '.editorial.nivel//"nenhum"' <<<"$f")
  case "$nivel" in
    editorial) ;;
    nenhum) add revisao_manual "sem análise editorial (registro.sh editorial)" ;;
    bloqueado) add bloqueado "editorial: fala alterada ou fato inventado" ;;
    *) add revisao_manual "material reutilizado: contribuição editorial $nivel" ;;
  esac
  if grep -qE 'dado_pessoal|autenticidade' <<<"$riscos"; then add bloqueado "riscos: $riscos"
  elif [ -n "$riscos" ]; then add revisao_manual "riscos: $riscos"; fi
  [ "$(jq -r '.risco_spoiler//false' <<<"$f")" = true ] && add revisao_manual "spoiler de história"
  url=$(jq -r '.origem_url//""' <<<"$f"); ini0=$(jq -r '.origem_inicio//""' <<<"$f")
  [ -n "$url" ] || add revisao_manual "sem link da live de origem (origem_url)"
  ok="${url:-$(jq -r .fonte <<<"$f")}"
  local base=0; [ -n "$ini0" ] && base=$(TZ="${FUSO_POSIX:-<-03>3}" date -d "$ini0" +%s 2>/dev/null || echo 0)
  ini=$(jq -r --argjson b "$base" '$b + .origem_ini_ms/1000' <<<"$f"); fim=$(jq -r --argjson b "$base" '$b + .origem_fim_ms/1000' <<<"$f")
  rcd=0; dup=$(bash "$(dirname "$0")/duplicidade.sh" checar "$mp4" "$ev" "$ok" "$ini" "$fim") || rcd=$?
  case $rcd in
    0) ;;
    3) add bloqueado "duplicado ($(jq -r .resultado <<<"$dup")) de $(jq -r .com <<<"$dup")" ;;
    4) add revisao_manual "trecho da live já usado em $(jq -r .com <<<"$dup")" ;;
    *) add revisao_manual "duplicidade não verificada"; dup='{"resultado":"erro"}' ;;
  esac
  rcq=0; q=$(bash "$(dirname "$0")/qa.sh" "$mp4" 2>&1) || rcq=$?
  [ $rcq = 0 ] || add revisao_manual "QA: $(grep FALHA <<<"$q" | tr '\n' ' ')"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4" | tr -d '\r')
  local p L est v pmin pmax tmax hmax txt
  travar
  for p in $PLATAFORMAS; do
    L="$G"; L+="$(cmd_direitos "$(jq -r .criador <<<"$f")" "$p")"$'\n'
    v="PERFIL_$p"; read -r pmin pmax tmax hmax <<<"${!v:-15 60 2200 3}"
    awk -v d="$dur" -v a="$pmin" -v b="$pmax" 'BEGIN{exit !(d>=a && d<=b)}' || L+="revisao_manual"$'\t'"duração ${dur%.*}s fora do perfil $p ($pmin–$pmax s)"$'\n'
    txt="${mp4%.mp4}.$p.txt"; [ -f "$txt" ] || txt="${mp4%.mp4}.txt"
    if [ ! -f "$txt" ]; then L+="revisao_manual"$'\t'"sem texto do post"$'\n'
    else
      [ "$(tr -d '\r' < "$txt" | wc -m)" -le "$tmax" ] || L+="revisao_manual"$'\t'"texto acima de $tmax caracteres em $p"$'\n'
      [ "$(grep -o '#[^ #]*' "$txt" | wc -l)" -le "$hmax" ] || L+="revisao_manual"$'\t'"mais de $hmax hashtags em $p"$'\n'
      [ "$p" != youtube ] || [ "$(head -1 "$txt" | tr -d '\r' | wc -m)" -le 101 ] || L+="revisao_manual"$'\t'"título do YouTube acima de 100 caracteres"$'\n'
    fi
    jq -Rnc --arg e "$ev" --arg p "$p" --arg a "$(basename "$mp4")" --argjson d "$dup" --arg n "$nivel" --arg ts "$(agora)" --arg m "$MAQUINA" '
      [inputs|select(length>0)|split("\t")|{n:.[0],t:.[1]}] as $l
      | ($l|map(select(.n!="aprovado"))) as $prob
      | {event_id:$e, plataforma:$p,
         estado:(if any($l[]; .n=="bloqueado") then "bloqueado" elif ($prob|length)>0 then "revisao_manual" else "aprovado" end),
         motivos:(if ($prob|length)>0 then $prob|map(.t) else $l|map(.t) end),
         arquivo:$a, duplicidade:$d, editorial:$n, por:"auto", ts:$ts, maquina:$m}' <<<"$L" >> "$CTL"
    tail -1 "$CTL" | jq -r '"\(.plataforma)\t\(.estado)\t\(.motivos|join("; "))"'
  done
}

cmd_revisar() {
  local ev="$1" novo="$3" mot="$4" p c
  case "$novo" in aprovado|bloqueado) ;; *) erro "decisão deve ser aprovado ou bloqueado" ;; esac
  [ -n "$mot" ] || erro "informe o motivo da decisão"
  travar
  for p in $(redes "$2"); do
    c=$(ctl_estado "$ev" "$p")
    if [ "$novo" = aprovado ] && [ "$c" != revisao_manual ]; then
      echo "$p: está '$c' — só sai da revisão manual para aprovado (bloqueado: corrija a causa e avalie de novo)"; continue
    fi
    local l; l=$(jq -sc --arg e "$ev" --arg p "$p" --arg s "$novo" --arg mo "$mot" --arg ts "$(agora)" --arg m "$MAQUINA" \
      '[.[]|select(.event_id==$e and .plataforma==$p)]|last|.estado=$s|.motivos=(.motivos+["humano: "+$mo])|.por="humano"|.ts=$ts|.maquina=$m' "$CTL")
    echo "$l" >> "$CTL"
    echo "$p: $c → $novo"
  done
}

cmd_revisao() {
  jq -rs 'group_by(.event_id+"|"+.plataforma)|map(last)|map(select(.estado=="revisao_manual"))
    |if length==0 then "fila de revisão vazia" else .[]|"\(.event_id)\t\(.plataforma)\t\(.arquivo)\t\(.motivos|join("; "))" end' "$CTL"
}

cmd_auditoria() {
  { printf 'event_id\tstreamer\torigem_url\torigem_inicio\ttrecho_s\tautorizacao\tcontribuicoes\tnivel_editorial\tduplicidade\triscos\tredes_aprovadas\tpublicacao\tjustificativa\n'
    jq -rs --slurpfile ctl "$CTL" --slurpfile pub "$PUB" --slurpfile aut "$AUT" --arg ev "${1:-}" '
      (group_by(.event_id)|map((map(.nota)|max) as $m|map(select(.nota==$m))|last)) as $fichas
      | ($fichas|map(.event_id)) as $ids
      | ($fichas[]|select($ev=="" or .event_id==$ev)|. as $f
        | ([$ctl[]|select(.event_id==$f.event_id)]|group_by(.plataforma)|map(last)) as $c
        | ([$pub[]|select(.event_id==$f.event_id)]|group_by(.plataforma)|map(last)) as $p
        | ([$aut[]|select((.canal|ascii_downcase)==($f.criador|ascii_downcase))]|last) as $a
        | [.event_id, .criador, (.origem_url//"—"), (.origem_inicio//"—"),
           "\(.origem_ini_ms/1000|floor)–\(.origem_fim_ms/1000|floor)",
           (if $a then "\($a.plataformas|join(",")); edição=\($a.edicao); monetização=\($a.monetizacao); evidência=\(if ($a.evidencia.ref//"")=="" then "não" else $a.evidencia.tipo//"sim" end)" else "sem cadastro" end),
           ((.editorial.contribuicoes//[])|map(.tipo)|join(",")), (.editorial.nivel//"—"),
           (($c|map(.duplicidade.resultado//"—")|first)//"—"), ((.riscos//[])|join(",")),
           ($c|map(select(.estado=="aprovado")|.plataforma)|join(",")),
           ($p|map("\(.plataforma):\(.estado)")|join(",")),
           ($c|map("\(.plataforma)=\(.estado): \(.motivos|join("; "))")|join(" | "))]|@tsv),
        ($pub|map(select((.event_id|IN($ids[]))|not))|group_by(.event_id)[]|select($ev=="" or .[0].event_id==$ev)
         |[.[0].event_id, "—", "—", "—", "—", "—", "—", "legado (sem ficha)", "—", "—", "—",
           (group_by(.plataforma)|map(last|"\(.plataforma):\(.estado)")|join(",")), "publicado antes do controle de conformidade"]|@tsv)' "$CAND"
  } | tee "$DADOS/auditoria.tsv"
}

cmd_relatorio() {
  jq -rs --slurpfile ctl "$CTL" --slurpfile pub "$PUB" --slurpfile met "$MET" '
    (group_by(.event_id)|map((map(.nota)|max) as $m|map(select(.nota==$m))|last)) as $f
    | ($ctl|group_by(.event_id+"|"+.plataforma)|map(last)) as $c
    | ($pub|group_by(.chave)|map(last)) as $p
    | "== Controle por rede (estado atual)",
      ($c|group_by(.plataforma)[]|"  \(.[0].plataforma): " + (group_by(.estado)|map("\(.[0].estado) \(length)")|join(" · "))),
      "== Motivos mais comuns de revisão/bloqueio",
      ($c|map(select(.estado!="aprovado")|.motivos[])|map(sub(" [(].*$";"")|sub(": .*$";"")|sub(" (de ev_|para @|em ).*$";""))|group_by(.)|map({m:.[0],n:length})|sort_by(-.n)|.[:10][]|"  \(.n)× \(.m)"),
      "== Por formato (categoria/tema · nível editorial): eventos · aprovados · restritos · views 24h médias",
      ($f|group_by("\(.categoria)/\(.tema) · \(.editorial.nivel//"sem editorial")")[]
        | (map(.event_id)) as $ids
        | ([$c[]|select((.event_id|IN($ids[])) and .estado=="aprovado")]|length) as $ap
        | ([$p[]|select((.event_id|IN($ids[])) and .estado=="restrito")]|length) as $re
        | ([$met[]|select((.event_id|IN($ids[])) and .janela=="24h" and .views!=null)|.views]) as $v
        | "  \(.[0].categoria)/\(.[0].tema) · \(.[0].editorial.nivel//"sem editorial"): \(length) · \($ap) · \($re) · \(if ($v|length)>0 then ($v|add/length|floor) else "—" end)"),
      "== Por streamer: eventos · bloqueios · restritos",
      ($f|group_by(.criador)[]|(map(.event_id)) as $ids
        | "  \(.[0].criador): \(length) · \([$c[]|select((.event_id|IN($ids[])) and .estado=="bloqueado")]|length) · \([$p[]|select((.event_id|IN($ids[])) and .estado=="restrito")]|length)"),
      "== Posts restritos pelas redes: \([$p[]|select(.estado=="restrito")]|length)"' "$CAND"
}

grava_estado() { # chave event_id plataforma estado id_externo arquivo
  jq -nc --arg k "$1" --arg e "$2" --arg c "$CONTA" --arg p "$3" --arg s "$4" --arg x "$5" --arg a "$6" \
     --arg ts "$(agora)" --arg maq "$MAQUINA" \
     '{chave:$k,event_id:$e,conta:$c,plataforma:$p,estado:$s,id_externo:(if $x=="" then null else $x end),
       arquivo:(if $a=="" then null else $a end),ts:$ts,maquina:$maq}' >> "$PUB"
}

# Marca "pendente" só nas redes aprovadas no controle e grava o corte no histórico de duplicidade.
cmd_entregar() {
  local el; el=$(cmd_elegivel "$1" todas) || erro "$el"
  local ok; ok=$(sed -n 's/^sim: *//p' <<<"$el")
  local f="$FILA/$(basename "$2")"; [ -f "$f" ] || f="$2"
  local fi_; fi_=$(ativa "$1")
  local url ini0 base=0; url=$(jq -r '.origem_url//.fonte' <<<"$fi_"); ini0=$(jq -r '.origem_inicio//""' <<<"$fi_")
  [ -n "$ini0" ] && base=$(TZ="${FUSO_POSIX:-<-03>3}" date -d "$ini0" +%s 2>/dev/null || echo 0)
  if [ -f "$f" ]; then
    bash "$(dirname "$0")/duplicidade.sh" registrar "$f" "$1" "$url" \
      "$(jq -r --argjson b "$base" '$b+.origem_ini_ms/1000' <<<"$fi_")" "$(jq -r --argjson b "$base" '$b+.origem_fim_ms/1000' <<<"$fi_")" >/dev/null
  fi
  travar
  local p; for p in $ok; do grava_estado "$1|$CONTA|$p" "$1" "$p" pendente "" "$(basename "$2")"; done
  echo "$1 pendente em: $ok ($(basename "$2"))"
  grep '^não:' <<<"$el" || true
}

cmd_estado() {
  local ev="$1" p="$2" novo="$3" x="${4:-}" conc=""
  if [ "${5:-}" = --conciliado ] || [ "$x" = --conciliado ]; then conc=1; fi
  if [ "$x" = --conciliado ]; then x=""; fi
  [ "$PAPEL" = publicador ] || erro "esta máquina é '$PAPEL': só o PC publicador muda estado de envio"
  local k="$ev|$CONTA|$p" atual; atual=$(ultimo_estado "$k")
  local ok=""
  case "$atual>$novo" in
    "pendente>em_envio"|"falha>pendente"|"falha>em_envio"|"revisao>pendente") ok=1 ;;
    "em_envio>agendado"|"em_envio>publicado"|"em_envio>falha"|"em_envio>envio_incerto") ok=1 ;;
    "agendado>publicado"|"agendado>revisao"|"publicado>revisao"|"pendente>revisao") ok=1 ;;
    "agendado>restrito"|"publicado>restrito"|"restrito>publicado") ok=1 ;;
    "envio_incerto>agendado"|"envio_incerto>publicado") if [ -n "$x" ]; then ok=1; fi ;;
    "envio_incerto>falha") if [ -n "$conc" ]; then ok=1; fi ;;
  esac
  [ -n "$ok" ] || erro "transição $atual → $novo recusada para $k$([ "$atual" = envio_incerto ] && echo ' (consulte a plataforma primeiro; precisa de id externo ou --conciliado)')"
  case "$novo" in agendado|publicado) [ -n "$x" ] || [ "$atual" = agendado ] || erro "$novo precisa do id externo" ;; esac
  travar; grava_estado "$k" "$ev" "$p" "$novo" "$x" ""
  echo "$k: $atual → $novo"
}

cmd_enviar() {
  [ "$PAPEL" = publicador ] || erro "esta máquina é '$PAPEL': só o PC publicador envia"
  local a; a=$(basename "$1")
  local ev; ev=$(jq -rs --arg a "$a" '[.[]|select(.arquivo==$a and (.event_id|startswith("legado_")|not))]|first|.event_id//empty' "$PUB")
  # Corte sem ficha (entregue à mão) não sai mais: passa por avaliar + entregar.
  [ -n "$ev" ] || erro "$a não tem ficha nem entrega registrada: rode registro.sh avaliar e entregar (não poste)"
  local c; c=$(ctl_estado "$ev" "$2")
  [ "$c" = aprovado ] || erro "$a está '$c' no controle para $2: só 'aprovado' é postado automaticamente (não poste)"
  local k="$ev|$CONTA|$2" e; e=$(ultimo_estado "$k")
  case "$e" in nenhum|pendente|falha) ;; *) erro "$k está '$e': não enviar$([ "$e" = envio_incerto ] && echo ' (concilie com list_posts antes)')" ;; esac
  travar
  [ "$e" = nenhum ] && grava_estado "$k" "$ev" "$2" pendente "" "$a"
  grava_estado "$k" "$ev" "$2" em_envio "" "$a"
  echo "$ev"
}

cmd_importar() {
  # .feito: "rede postId horario url" por linha (gravado pela rodada da tarefa agendada). Só lê a fila.
  travar
  local f base ev rede id n=0
  for f in "$FILA"/*.feito "$FILA"/postados/*.feito; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .feito)
    ev=$(jq -rs --arg a "$base.mp4" '[.[]|select(.arquivo==$a)]|first|.event_id//empty' "$PUB")
    [ -n "$ev" ] || ev="legado_$base"
    while read -r rede id _; do
      rede=${rede#$'\xef\xbb\xbf'}; [ -n "${id:-}" ] || continue
      [ "$(ultimo_estado "$ev|$CONTA|$rede")" = agendado ] && continue
      [ "$(ultimo_estado "$ev|$CONTA|$rede")" = publicado ] && continue
      grava_estado "$ev|$CONTA|$rede" "$ev" "$rede" agendado "$id" "$base.mp4"; n=$((n+1))
    done < <(tr -d '\r' < "$f")
  done
  echo "importados: $n registros novos de .feito"
}

cmd_metrica() {
  echo "$4" | jq -e 'type=="object"' >/dev/null || erro "métrica precisa ser objeto JSON"
  travar
  echo "$4" | jq -c --arg e "$1" --arg p "$2" --arg j "$3" --arg ts "$(agora)" --arg c "$CONTA" '
    {event_id:$e,conta:$c,plataforma:$p,janela:$j,ts:$ts}
    + ({views:null,tempo_medio_s:null,pct_visto:null,retencao_inicial:null,compartilhamentos:null,salvamentos:null,seguidores:null} + .)' >> "$MET"
  echo "métrica $1 $2 $3 gravada"
}

cmd_resumo() {
  echo "Candidatos (ficha ativa por evento):"
  jq -rs 'group_by(.event_id)|map(max_by(.nota))|group_by(.decisao)|map("  \(.[0].decisao): \(length)")|.[]' "$CAND"
  echo "Publicação (estado atual por evento+conta+rede):"
  jq -rs 'group_by(.chave)|map(last)|group_by(.estado)|map("  \(.[0].estado): \(length)")|.[]' "$PUB"
  echo "Métricas: $(wc -l < "$MET") linhas"
}

case "${1:-}" in
  candidato) cmd_candidato "$2" ;;
  decidir) cmd_decidir "$2" "$3" "$4" ;;
  elegivel) cmd_elegivel "$2" "${3:-todas}" ;;
  entregar) cmd_entregar "$2" "$3" ;;
  estado) cmd_estado "$2" "$3" "$4" "${5:-}" "${6:-}" ;;
  enviar) cmd_enviar "$2" "$3" ;;
  importar) cmd_importar ;;
  metrica) cmd_metrica "$2" "$3" "$4" "$5" ;;
  autorizacao) cmd_autorizacao "$2" ;;
  direitos) cmd_direitos "$2" "$3" ;;
  editorial) cmd_editorial "$2" "$3" ;;
  avaliar) cmd_avaliar "$2" "$3" ;;
  revisar) cmd_revisar "$2" "$3" "$4" "${5:-}" ;;
  revisao) cmd_revisao ;;
  auditoria) cmd_auditoria "${2:-}" ;;
  relatorio) cmd_relatorio ;;
  ficha) ativa "$2" | jq . ; jq -cs --arg e "$2" '[.[]|select(.event_id==$e)]|group_by(.chave)|map(last)|.[]' "$PUB" ;;
  resumo) cmd_resumo ;;
  exportar) cat "$CAND" ;;
  juntar) travar; sort -u "$CAND" "$2" > "$CAND.novo" && mv "$CAND.novo" "$CAND"; echo "juntado: $(wc -l < "$CAND") fichas" ;;
  *) sed -n '2,32p' "$0"; exit 1 ;;
esac
