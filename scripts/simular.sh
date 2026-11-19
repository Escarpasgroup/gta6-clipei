#!/usr/bin/env bash
# Simulação completa SEM postagem externa e sem tocar nos dados reais, na fila nem nas gravações.
#   simular.sh [corte_renderizado.mp4]
# Tudo roda numa pasta temporária (config, dados, fila e gravação falsas). O corte renderizado, se passado,
# só é lido (ffprobe/ffmpeg) para validar a prévia. Sai 0 se todos os casos passaram.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; S="$(mktemp -d)"; ok=0; nok=0
trap '[ -n "${SIM_MANTER:-}" ] && echo "mantido: $S" || rm -rf "$S"' EXIT
caso() { if eval "$2" >/dev/null 2>&1; then echo "OK    $1"; ok=$((ok+1)); else echo "FALHA $1"; nok=$((nok+1)); fi; }

mkdir -p "$S/fila" "$S/grav"
sed -e "s#^DADOS=.*#DADOS=$S/dados#" -e "s#^FILA=.*#FILA=\"$S/fila\"#" -e 's/^PAPEL=.*/PAPEL=publicador/' \
    -e 's/^MAQUINA=.*/MAQUINA=simulacao/' "$D/../modelos/operacao.env" > "$S/cfg.env"
export GTA6_OP="$S" GTA6_CONFIG="$S/cfg.env"
R() { bash "$D/registro.sh" "$@"; }

# Gravação falsa: 2 blocos de 20 min já "prontos" (como o editar-video deixa).
echo "2026-11-18 10:00:00" > "$S/grav/inicio.txt"
for b in b000 b001; do
  mkdir -p "$S/grav/$b"; echo "duration=1200.0" > "$S/grav/$b/info.txt"
  printf '1\n00:00:01,000 --> 00:00:02,000\nteste\n' > "$S/grav/$b/transcricao.srt"
  printf 'volume mediano -30 dB\n\n#1  0:02:15–0:02:40 (135–160 s)  nota 19.0  [reação evento pico(66) ]\n    Que isso? | O polícia pega pesado |\n\n#2  0:10:00–0:10:25 (600–625 s)  nota 9.0  [reação ]\n    Nossa |\n\n#3  0:15:00–0:15:25 (900–925 s)  nota 4.0  [reação ]\n    eita |\n' > "$S/grav/$b/candidatos.txt"
  # volume: -30 dB, silêncio (-45) de 300–306 s e pico (-15) em 306,5 s (detalhe silencioso fora das fortes)
  awk 'BEGIN{for(i=0;i<4800;i++){t=i*0.25; v=-30; if(t>=300&&t<306)v=-45; if(t>=306.5&&t<307)v=-15; printf "%6.2f %6.1f\n",t,v}}' > "$S/grav/$b/volume.txt"
done

T1=$(bash "$D/triagem.sh" "$S/grav" 2>/dev/null)
caso "triagem: 2 fortes por bloco de 20 min (6/h)" '[ "$(grep -c "	forte	" <<<"$T1")" = 4 ]'
caso "detalhe silencioso entra como amostra" 'grep -q "	amostra	.*silencio>reacao" <<<"$T1"'
caso "cursor: 2ª triagem não repete blocos" 'bash "$D/triagem.sh" "$S/grav" 2>/dev/null | grep -q "nada novo"'
caso "consumo registrado com lacunas" 'jq -e ".duracao_analisada_s==2400 and (.lacunas|test(\"chat\"))" "$S/dados/consumo.jsonl"'

base='{"fonte":"grav_20261118100000","criador":"@streamer_exemplo","categoria":"gta6","tema":"policia",
 "origem_ini_ms":137000,"origem_fim_ms":172000,"gancho":"QUANDO VOCÊ TENTA ROUBAR A VIATURA:","contexto":"rouba viatura",
 "desfecho":"polícia derruba e leva o dinheiro","confianca":"alta","contexto_faltante":"","direitos":"ok",
 "risco_spoiler":false,"riscos":[],"origem_url":"https://www.youtube.com/watch?v=sim123","origem_inicio":"2026-11-18 10:00:00",
 "fatores":{"gancho":5,"compreensao":4,"novidade":4,"progressao":5,"legibilidade":4,"compartilhamento":4}}'

