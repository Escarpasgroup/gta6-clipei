#!/usr/bin/env bash
# Vigia automática: mantém UMA gravação na live autorizada mais forte e troca quando outra passa com folga.
#   vigia.sh            → uma rodada (a tarefa agendada roda de hora em hora)
#   vigia.sh estado     → mostra a gravação da vigia e o último ranking, sem mudar nada
#   vigia.sh parar      → encerra a gravação da vigia
# Regras:
#   - Só grava streamer autorizado (coluna "sim" do ranking de lives_fortes.sh). Os "nao" são só sugestões.
#   - Pula live que outra sessão já grava (url ou id no comando de algum processo): não grava duas vezes.
#   - Troca se a melhor tiver >= VIGIA_MARGEM % (padrão 30) a mais de espectadores que a atual, ou se a atual acabou.
#   - A gravação roda fora da sessão do Claude (criada pelo WMI do Windows), então continua depois da rodada.
# Estado em $DADOS/vigia.atual; decisões em $DADOS/vigia.log.
. "$(dirname "$0")/_comum.sh"
MARGEM="${VIGIA_MARGEM:-30}"; DUR="${VIGIA_DURACAO_S:-21600}"; BLOCO="${VIGIA_BLOCO_S:-1200}"
EST="$DADOS/vigia.atual"; LOG="$DADOS/vigia.log"
mkdir "$DADOS/.trava_vigia" 2>/dev/null || { echo "outra rodada da vigia em andamento"; exit 0; }
trap 'rmdir "$DADOS/.trava_vigia" 2>/dev/null' EXIT
log() { echo "$(agora) $*" | tee -a "$LOG"; }
ps_cmd() { powershell.exe -NoProfile -Command "$1" | tr -d '\r'; }
vivo() { [ -n "$1" ] && ps_cmd "if (Get-Process -Id $1 -ErrorAction SilentlyContinue) { 'sim' }" | grep -q sim; }
# Linhas de comando de todos os gravadores da máquina (de qualquer sessão).
gravando_agora() { ps_cmd "Get-CimInstance Win32_Process -Filter \"Name='bash.exe' or Name='ffmpeg.exe'\" | ForEach-Object { \$_.CommandLine }" | grep gravar_live; }

APELIDO=; URL=; PASTA=; PID=; AUDIENCIA=0
[ -f "$EST" ] && . "$EST"
ativo() { vivo "$PID" && [ ! -f "$PASTA/FIM" ]; }

parar() {
  # shortcut: encerra à força (taskkill /T /F); o bloco em gravação (até VIGIA_BLOCO_S) fica sem fechar e se perde.
  # Se isso pesar, trocar só quando o bloco atual fechar.
  taskkill //PID "$PID" //T //F > /dev/null 2>&1
  touch "$PASTA/FIM"   # sinal para blocos_live.sh, como no fim normal da gravação
  log "PAROU $APELIDO ($URL) pasta=$PASTA"
}

iniciar() {  # $1 apelido  $2 url  $3 audiência
  local p; p="${TRAB:-$LOCALAPPDATA/Temp}/vedit-$1-$(TZ="${FUSO_POSIX:-<-03>3}" date +%Y%m%d-%H%M)"
  mkdir -p "$p"
  local bash_win sk_u p_u
  bash_win="$(cygpath -w /usr/bin/bash.exe)"; sk_u="$(cygpath -u "$SK")"; p_u="$(cygpath -u "$p")"
  # 0 = desde o começo da janela que o YouTube guarda (~15 min): pega o que rolou antes da troca.
  # A linha de comando vai por variável de ambiente para não passar pelo parser de aspas do PowerShell.
  NOVO_PID="$(CMDLINE="\"$bash_win\" -c \"'$sk_u/scripts/gravar_live.sh' '$2' '$p_u' $DUR 0 $BLOCO > '$p_u/gravar.log' 2>&1\"" \
    ps_cmd '(Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$env:CMDLINE}).ProcessId')"
  [ -n "$NOVO_PID" ] && [ "$NOVO_PID" != 0 ] || { log "ERRO ao iniciar $1 ($2)"; exit 1; }
  printf 'APELIDO=%q\nURL=%q\nPASTA=%q\nPID=%q\nAUDIENCIA=%q\nINICIO=%q\n' "$1" "$2" "$p" "$NOVO_PID" "$3" "$(agora)" > "$EST"
  log "GRAVANDO $1 ($3 espectadores) $2 pasta=$p pid=$NOVO_PID"
}

case "${1:-}" in
  estado) if ativo; then echo "gravando: $APELIDO ($AUDIENCIA) $URL pasta=$PASTA pid=$PID"; else echo "vigia sem gravação ativa"; fi
          echo "--- último ranking ($DADOS/lives_ranking.tsv)"; head -15 "$DADOS/lives_ranking.tsv" 2>/dev/null; exit 0 ;;
  parar)  ativo && parar; rm -f "$EST"; exit 0 ;;
esac

RANK="$(bash "$SK/scripts/lives_fortes.sh")" || { log "ERRO no ranking"; exit 1; }
OUTROS="$(gravando_agora | grep -v "vedit-${APELIDO:-@@}-" || true)"
# Melhor autorizado que nenhuma outra sessão já grava (compara pelo id do vídeo ou pela url).
MELHOR="$(awk -F'\t' '$2=="sim"' <<< "$RANK" | while IFS=$'\t' read -r n _ ap url _; do
  id="${url##*v=}"; grep -qF -- "$id" <<< "$OUTROS" && continue; printf '%s\t%s\t%s\n' "$n" "$ap" "$url"; break; done)"
[ -n "$MELHOR" ] || { log "nenhuma live autorizada livre no ar"; exit 0; }
IFS=$'\t' read -r N_M AP_M URL_M <<< "$MELHOR"

if ! ativo; then
  [ -n "$APELIDO" ] && log "gravação anterior de $APELIDO terminou"
  iniciar "$AP_M" "$URL_M" "$N_M"; exit 0
fi
# Audiência atual da live que a vigia grava (0 se saiu do ranking).
N_A="$(awk -F'\t' -v u="$URL" -v a="$APELIDO" '$4==u || ($2=="sim" && $3==a) {print $1; exit}' <<< "$RANK")"; N_A="${N_A:-0}"
if [ "$URL_M" = "$URL" ] || [ "$AP_M" = "$APELIDO" ]; then
  sed -i "s/^AUDIENCIA=.*/AUDIENCIA=$N_A/" "$EST"; log "mantém $APELIDO ($N_A espectadores)"; exit 0
fi
if [ "$N_M" -ge $(( N_A * (100 + MARGEM) / 100 )) ]; then
  log "TROCA $APELIDO ($N_A) -> $AP_M ($N_M), margem ${MARGEM}%"
  parar; iniciar "$AP_M" "$URL_M" "$N_M"
else
  sed -i "s/^AUDIENCIA=.*/AUDIENCIA=$N_A/" "$EST"
  log "mantém $APELIDO ($N_A); melhor livre $AP_M ($N_M) não passa a margem de ${MARGEM}%"
fi
