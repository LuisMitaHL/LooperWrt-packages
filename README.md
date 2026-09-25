# LooperWrt-packages

Single custom OpenWrt feed for LooperWrt builds (`openwrt-25.12`).
Source of truth for all owned packages. Consumed as:

```
src-git looperwrt https://github.com/LuisMitaHL/LooperWrt-packages.git;main
```

## Packages

| Package | Base version | Notes |
|---|---|---|
| `antilag` | 1.0.0 | CAKE autorate daemon (C, procd). No LuCI inside. |
| `luci-app-antilag` | 1.0.0 | LuCI UI for antilag (menu.d, rpcd ACL, JS views, `es` lmo). `DEPENDS +antilag`. |
| `tailscale-route-watchdog` | 0.1 | Self-healing watchdog for Tailscale policy routing (table 52). Aurora core only. |
| `mwan3-bootfix` | 0.1 | One-shot delayed `mwan3 restart` after boot. Core only. |
| `snmpd-defaults` | 1.0.0 | LooperWrt snmpd defaults (agent `UDP:16161`, `access_default` community, location/contact, temperature/conntrack/hardware extends). Applied by `/etc/uci-defaults`, **replace** semantics: drops stock `UDP:161` and the stock `public` community. `DEPENDS +snmpd-nossl`. |
| `snmpd-librenms` | 1.0.0 | LibreNMS OpenWrt agent + dynamic wireless extends. Fetches the collector scripts at build time from a pinned `librenms/librenms-agent` commit. A procd service watches hostapd `bss.add`/`bss.remove` and reconciles `/etc/config/snmpd` + `/etc/librenms/wlInterfaces.txt` (band+SSID names) only when the AP set changes. `DEPENDS +snmpd-defaults +iw +iwinfo`. |
| `net-snmp` | 5.9.4-7 | **Override** of `packages/net/net-snmp` (stock 5.9.4-6). Only deltas: `PKG_RELEASE` 6→7 and `--with-persistent-directory=/tmp/snmp/` (tmpfs, avoids flash wear; stock uses `/usr/lib/snmp/`). Rebase procedure below. |
| `tailscale` | 1.102.4 | **Override** of `packages/net/tailscale` (newer upstream than the stock 25.12 feed copy). Upstream-tracked version: never HEAD-stamped. Migrated from the in-tree `package/net/tailscale` on `openwrt-25.12-aurora`. |
| `dhcpoptinj` | 0.5.4 | DHCP option injector daemon (nftables bridge queue, procd init, UCI, `dhcpoptinj-enc82` helper). Vendored from the deprecated `LuisMitaHL/dhcpoptinj-openwrt` recipe; sources from the fork `https://github.com/LuisMitaHL/dhcpoptinj` (HTTPS git, pinned `PKG_SOURCE_VERSION`, `PKG_MIRROR_HASH:=skip`). Ships `enabled '0'`. `DEPENDS +libnetfilter-queue +nftables +kmod-nft-queue`. |
| `ap-isolation` | 1.0.0 | Public-AP client isolation via nftables (bridge ARP/broadcast/multicast blocking, DHCP + gateway still pass; UCI + hotplug + `ap-isolation.sh`). Vendor copy of `https://github.com/LuisMitaHL/openwrt-public-ap-isolation` package root — feed dir is `ap-isolation` (= package name), repo name differs. Ships `enabled '0'` (opt-in). `DEPENDS +nftables`. |
| `ap-network-defaults` | 1.0.0 | First-boot (uci-defaults `zz-ap-network-defaults`) dumb-AP conversion for `ap` profile images: every physical port becomes a br-lan port and the wan interface is removed, lan switches to a DHCP client, DHCPv4/DHCPv6/RA servers are off (dnsmasq keeps serving DNS), antilag disabled (no L3 uplink left to shape). Apply-once via the `looperwrt.ap_netdefaults` marker; named `zz-*` so it runs after the branch `99_*-defaults`. Feed-native (no vendor repo). |

Build-time version stamp rewrites each `PKG_VERSION` to
`<base>.<YYYYMMDD>.<epoch>` from this feed's HEAD (numeric dotted form,
apk-safe). Exemptions: `net-snmp` and `tailscale` track upstream releases
and are never stamped. See `build-firmware.sh` `stamp_looperwrt_versions`.

## snmpd package split

Three packages, deliberately separated:

- `net-snmp` stays a thin upstream override (daemon + `/tmp/snmp` fix).
- `snmpd-defaults` is the independent set: useful on any device with snmpd,
  and it pulls in neither wireless tooling nor a build-time download.
- `snmpd-librenms` owns the external fetch, the wireless collectors and the
  dynamic reconciler (see below).

### snmpd-librenms download pin

The collector scripts come from `librenms/librenms-agent` at the commit in
`PKG_SOURCE_VERSION`; the tarball `PKG_HASH` is verified. `PKG_SOURCE_VERSION`
is kept separate from `PKG_VERSION` on purpose — the builder HEAD-stamps
`PKG_VERSION`, which must not leak into the source URL or build dir name.

To rebase onto a newer `librenms-agent`:

