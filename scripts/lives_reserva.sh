#!/usr/bin/env bash
# Registro compartilhado de lives em gravação: impede duas sessões de gravar o mesmo streamer.
#   lives_reserva.sh reservar <streamer> <dono>   -> 0 = reservado (ou já era deste dono); 3 = ocupado por outro dono
#   lives_reserva.sh renovar  <streamer> <dono>   -> atualiza a batida (prova de vida) da reserva
#   lives_reserva.sh liberar  <streamer> <dono>   -> remove a reserva, só se for deste dono
#   lives_reserva.sh listar                       -> streamer<TAB>dono<TAB>segundos_desde_a_batida<TAB>situacao
#   lives_reserva.sh chave <url>                  -> chave do streamer (canal) de uma URL de live
# <streamer> = @ do canal ou apelido (normalizado: minúsculo, sem @). <dono> = pasta da gravação (única por sessão).
# Reserva sem batida há mais de RESERVA_EXPIRA_S (padrão 600 s) está "expirada": outra sessão pode assumir.
# mkdir é atômico: duas sessões reservando ao mesmo tempo nunca ganham as duas.
. "$(dirname "$0")/_comum.sh"
export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Links"
: "${RESERVA_EXPIRA_S:=600}"
R="$DADOS/lives_ativas"; mkdir -p "$R"
CMD="$1"; K="$(echo "${2:-}" | tr '[:upper:]' '[:lower:]' | tr -d '@[:space:]' | tr -c 'a-z0-9._\n-' '_')"; DONO="${3:-}"
idade() { echo $(( $(date +%s) - $(date -r "$1/batida" +%s 2>/dev/null || echo 0) )); }

case "$CMD" in
  reservar)
    [ -n "$K" ] && [ -n "$DONO" ] || { echo "uso: lives_reserva.sh reservar <streamer> <dono>" >&2; exit 1; }
    for _ in 1 2; do
      if mkdir "$R/$K" 2>/dev/null; then echo "$DONO" > "$R/$K/dono"; touch "$R/$K/batida"; echo "RESERVADO $K"; exit 0; fi
      atual="$(cat "$R/$K/dono" 2>/dev/null)"
      [ "$atual" = "$DONO" ] && { touch "$R/$K/batida"; echo "RESERVADO $K"; exit 0; }
      if [ "$(idade "$R/$K")" -gt "$RESERVA_EXPIRA_S" ]; then
        echo "reserva expirada de $K (dono: $atual): assumindo" >&2; rm -rf "$R/$K"; continue
      fi
      echo "OCUPADO $K por $atual"; exit 3
    done
    echo "OCUPADO $K (disputa)"; exit 3 ;;
  renovar)
    [ "$(cat "$R/$K/dono" 2>/dev/null)" = "$DONO" ] && touch "$R/$K/batida" || { echo "reserva de $K não é de $DONO" >&2; exit 3; } ;;
  liberar)
    [ "$(cat "$R/$K/dono" 2>/dev/null)" = "$DONO" ] && rm -rf "${R:?}/$K" && echo "LIBERADO $K" ;;
  listar)
    for d in "$R"/*/; do
      [ -d "$d" ] || continue; d="${d%/}"; s=$(idade "$d")
      printf '%s\t%s\t%s\t%s\n' "$(basename "$d")" "$(cat "$d/dono" 2>/dev/null)" "$s" \
        "$([ "$s" -gt "$RESERVA_EXPIRA_S" ] && echo expirada || echo ativa)"
    done ;;
  chave)
    # YouTube: uploader_id = @canal; Twitch: login do canal.
    yt-dlp --no-warnings --skip-download --print "%(uploader_id,channel_id,uploader)s" "$2" < /dev/null 2>/dev/null | head -1 ;;
  *) echo "uso: lives_reserva.sh reservar|renovar|liberar <streamer> <dono> | listar | chave <url>" >&2; exit 1 ;;
esac
