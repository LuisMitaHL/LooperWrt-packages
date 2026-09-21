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
