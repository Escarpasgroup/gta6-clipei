#!/usr/bin/env bash
# Instala (ou confere) uma operação da skill gta6-clipei nesta máquina. Pode rodar de novo: nunca sobrescreve
# config, memória, dados, layouts, moldura nem fila que já existam.
#   bash instalar.sh <pasta_da_operacao> [publicador|analise] [nome_da_maquina] [--baixar-modelo]
# Cria em <pasta_da_operacao>: config/operacao.env, memoria/, dados/, layouts/, marca/moldura.png, fila/postados/.
# Grava o caminho em <skill>/operacao.local, copia as fontes do Windows para a skill e confere as dependências.
# --baixar-modelo: baixa o modelo do Whisper (ggml-small.bin, ~466 MB, licença MIT, Hugging Face ggerganov/whisper.cpp).
set -uo pipefail
export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Links"
SK="$(cd "$(dirname "$0")" && pwd)"
OP="${1:?uso: instalar.sh <pasta_da_operacao> [publicador|analise] [nome_da_maquina] [--baixar-modelo]}"
PAPEL_NOVO="${2:-analise}"; MAQ="${3:-$(hostname)}"; BAIXAR=""; for a in "$@"; do [ "$a" = --baixar-modelo ] && BAIXAR=1; done
case "$PAPEL_NOVO" in publicador|analise) ;; *) echo "papel deve ser publicador ou analise"; exit 1 ;; esac
mkdir -p "$OP"/{config,memoria,dados,layouts,marca,fila/postados} || exit 1
OP="$(cd "$OP" && pwd)"; OPW="$(cygpath -m "$OP" 2>/dev/null || echo "$OP")"
falta=0; ok() { echo "  ok    $*"; }; aviso() { echo "  FALTA $*"; falta=$((falta+1)); }

echo "== pasta da operação: $OPW"
if [ ! -f "$OP/config/operacao.env" ]; then
  sed -e "s/^PAPEL=.*/PAPEL=$PAPEL_NOVO/" -e "s/^MAQUINA=.*/MAQUINA=$MAQ/" "$SK/modelos/operacao.env" > "$OP/config/operacao.env"
  ok "config/operacao.env criado (PAPEL=$PAPEL_NOVO, MAQUINA=$MAQ): edite CONTA, ARROBA, HASHTAGS"
elif [ "$PAPEL_NOVO" = analise ] && grep -q '^PAPEL=publicador' "$OP/config/operacao.env"; then
  # Config copiada do publicador: rebaixar é seguro (evita duas máquinas postando na mesma conta).
  sed -i -e 's/^PAPEL=.*/PAPEL=analise/' -e "s/^MAQUINA=.*/MAQUINA=$MAQ/" "$OP/config/operacao.env"
  ok "config/operacao.env copiada do publicador: PAPEL=analise e MAQUINA=$MAQ nesta máquina"
