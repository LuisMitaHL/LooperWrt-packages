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
| `net-snmp` | 5.9.4-7 | **Override** of `packages/net/net-snmp` (stock 5.9.4-6). Only deltas: `PKG_RELEASE` 6→7 and `--with-persistent-directory=/tmp/snmp/` (tmpfs, avoids flash wear; stock uses `/usr/lib/snmp/`). Rebase procedure below. |

Build-time version stamp rewrites each `PKG_VERSION` to
`<base>.<YYYYMMDD>.<epoch>` from this feed's HEAD (numeric dotted form,
apk-safe). See `build-firmware.sh` `stamp_looperwrt_versions`.

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