# Vídeos sintéticos 1080x1920 de 20 s (passam no QA): A, B (outro conteúdo) e A2 (= A com texto por cima, re-encodado).
gv() { ffmpeg -v error -nostdin -f lavfi -t 20 -i "$1=s=270x480:r=30" -f lavfi -i "anoisesrc=d=20:c=pink:seed=$2:a=0.3" \
  -vf "scale=1080:1920${4:+,$4}" -af "loudnorm=I=-11.8:TP=-1.5" -ar 44100 -c:v libx264 -preset ultrafast -crf 30 -shortest -y "$S/$3"; }
gv testsrc2 1 A.mp4; gv life 2 B.mp4; gv testsrc2 1 A2.mp4 "drawbox=x=100:y=100:w=300:h=120:color=red:t=fill"
txt() { printf 'Título do corte no GTA 6\n\nDescrição com termo de busca. Você tentaria?\n\n🎮 Live: @streamer_exemplo\n%s\n' "${2:-#gta6 #gta6policia}" > "$S/fila/$1.txt"; }
aut='{"apelido":"exemplo","canal":"@streamer_exemplo","evidencia":{"tipo":"mensagem","ref":"prints/x.png","data":"2026-11-10"},
 "plataformas":["instagram","tiktok","youtube"],"edicao":true,"republicacao":true,"monetizacao":"sim"}'
edi='{"contexto":"vinha fugindo da polícia","historia":true,"abertura":"ELE TENTOU ROUBAR A VIATURA",
 "contribuicoes":[{"tipo":"contexto","texto":"cartela: 2 min antes fugia","base":"b000 01:50"},
                  {"tipo":"humor","texto":"*plano perfeito*","base":"derrubado 00:12"},
                  {"tipo":"zoom","texto":"zoom no rosto","base":"00:05"}],"fala_preservada":true,"inventado":false}'
OA=$(R candidato "$base"); EA=$(cut -f1 <<<"$OA")
caso "cena com desfecho (nota ≥80) vai para fila" 'grep -q "	fila	" <<<"$OA"'
OB=$(R candidato "$(jq -c '.origem_ini_ms=600000|.origem_fim_ms=630000|.contexto_faltante="piada interna do RP"|.fatores.compreensao=2' <<<"$base")")
caso "cena sem contexto é retida" 'grep -q "	retido	" <<<"$OB"'
OC=$(R candidato "$(jq -c '.origem_ini_ms=294000|.origem_fim_ms=320000|.amostra=true|.fatores={"gancho":3,"compreensao":3,"novidade":4,"progressao":2,"legibilidade":3,"compartilhamento":2}' <<<"$base")")
caso "amostra fraca vira calibração (não some)" 'grep -q "	calibracao	" <<<"$OC"'
OD=$(R candidato "$(jq -c '.origem_ini_ms=900000|.origem_fim_ms=925000|.desfecho=""' <<<"$base")")
caso "sem desfecho → aguardando_desfecho" 'grep -q "aguardando_desfecho" <<<"$OD"'
OE=$(R candidato "$(jq -c '.origem_ini_ms=1300000|.origem_fim_ms=1330000|.direitos="incerto"' <<<"$base")")
caso "direito incerto é retido mesmo com nota alta" 'grep -q "	retido	" <<<"$OE"'
caso "ficha incompleta é recusada" '! R candidato "{\"fonte\":\"x\"}"'

