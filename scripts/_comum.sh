# Carregado pelos scripts de operação (triagem, registro, qa, simular). Acha a skill, a pasta da operação e a config.
# A pasta da operação fica FORA da skill (instalar.sh grava o caminho em <skill>/operacao.local).
# GTA6_OP e GTA6_CONFIG podem ser sobrescritos (a simulação usa isso para não tocar nos dados reais).
SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${GTA6_OP:-}" ] && [ -f "$SK/operacao.local" ]; then GTA6_OP="$(tr -d '[:cntrl:]' < "$SK/operacao.local")"; fi
GTA6_CONFIG="${GTA6_CONFIG:-${GTA6_OP:-}/config/operacao.env}"
[ -f "$GTA6_CONFIG" ] || { echo "Operação não instalada: rode  bash $SK/instalar.sh <pasta_da_operacao>" >&2; exit 1; }
# shellcheck disable=SC1090
. <(tr -d '\r' < "$GTA6_CONFIG")
rel() { case "$1" in /*|?:/*) echo "$1" ;; *) echo "${GTA6_OP:-.}/$1" ;; esac; }
DADOS="$(rel "${DADOS:-dados}")"; FILA="$(rel "${FILA:-fila}")"
mkdir -p "$DADOS/cache"
: "${LIMIAR_FILA:=80}" "${LIMIAR_REVISAO:=65}" "${FORTES_POR_HORA:=6}" "${AMOSTRA_FRACAO:=0.15}" "${TRIAGEM_VERSAO:=1}"
: "${PLATAFORMAS:=instagram tiktok youtube}" "${CONTA:=minha-conta}" "${MAQUINA:=pc}" "${PAPEL:=analise}"
# O date do Git Bash não tem a base de fusos: use FUSO_POSIX (ex.: America/Sao_Paulo = "<-03>3", sem horário de verão).
agora() { TZ="${FUSO_POSIX:-<-03>3}" date +%Y-%m-%dT%H:%M:%S%z; }
# Um gravador por vez nesta máquina (mkdir é atômico). Evita duas linhas JSONL intercaladas.
travar() { local i=0; until mkdir "$DADOS/.trava" 2>/dev/null; do i=$((i+1)); [ $i -gt 100 ] && { echo "trava presa: $DADOS/.trava" >&2; exit 1; }; sleep 0.1; done; trap 'rmdir "$DADOS/.trava" 2>/dev/null' EXIT; }

# ---- Trabalho pesado (render, Whisper, proxy): um por vez, prioridade baixa e respeitando o FiveM ----
# FIVEM_MODO: pausar = espera o FiveM fechar · leve = segue com poucas threads, prioridade Idle e sem GPU · ignorar.
: "${RENDER_THREADS:=8}" "${RENDER_PRIORIDADE:=BelowNormal}" "${FIVEM_MODO:=leve}" "${FIVEM_THREADS:=2}"
fivem_ativo() { tasklist.exe //fi "imagename eq FiveM*" //nh 2>/dev/null | grep -qi '^fivem'; }
pesado_inicio() {
  [ -n "${GTA6_PESADO:-}" ] && return 0   # já dentro de um trabalho pesado (ex.: preparar_live chama analisar)
  # Rodízio: cada pedido entra no fim da fila ($DADOS/.fila_pesado) e só o pedido vivo mais antigo tenta a trava.
  # Assim uma sessão que prepara vários blocos seguidos volta ao fim da fila a cada bloco, e as outras não ficam sem vez.
  local L="$DADOS/.trava_pesado" Q="$DADOS/.fila_pesado" pid avisou="" t p n i
  mkdir -p "$Q"
  _GTA6_SENHA="$Q/$(date +%s%N)-$$"
  echo $$ > "$Q/.tmp.$$" && mv "$Q/.tmp.$$" "$_GTA6_SENHA"   # mv: a senha nunca aparece vazia para os outros
  trap 'rm -f "$_GTA6_SENHA"' EXIT
  while :; do
    [ -f "$_GTA6_SENHA" ] || { echo $$ > "$Q/.tmp.$$" && mv "$Q/.tmp.$$" "$_GTA6_SENHA"; }
    t=""
    for t in "$Q"/*; do
      [ -f "$t" ] || continue
      p=$(cat "$t" 2>/dev/null || true)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then break; fi
      rm -f "$t"; t=""   # dono da senha morreu: senha velha
    done
    if [ "$t" = "$_GTA6_SENHA" ]; then
      # Vagas: até PESADO_VAGAS trabalhos pesados ao mesmo tempo (padrão 2). Com o FiveM aberto, 1 só:
      # no modo leve (sem GPU, poucas threads) o proxy vertical chega a ~16 GB de RAM.
      n=${PESADO_VAGAS:-2}; [ "$FIVEM_MODO" != ignorar ] && fivem_ativo && n=1
      for i in $(seq 1 "$n"); do
        L="$DADOS/.trava_pesado"; [ "$i" -gt 1 ] && L="$DADOS/.trava_pesado$i"
        mkdir "$L" 2>/dev/null && break 2
        pid=$(cat "$L/pid" 2>/dev/null || true)
        # dono morreu: trava velha
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$L"; mkdir "$L" 2>/dev/null && break 2; fi
      done
    fi
    [ -n "$avisou" ] || { echo "fila de processamento: aguardando a vez (rodízio)" >&2; avisou=1; }
    sleep 2
  done
  echo $$ > "$L/pid"; rm -f "$_GTA6_SENHA"; export GTA6_PESADO=1
  _GTA6_TRAVA="$L"; trap 'rm -rf "$_GTA6_TRAVA"' EXIT
  THREADS=$RENDER_THREADS; local prio=$RENDER_PRIORIDADE
  if [ "$FIVEM_MODO" != ignorar ] && fivem_ativo; then
    if [ "$FIVEM_MODO" = pausar ]; then
      echo "FiveM aberto: processamento pausado até ele fechar (FIVEM_MODO=pausar)" >&2
      while fivem_ativo; do sleep 30; done
    else
      THREADS=$FIVEM_THREADS; prio=Idle; GTA6_SEM_GPU=1
      echo "FiveM aberto: modo leve ($THREADS threads, prioridade Idle, sem GPU)" >&2
    fi
  fi
  export THREADS GTA6_SEM_GPU
  # Prioridade do Windows: os processos filhos (ffmpeg) herdam BelowNormal/Idle do bash.
  local wp; wp=$(cat /proc/$$/winpid 2>/dev/null || true)
  [ -n "$wp" ] && powershell.exe -NoProfile -Command "try{(Get-Process -Id $wp).PriorityClass='$prio'}catch{}" >/dev/null 2>&1 || true
}
