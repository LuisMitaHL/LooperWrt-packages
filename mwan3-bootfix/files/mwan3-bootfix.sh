#!/bin/sh
# mwan3-bootfix worker: sleep, then restart mwan3 exactly once.
# Launched in background by /etc/init.d/mwan3-bootfix at boot (START=99).

. /lib/functions.sh

TAG="mwan3-bootfix"

config_load mwan3-bootfix 2>/dev/null
config_get_bool enabled config enabled 1
config_get delay config delay 180

if [ "$enabled" != "1" ]; then
	logger -t "$TAG" "disabled in /etc/config/mwan3-bootfix, skipping"
	exit 0
fi

case "$delay" in
	''|*[!0-9]*)
		logger -t "$TAG" "bad delay '$delay', using 180"
		delay=180
		;;
esac

# Guards: only restart when mwan3 is actually installed and configured.
[ -x /etc/init.d/mwan3 ] || {
	logger -t "$TAG" "/etc/init.d/mwan3 missing, skipping"
	exit 0
}
[ -f /etc/config/mwan3 ] || {
	logger -t "$TAG" "/etc/config/mwan3 missing, skipping"
	exit 0
}

sleep "$delay"

logger -t "$TAG" "restarting mwan3 once (delay=${delay}s)"
if /etc/init.d/mwan3 restart; then
	logger -t "$TAG" "mwan3 restart done"
else
	logger -t "$TAG" "mwan3 restart failed"
fi
