#!/bin/sh
# Renders the Asterisk config from templates + environment, then starts
# Asterisk in the foreground. This is the per-customer rollout lever: the
# image is identical everywhere, only .env differs.
set -eu

log() { echo "hermes-asterisk: $*" >&2; }

: "${FRITZBOX_HOST:=192.168.178.1}"
: "${ARI_USER:=hermes}"
: "${HERMES_CALL_MODE:=test}"
: "${RTP_START:=10000}"
: "${RTP_END:=10200}"

missing=""
for var in FRITZBOX_SIP_USER FRITZBOX_SIP_PASSWORD ARI_PASSWORD; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || missing="$missing $var"
done
if [ -n "$missing" ]; then
  log "fehlende Einstellungen in .env:$missing (siehe docs/fritzbox.md)"
  exit 1
fi

case "$HERMES_CALL_MODE" in
  test | stasis) ;;
  *) log "HERMES_CALL_MODE muss 'test' oder 'stasis' sein, nicht '$HERMES_CALL_MODE'"; exit 1 ;;
esac

# SIP only listens on the interface that faces the Fritz!Box (never 0.0.0.0).
if [ -z "${SIP_BIND_ADDRESS:-}" ]; then
  SIP_BIND_ADDRESS=$(ip -4 route get "$FRITZBOX_HOST" 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
fi
if [ -z "$SIP_BIND_ADDRESS" ]; then
  log "keine Route zur Fritz!Box $FRITZBOX_HOST – SIP_BIND_ADDRESS bitte in .env setzen"
  exit 1
fi

# ARI only listens on the Docker bridge, where the app container reaches it as
# host.docker.internal. Not reachable from the LAN.
if [ -z "${ARI_BIND_ADDRESS:-}" ]; then
  ARI_BIND_ADDRESS=$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  : "${ARI_BIND_ADDRESS:=127.0.0.1}"
fi

# ";" starts a comment in Asterisk config files and must be escaped.
escape() { printf '%s' "$1" | sed 's/;/\\;/g'; }
FRITZBOX_SIP_PASSWORD=$(escape "$FRITZBOX_SIP_PASSWORD")
ARI_PASSWORD=$(escape "$ARI_PASSWORD")

export FRITZBOX_HOST FRITZBOX_SIP_USER FRITZBOX_SIP_PASSWORD SIP_BIND_ADDRESS \
  ARI_BIND_ADDRESS ARI_USER ARI_PASSWORD HERMES_CALL_MODE RTP_START RTP_END

# Only our variables are substituted; dialplan variables like ${EXTEN} stay intact.
vars='$FRITZBOX_HOST $FRITZBOX_SIP_USER $FRITZBOX_SIP_PASSWORD $SIP_BIND_ADDRESS
$ARI_BIND_ADDRESS $ARI_USER $ARI_PASSWORD $HERMES_CALL_MODE $RTP_START $RTP_END'

umask 077
for template in /etc/asterisk/templates/*.conf; do
  envsubst "$vars" <"$template" >"/etc/asterisk/$(basename "$template")"
done

log "Fritz!Box $FRITZBOX_HOST als $FRITZBOX_SIP_USER, SIP auf $SIP_BIND_ADDRESS:5060," \
  "ARI auf $ARI_BIND_ADDRESS:8088, RTP $RTP_START-$RTP_END, Modus $HERMES_CALL_MODE"

exec asterisk -f
