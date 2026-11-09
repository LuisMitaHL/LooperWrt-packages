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
  `ap-isolation`, `ap-network-defaults`, `pasankalla`, `tailscale-lowmem`) carry a static base `PKG_VERSION`; the builder stamps `<base>.<YYYYMMDD>.<epoch>` at build time.
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
- `pasankalla` is feed-native (no vendor repo): Cudy TR3000/TR1200
  travel-router defaults. `zz-pasankalla` creates the guest `lanclientes`
  bridge/subnet + DHCP + firewall membership and one OWE-only `Pasankalla gratis`
  AP per built-in band (disabled until the slider is on), adopting an existing
  open+hidden-OWE transition pair on an already-configured router. The
  `/usr/sbin/pasankalla` state machine moves travelmate between the built-in
  5 GHz and a hot-plugged USB WiFi radio, suspends private APs on the radio
  travelmate scans, drives `white:status`/`red:power` with kernel timer
  triggers (written only on state change), and logs button/iface/phy events
  plus state transitions to syslog. At boot it waits `wan_grace` seconds
  (default 20) for the ethernet WAN DHCP lease before starting travelmate.
  Travelmate is enabled by default (`trm_enabled=1` plus the rc.d link) and
  stays enabled; while the WAN owns the uplink pasankalla stops it and
  unplugs its STAs from `network.trm_wwan` (a STA left on it would outbid
  the WAN route, metric 100). Which side owns the uplink is kept in
  `/tmp/pasankalla/tm`: a running travelmate takes its own rc.d link out
  once nothing is left to scan, so the init's enabled flag must never be
  used as the state. It keeps the antilag
  instance on the netdev that currently carries the uplink (`ul_if` = WAN
  `l3_device`, or the travelmate STA when WAN is down; `dl_if` =
  `ifb-<dev>`). One-shot service defaults on first boot (`defaults_version`
  marker): antilag enabled on the WAN netdev, tailscale and tswatchdog
  stopped and disabled when installed. Selected only on
  `pasankalla`/`pasankalla_lite` via `configs/pasankalla.config`.
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