caso "memória sobrevive a nova execução" '[ "$(R ficha "$EA" | jq -rs ".[0].decisao")" = fila ]'
cp "$S/A.mp4" "$S/fila/12_teste.mp4"; txt 12_teste
st() { jq -rs --arg e "$1" --arg p "$2" '[.[]|select(.event_id==$e and .plataforma==$p)]|last|.estado' "$S/dados/controle.jsonl"; }
# --- conformidade: direitos, editorial, controle por rede ---
caso "sem editorial nem autorização: não entrega" '! R entregar "$EA" 12_teste.mp4'
R avaliar "$EA" "$S/fila/12_teste.mp4" >/dev/null 2>&1
caso "sem autorização cadastrada → bloqueado" '[ "$(st "$EA" tiktok)" = bloqueado ]'
caso "cadastro incompleto é recusado" '! R autorizacao "{\"apelido\":\"x\",\"canal\":\"@x\"}"'
R autorizacao "$(jq -c '.evidencia.ref=""' <<<"$aut")" >/dev/null
caso "autorização sem evidência → direitos em revisão" 'R direitos @streamer_exemplo tiktok | grep -q "^revisao_manual"'
caso "rede fora da autorização → bloqueada" 'R direitos @streamer_exemplo facebook | grep -q "^bloqueado"'
R autorizacao "$(jq -c '.monetizacao="nao"' <<<"$aut")" >/dev/null
caso "monetização negada em rede monetizada → bloqueado" 'R direitos @streamer_exemplo youtube | grep -q "^bloqueado"'
R autorizacao "$aut" >/dev/null
caso "editorial: zoom não conta, contexto+humor = editorial" 'R editorial "$EA" "$edi" | grep -q "editorial: editorial (2 contribuições, 1 informativas); não contam: zoom"'
OAV=$(R avaliar "$EA" "$S/fila/12_teste.mp4")
caso "completo → aprovado nas 3 redes" '[ "$(grep -c "	aprovado	" <<<"$OAV")" = 3 ]'
caso "entregar marca pendente nas 3 redes" 'R entregar "$EA" 12_teste.mp4 && [ "$(R ficha "$EA" | jq -s "[.[1:][]|select(.estado==\"pendente\")]|length")" = 3 ]'
caso "entrega grava o corte no histórico" 'jq -e "select(.event_id==\"$EA\")" "$S/dados/historico.jsonl"'

OF=$(R candidato "$(jq -c '.origem_ini_ms=2000000|.origem_fim_ms=2030000' <<<"$base")"); EF=$(cut -f1 <<<"$OF")
cp "$S/A2.mp4" "$S/fila/14_dup.mp4"; txt 14_dup
R editorial "$EF" "$edi" >/dev/null
OFV=$(R avaliar "$EF" "$S/fila/14_dup.mp4")
caso "mesmo vídeo com texto por cima → duplicado bloqueado nas 3 redes" '[ "$(grep -c "bloqueado.*duplicado (video)" <<<"$OFV")" = 3 ]'
OG=$(R candidato "$(jq -c '.fonte="grav_outra"|.origem_ini_ms=140000|.origem_fim_ms=170000' <<<"$base")"); EG=$(cut -f1 <<<"$OG")
cp "$S/B.mp4" "$S/fila/15_trecho.mp4"; txt 15_trecho
R editorial "$EG" "$edi" >/dev/null
OGV=$(R avaliar "$EG" "$S/fila/15_trecho.mp4")
caso "mesmo trecho da live por outra gravação → revisão" 'grep -q "revisao_manual.*trecho da live já usado" <<<"$OGV"'
OH=$(R candidato "$(jq -c '.origem_ini_ms=3000000|.origem_fim_ms=3030000' <<<"$base")"); EH=$(cut -f1 <<<"$OH")
cp "$S/B.mp4" "$S/fila/16_leve.mp4"; txt 16_leve "#gta6 #a #b #c #d"
R editorial "$EH" "$(jq -c '.contribuicoes=[{"tipo":"humor","texto":"*x*","base":"00:03"},{"tipo":"legenda","texto":"fala","base":"toda"}]' <<<"$edi")" >/dev/null
OHV=$(R avaliar "$EH" "$S/fila/16_leve.mp4")
caso "pouca contribuição → revisão manual (material reutilizado)" 'grep -q "revisao_manual.*material reutilizado" <<<"$OHV"'
caso "hashtags acima do perfil da rede → motivo registrado" 'grep -q "mais de 3 hashtags" <<<"$OHV"'
caso "fila de revisão lista o corte" 'R revisao | grep -q "$EH"'
caso "humano aprova da revisão (só nessa rede)" 'R revisar "$EH" tiktok aprovado "conferido com o dono" && [ "$(st "$EH" tiktok)" = aprovado ] && [ "$(st "$EH" youtube)" = revisao_manual ]'
caso "bloqueado não vira aprovado no revisar" 'R revisar "$EF" tiktok aprovado "tentativa" | grep -q "só sai da revisão" && [ "$(st "$EF" tiktok)" = bloqueado ]'
caso "enviar recusa rede não aprovada" '! R enviar 16_leve.mp4 youtube'
caso "mesmo corte não fica elegível de novo" '! R elegivel "$EA" tiktok'
OS=$(R candidato "$(jq -c '.origem_ini_ms=140000|.origem_fim_ms=175000|.fatores.novidade=3' <<<"$base")")
caso "corte deslocado 3 s = mesmo evento, marcado duplicado" '[ "$(cut -f1 <<<"$OS")" = "$EA" ] && grep -q duplicado <<<"$OS"'
caso "deslocado também não fica elegível" '! R elegivel "$(cut -f1 <<<"$OS")" todas'