else ok "config/operacao.env já existe (mantido: $(grep -E '^PAPEL=' "$OP/config/operacao.env"))"; fi
# Config de antes da conformidade (2026-11-19): acrescenta as chaves novas sem mexer nas que existem.
grep -q '^MONETIZA=' "$OP/config/operacao.env" || { sed -n '/^# ---- Conformidade/,$p' "$SK/modelos/operacao.env" >> "$OP/config/operacao.env"; ok "config: chaves de conformidade e desempenho acrescentadas"; }
mkdir -p "$OP/memoria/autorizacoes"
for f in "$SK"/modelos/memoria/*.md; do [ -f "$OP/memoria/$(basename "$f")" ] || cp "$f" "$OP/memoria/"; done; ok "memoria/"
ls "$OP"/layouts/*.sh >/dev/null 2>&1 || cp "$SK/modelos/layout-exemplo.sh" "$OP/layouts/exemplo.sh"; ok "layouts/"
printf '%s' "$OPW" > "$SK/operacao.local"; ok "operacao.local → $OPW"

echo "== fontes (copiadas do Windows desta máquina; não vão no pacote)"
mkdir -p "$SK/assets/fonts"
for f in arialbd impact seguibl times; do
  if [ -f "$SK/assets/fonts/$f.ttf" ]; then ok "$f.ttf"
  elif [ -f "${WINDIR:-C:/Windows}/Fonts/$f.ttf" ]; then cp "${WINDIR:-C:/Windows}/Fonts/$f.ttf" "$SK/assets/fonts/" && ok "$f.ttf (copiada)"
  else aviso "$f.ttf (instale a fonte no Windows)"; fi
done

echo "== dependências"
for c in ffmpeg ffprobe yt-dlp jq curl gawk sha1sum; do
  if command -v $c >/dev/null 2>&1; then ok "$c $($c --version 2>&1 | head -1 | sed -E 's/.*(version|ffmpeg|jq-|curl|Awk) ?//I' | cut -c1-40)"
  else aviso "$c  (winget install Gyan.FFmpeg yt-dlp.yt-dlp jqlang.jq; gawk/curl/sha1sum vêm com o Git for Windows)"; fi
done
ffmpeg -hide_banner -filters 2>/dev/null | grep -q ' whisper ' && ok "ffmpeg com filtro whisper" || aviso "ffmpeg sem filtro whisper (use o build full do gyan.dev, versão 8 ou mais nova)"
ffmpeg -hide_banner -muxers 2>/dev/null | grep -q ' chromaprint ' && ok "ffmpeg com chromaprint (duplicidade de áudio)" || aviso "ffmpeg sem chromaprint (use o build full do gyan.dev)"
command -v nvidia-smi >/dev/null 2>&1 && ok "GPU NVIDIA (render mais rápido)" || echo "  info  sem GPU NVIDIA: render na CPU, mais lento"

echo "== modelo do Whisper"
M="$(cygpath -u "$LOCALAPPDATA")/gta6-clipei/ggml-small.bin"; mkdir -p "$(dirname "$M")"
if [ -s "$M" ]; then ok "$(cygpath -m "$M")"
elif [ -s "$(cygpath -u "$LOCALAPPDATA")/editar-video/ggml-small.bin" ]; then cp "$(cygpath -u "$LOCALAPPDATA")/editar-video/ggml-small.bin" "$M" && ok "copiado da instalação antiga"
elif [ -n "$BAIXAR" ]; then curl -L --fail -o "$M" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin && ok "baixado" || aviso "download falhou"
else aviso "rode de novo com --baixar-modelo (466 MB)"; fi

echo "== moldura"
if [ -f "$OP/marca/moldura.png" ]; then ok "marca/moldura.png"
else
  AR=$(sed -n 's/^ARROBA=//p' "$OP/config/operacao.env" | tr -d '\r"' | tr -dc '@A-Za-z0-9._-')
  if bash "$SK/scripts/criar_moldura.sh" "$OP/marca/moldura.png" "${AR:-@meu.canal}" >/dev/null; then
    ok "marca/moldura.png criada com ${AR:-@meu.canal} (crie a sua: scripts/criar_moldura.sh, ver references/3-editar.md)"
  else aviso "marca/moldura.png (rode scripts/criar_moldura.sh ou coloque um PNG 1080x1920 transparente)"; fi
fi

echo "== teste sem postar"
bash "$SK/scripts/simular.sh" | tail -1

echo "== próximos passos"
echo "  1. Edite $OPW/config/operacao.env (CONTA, ARROBA, HASHTAGS, TEMA)."
if [ "$PAPEL_NOVO" = publicador ]; then
  echo "  2. Copie modelos/segredos.env.example para $OPW/config/segredos.env e preencha (Cloudflare R2)."
  echo "  3. No Claude: conecte o Buffer, peça '/gta6-clipei configurar postagem' (preenche BUFFER_* e cria a tarefa agendada)."
  echo "  4. Cadastre a autorização de cada streamer (registro.sh autorizacao; evidência em memoria/autorizacoes/)."
  echo "     Sem cadastro, nenhum corte é aprovado para postar."
else echo "  2. Esta máquina é de análise: não crie a tarefa de postagem nem copie segredos.env."
     echo "     Conferência (avaliar/entregar) roda no publicador; aqui faça ficha, pauta editorial e render."; fi
[ $falta = 0 ] && echo "INSTALAÇÃO OK" || echo "INSTALAÇÃO COM $falta PENDÊNCIA(S) (acima)"
