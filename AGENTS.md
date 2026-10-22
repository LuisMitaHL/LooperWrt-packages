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
  `mwan3-bootfix`, `snmpd-defaults`, `snmpd-librenms`, `dhcpoptinj`,
  `ap-isolation`, `ap-network-defaults`, `tailscale-lowmem`) carry a static base `PKG_VERSION`; the builder stamps `<base>.<YYYYMMDD>.<epoch>` at build time.
  `snmpd-librenms` pins its upstream download in `PKG_SOURCE_VERSION`, never
  in `PKG_VERSION`; `dhcpoptinj` follows the same rule (HTTPS git pin at
  `https://github.com/LuisMitaHL/dhcpoptinj`).
- `dhcpoptinj`, `ap-isolation`, `antilag` and `luci-app-antilag` pin their
  sources from upstream git repos (`dhcpoptinj` from `LuisMitaHL/dhcpoptinj`;
  `ap-isolation` from `LuisMitaHL/openwrt-public-ap-isolation`, whose repo root
  is the package root; `antilag` and `luci-app-antilag` from the same dev
  repo `LuisMitaHL/laotrared-openwrt-antilag`, with the LuCI app installing
  `luci-app-antilag/www` + `po` from the checkout and keeping `menu.d`/`acl.d`
  inline). This feed is the build recipe; bump `PKG_SOURCE_VERSION`
  (+ `PKG_SOURCE_DATE`) in both pin Makefiles when the dev repo changes.
  Both ap-isolation families are selected on every `ap` profile via
  `configs/ap.config` in the builder. The `ap-isolation` Makefile also defines
  the qca8k-only `ap-isolation-fdb` add-on (stale-ATU roaming workaround),
  selected only in `configs/target-ipq40xx.config` and disabled by default.
- `fullconenat-nft` is a **kernel package**: it has no `PKG_VERSION`, so it is never HEAD-stamped and is not in `LOOPERWRT_PKGS`. The builder verifies it separately (`LOOPERWRT_NOVERSION_PKGS` in `verify_fullcone_carry`). It is selected only on `core`/`core_lite`; the package's `files/95-fullcone` uci-defaults enables `firewall.@defaults[0].fullcone` when unset. Do not add a LuCI app or patch `luci-app-firewall` for it: the option survives LuCI edits (delta-based UCI save) but is intentionally invisible; the UCI command is documented.
- `ap-network-defaults` is feed-native (no vendor repo): the uci-defaults
  script `zz-ap-network-defaults` converting ap images to dumb-AP networking
  (all physical ports → br-lan, wan iface removed, lan as DHCP client,
  DHCPv4/DHCPv6/RA servers off, antilag disabled). Also selected on every
  `ap` profile via `configs/ap.config`.
- Commit style: plain descriptive subject (see `git log`). The user controls
  pushes; commit locally, push only on request.
- snmpd packages (`snmpd-defaults`, `snmpd-librenms`): OpenWrt's config is
  UCI `/etc/config/snmpd` (never `/etc/default/snmpd`, which is Debian);
  `uci` section ids are `[A-Za-z0-9_]` only; never restore that file by
  copying over it (a later `uci commit` replays the in-memory delta); use
  busybox `flock` in a subshell for locks; `/etc/init.d/snmpd reload` is a
  no-op for config changes (no `reload_service`) — use `restart`. The
  wireless trigger is `ubus subscribe hostapd` (`bss.add`/`bss.remove`),
  **not** `/etc/hotplug.d/ieee80211`. `README.md` "snmpd field notes" has the
  full list with the router/test details.
