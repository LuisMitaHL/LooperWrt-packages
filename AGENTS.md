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
  `mwan3-bootfix`) carry a static base `PKG_VERSION`; the builder stamps
  `<base>.<YYYYMMDD>.<epoch>` at build time.
- Commit style: plain descriptive subject (see `git log`). The user controls
  pushes; commit locally, push only on request.
