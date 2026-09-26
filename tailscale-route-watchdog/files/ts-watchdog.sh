#!/bin/sh
# ts-watchdog supervisor - runs one watchdog cycle per interval.
#
# The ucode helper is one-shot on purpose: a long-lived interpreter was
# fragile on low-CPU routers (any internal failure takes down all future
# cycles and resets every rate limiter), while a per-cycle process
# contains any failure - it is logged here and retried next interval.
# Cross-cycle state lives in /tmp/tswatchdog.state (written by the ucode
# helper), so rate limiters and the table snapshot survive a supervisor
# restart.

BIN=/usr/bin/ts-watchdog-cycle.uc

interval="$(uci -q get tswatchdog.config.interval 2>/dev/null)"
case "$interval" in
	''|*[!0-9]*) interval=30 ;;
esac
[ "$interval" -lt 5 ] && interval=5

logger -t ts-watchdog -p daemon.info "supervisor started (interval=${interval}s)"

while :; do
	ucode "$BIN"
	rc=$?
	# 0 = clean cycle (healthy, healed or skipped). Anything else is an
	# internal error - logged and retried next interval either way.
	[ "$rc" -ne 0 ] && logger -t ts-watchdog -p daemon.warn "cycle failed rc=$rc"

	sleep "$interval"
done