1. Bump `PKG_SOURCE_VERSION` to the new commit.
2. Refresh the hash:
   `curl -sSL https://codeload.github.com/librenms/librenms-agent/tar.gz/<commit> | sha256sum`.
3. Update `PKG_HASH`, then `make download` on the builder.

### snmpd-librenms dynamic reconciliation

`/usr/sbin/snmpd-librenms-sync` derives the desired extend set from the live
wdevs (`iw dev`), names each AP `<band>-<SSID>` in `wlInterfaces.txt`, and
reconciles `uci` sections prefixed `lnms_` in `/etc/config/snmpd`. UCI
section identifiers allow only `[A-Za-z0-9_]`, so ifnames are key-sanitised.

Flash-wear control: the desired set is diffed against what is already on
flash, `bss.add`/`bss.remove` bursts are coalesced (`debounce`), and real
writes are rate-limited (`cooldown`) via `/etc/config/snmpd-librenms`.
`/etc/config/snmpd` is only ever changed through `uci` — never rewrite the
file directly, or a later `uci commit` replays its in-memory delta over your
edit.

Every reconcile that writes logs its delta to syslog, tag `snmpd-librenms`
(`logread -e snmpd-librenms`): one line per extend added/removed, the
`wlInterfaces.txt` `-`/`+` delta, the snmpd restart result, then a
`reconciled uci=… wlInterfaces=…` summary. No-change runs stay silent, so any
line means flash was written.

## snmpd field notes (learned the hard way)

UCI / config:

- OpenWrt's config is `/etc/config/snmpd` (UCI). `/etc/default/snmpd` is the
  Debian path and does not exist here.
- `uci` section identifiers accept only `[A-Za-z0-9_]`. A section key built
  from an ifname (`...phy0-ap0`) fails `uci set` with `Invalid argument`; run
  that under `uci -q` and the failure is silent. Key-sanitise ifnames.
- Never restore `/etc/config/snmpd` by copying a file over it: `uci` keeps an
  in-memory delta and a later `uci commit` replays it over the copy, undoing
  the restore. Restore through `uci`, or copy *and* `rm -f /tmp/.uci/snmpd`
  before the next `uci` call.
- The snmpd initscript defines **no `reload_service`**, so
  `/etc/init.d/snmpd reload` falls through to `start`: it rewrites
  `/var/run/snmpd.conf` but does **not** restart the daemon, leaving the
  running snmpd on its old config. Use `restart` whenever the generated config
  changed (`snmpd-librenms-sync` does). Symptom of getting this wrong: the
  config file shows the extends but `snmpwalk ... 1.3.6.1.4.1.8072.1.3.2.2.1.2`
  lists only the handful the daemon started with.

Dynamic trigger:

- The per-wdev trigger is `ubus subscribe hostapd`, emitting
  `{ "bss.add": {"name": "phy0-ap1"} }` and `bss.remove`.
  `ubus call network.wireless status` is the band + SSID source.
- `/etc/hotplug.d/ieee80211/` does **not** fire on `wifi up`/`wifi reload`
  (it is a wiphy-add hook, cf. `10-wifi-detect`). `wifi reload` *does* emit
  `bss.add` for a newly configured AP.
- Lock the reconciler with busybox `flock`, scoped to a subshell. A `mkdir`
  lock goes stale when a run is killed (SIGPIPE/SIGKILL), and an `exec 9>`
  held by a long-lived watcher blocks every later run forever.

Dev router (`root@192.168.1.1`):

- The SSH host key has changed at least once (reflash). Use a throwaway
  `UserKnownHostsFile` instead of editing the shared `known_hosts`.
- BusyBox only: no `base64`, no `pkill`; `flock` is a busybox applet.
- This workspace's host has `snmpwalk`/`snmpget`, so the router can be
  queried directly, e.g.
  `snmpget -v2c -c publicagentxD -Oqnv 192.168.1.1:16161 'NET-SNMP-EXTEND-MIB::nsExtendOutputFull."frequency-phy0-ap0"'`.
- To uninstall: stop/disable the service, remove `/etc/librenms`,
  `/etc/config/snmpd-librenms`, `/etc/init.d/snmpd-librenms`,
  `/usr/sbin/snmpd-librenms-sync`, `/etc/uci-defaults/99-snmpd-defaults`,
  delete the `lnms_*` extends, then restore the stock `/etc/config/snmpd`.

## Layout

Flat feed root: one directory per package, each with `Makefile`
(+ `files/`, `src/`/`po/` where applicable). No category subdirs needed;
`scripts/feeds` scans this layout.

## net-snmp rebase

When the `packages` feed bumps `net/net-snmp`:

1. Copy the new stock package over `net-snmp/` (keep `patches/` from stock).
2. Re-apply the two deltas: `PKG_RELEASE:=<stock+1>`,
   `--with-persistent-directory=/tmp/snmp/`.
3. Verify: `grep -n persistent net-snmp/Makefile`, then
   `scripts/feeds update looperwrt && scripts/feeds install net-snmp`
   must install from `looperwrt`, and `verify_looperwrt` on the builder
   must pass.
