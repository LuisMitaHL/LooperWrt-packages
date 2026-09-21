# AGENTS.md — LooperWrt-packages

Single custom OpenWrt feed; source of truth for all owned packages. Consumed by
the builder as `src-git looperwrt` (first entry in `feeds.conf.default` on the
`openwrt-25.12-aurora` branch of `LuisMitaHL/LooperWrt`). See `README.md` for
the package table and the net-snmp rebase procedure — don't duplicate them here.

## Rules

- Flat layout: one directory per package with its `Makefile` at the package
  root; `scripts/feeds` scans this directly. No wrapper feeds needed.
- Overrides of stock `packages`-feed copies (`net-snmp`, `tailscale`): track
  the upstream version, are **never HEAD-stamped**, and the builder must
  `feeds uninstall` the stock package before `feeds install` so the feed copy
  wins. Builder side lives in `laotrared-aurora-build/build-firmware.sh`
  (`prepare_feeds`, `stamp_looperwrt_versions`, `verify_looperwrt`).
- HEAD-owned packages (`antilag`, `luci-app-antilag`, `tailscale-route-watchdog`,
  `mwan3-bootfix`, `snmpd-defaults`, `snmpd-librenms`) carry a static base
  `PKG_VERSION`; the builder stamps `<base>.<YYYYMMDD>.<epoch>` at build time.
  `snmpd-librenms` pins its upstream download in `PKG_SOURCE_VERSION`, never
  in `PKG_VERSION`.
- Commit style: plain descriptive subject (see `git log`). The user controls
  pushes; commit locally, push only on request.
- snmpd packages (`snmpd-defaults`, `snmpd-librenms`): OpenWrt's config is
  UCI `/etc/config/snmpd` (never `/etc/default/snmpd`, which is Debian);
  `uci` section ids are `[A-Za-z0-9_]` only; never restore that file by
  copying over it (a later `uci commit` replays the in-memory delta); use
  busybox `flock` in a subshell for locks. The wireless trigger is
  `ubus subscribe hostapd` (`bss.add`/`bss.remove`), **not**
  `/etc/hotplug.d/ieee80211`. `README.md` "snmpd field notes" has the full
  list with the router/test details.
