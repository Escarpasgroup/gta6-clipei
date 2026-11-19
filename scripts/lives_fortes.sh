#!/usr/bin/env bash
# Ranking das lives no ar, por audiência (espectadores agora), em duas fontes:
#   1. streamers de memoria/streamers.md com @ real e live no YouTube (consulta youtube.com/@canal/live);
#   2. busca de lives no YouTube pelo TEMA da config (ex.: "GTA 6"), para descobrir quem está forte agora.
#   lives_fortes.sh [max_busca=40]
# Saída (stdout e $DADOS/lives_ranking.tsv), maior audiência primeiro:
#   espectadores<TAB>autorizado(sim|nao)<TAB>apelido_ou_@<TAB>url<TAB>titulo
# Também acrescenta a rodada em $DADOS/lives_historico.tsv (data na 1ª coluna) para ver quem é forte ao longo do dia.
# Só YouTube: a Twitch não informa audiência pelo yt-dlp sem API.
. "$(dirname "$0")/_comum.sh"
export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Links"
MAX="${1:-40}"
STREAMERS="${GTA6_OP:-.}/memoria/streamers.md"
LISTA="$(mktemp)"; trap 'rm -f "$LISTA"' EXIT

# 1. Autorizados: linhas da tabela com um @ real no canal e "YouTube" na coluna live.
declare -A AUT=()   # @canal (minúsculo) -> apelido
if [ -f "$STREAMERS" ]; then
  while IFS='|' read -r _ apelido canal live _; do
    apelido="$(echo "$apelido" | xargs)"; at="$(grep -oE '@[A-Za-z0-9_.-]+' <<< "$canal" | head -1)"
    [ -n "$at" ] && grep -qi youtube <<< "$live" || continue
    AUT["${at,,}"]="$apelido"
    yt-dlp --no-warnings --skip-download --print "%(concurrent_view_count)s	sim	$apelido	%(webpage_url)s	%(title).80s" \
      "https://www.youtube.com/$at/live" < /dev/null 2>/dev/null >> "$LISTA"   # </dev/null: não comer a tabela do loop
  done < <(grep -E '^\|' "$STREAMERS" | tail -n +3)
fi

# 2. Busca de lives pelo tema (filtro "Ao vivo" do YouTube).
Q="$(echo "${TEMA:-GTA 6}" | tr ' ' '+')"
yt-dlp --no-warnings --flat-playlist --playlist-end "$MAX" \
  --print "%(concurrent_view_count)s	%(uploader_id)s	https://www.youtube.com/watch?v=%(id)s	%(title).80s" \
  "https://www.youtube.com/results?search_query=$Q&sp=EgJAAQ%253D%253D" 2>/dev/null |
while IFS=$'\t' read -r n at url titulo; do
  ap="${AUT[${at,,}]:-}"
  if [ -n "$ap" ]; then printf '%s\tsim\t%s\t%s\t%s\n' "$n" "$ap" "$url" "$titulo"
  else printf '%s\tnao\t%s\t%s\t%s\n' "$n" "$at" "$url" "$titulo"; fi
done >> "$LISTA"

# Uma linha por url (autorizado vence a busca), números válidos, maior audiência primeiro.
OUT="$DADOS/lives_ranking.tsv"
awk -F'\t' '$1 ~ /^[0-9]+$/ && !seen[$4]++' <(sort -t$'\t' -k2,2r "$LISTA") | sort -t$'\t' -k1,1nr > "$OUT"
D="$(agora)"; sed "s/^/$D\t/" "$OUT" >> "$DADOS/lives_historico.tsv"
cat "$OUT"