caso "envio: pendente → em_envio" 'R estado "$EA" tiktok em_envio'
caso "timeout: em_envio → envio_incerto" 'R estado "$EA" tiktok envio_incerto'
caso "sem tentativa cega: envio_incerto → em_envio recusado" '! R estado "$EA" tiktok em_envio'
caso "falha sem conciliar é recusada" '! R estado "$EA" tiktok falha'
caso "conciliado com id externo → agendado" 'R estado "$EA" tiktok agendado sim_post_123'
caso "PC de análise não muda estado de envio" '! (sed -i "s/^PAPEL=.*/PAPEL=analise/" "$S/cfg.env"; R estado "$EA" instagram em_envio)'
sed -i 's/^PAPEL=.*/PAPEL=publicador/' "$S/cfg.env"

touch "$S/fila/13_manual.mp4" "$S/fila/13_manual.txt"
caso "rodada: corte sem ficha (manual/legado) é recusado" '! R enviar 13_manual.mp4 youtube'
caso "rodada: rede aprovada e pendente vira em_envio" 'R enviar 12_teste.mp4 youtube'
caso "rodada: 2º envio do mesmo corte é recusado" '! R enviar 12_teste.mp4 youtube'
caso "rodada: corte já agendado não é reenviado" '! R enviar 12_teste.mp4 tiktok'
caso "post limitado pela rede: agendado → restrito" 'R estado "$EA" tiktok restrito'
printf 'instagram sim_ig_1 2026-11-18T20:00:00-03:00 https://exemplo.invalid/x.mp4\n' > "$S/fila/12_teste.feito"
caso "importar .feito marca agendado com id" 'R importar && R ficha "$EA" | jq -se "any(.[]; .plataforma==\"instagram\" and .estado==\"agendado\" and .id_externo==\"sim_ig_1\")"'
caso "importar de novo não duplica" '[ "$(R importar)" = "importados: 0 registros novos de .feito" ]'
caso "métrica com campos ausentes vira null" 'R metrica "$EA" tiktok 1h "{\"views\":100}" && jq -e ".views==100 and .salvamentos==null" "$S/dados/metricas.jsonl"'
caso "auditoria: corte com link, contribuições e justificativa" 'R auditoria "$EA" | grep "$EA" | grep -q "sim123.*contexto,humor,zoom.*editorial.*nenhuma.*instagram,tiktok,youtube"'
caso "relatório mostra restrito e motivos" 'R relatorio | grep -q "Posts restritos pelas redes: 1" && R relatorio | grep -q "duplicado"'
# fila de processamento: trava de um processo morto é limpa; modo ignorar não espera o FiveM
mkdir -p "$S/dados/.trava_pesado"; echo 999999 > "$S/dados/.trava_pesado/pid"
caso "fila de render: trava velha é liberada" '(. "$D/_comum.sh"; FIVEM_MODO=ignorar; pesado_inicio; [ "$(cat "$DADOS/.trava_pesado/pid")" = "$BASHPID" ] || [ -n "$GTA6_PESADO" ])'

if [ -n "${1:-}" ]; then
  Q=$(bash "$D/qa.sh" "$1" 3 "$S/quadro.jpg" 2>&1); echo "$Q" | sed 's/^/      /'
  caso "prévia renderizada passa no QA técnico" 'grep -q "QA OK" <<<"$Q"'
  caso "quadro com áreas da interface gerado" '[ -s "$S/quadro.jpg" ]'
  [ -n "${SIM_QUADRO:-}" ] && cp "$S/quadro.jpg" "$SIM_QUADRO"
fi
echo "---"; echo "$ok OK · $nok falha(s)"; [ $nok = 0 ]
