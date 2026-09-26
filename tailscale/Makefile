#
# Copyright (C) 2021 CZ.NIC, z. s. p. o. (https://www.nic.cz/)
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=tailscale
PKG_VERSION:=1.102.4
PKG_RELEASE:=2

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/tailscale/tailscale/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=784b023e825e1cca7b146ac6a7aff08b179d60d10839b51019f315dab426c871

PKG_MAINTAINER:=Zephyr Lykos <self@mochaa.ws>, \
		Sandro Jäckel <sandro.jaeckel@gmail.com>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:tailscale:tailscale

PKG_BUILD_DIR:=$(BUILD_DIR)/tailscale-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=tailscale.com/cmd/tailscaled
# -s -w: drop Go symbol table + DWARF (OpenWrt strips anyway; saves ~20%).
GO_PKG_LDFLAGS:=-s -w -X 'tailscale.com/version.longStamp=$(PKG_VERSION)-$(PKG_RELEASE) (OpenWrt)'
GO_PKG_LDFLAGS_X:=tailscale.com/version.shortStamp=$(PKG_VERSION)
# "extra-small" feature set for 16 MiB flash devices (mt7621 etc.).
# Generated with the upstream resolver (regenerate on every version bump —
# never hand-edit, tags drift between releases):
#   go run ./cmd/featuretags --min --add=cli,osrouter,advertiseroutes,advertiseexitnode,useroutes,useexitnode,dns,portmapper,cachenetmap,health,unixsocketidentity,ipnbus
# (then strip ts_omit_debug again, see NOTE below — featuretags --min emits it).
# Kept on purpose: headscale OIDC login (--login-server), subnet routers,
# exit nodes, --advertise-tags, MagicDNS/DNS config, NAT-PMP/UPnP for
# port forwards, unix socket LocalAPI identity.
# NOTE: ipnbus deliberately kept (featuretags --min would omit it).
# tailscale#20709: the HasIPNBus gate in cmd/tailscale/cli/up.go sits
# BEFORE Start()/StartLoginInteractive(), so a ts_omit_ipnbus build's
# `tailscale up` prints "binary built with ts_omit_ipnbus; not waiting
# for completion" and never starts the backend or login (no auth URL,
# prefs unapplied) — headscale OIDC login would be impossible. The
# daemon also skips registering /localapi/v0/watch-ipn-bus, the stream
# that surfaces AuthURL. Upstream bug, open; cost of keeping it is ~0
# (gate is a const bool + one localapi route).
# Dropped: ts ssh, serve/funnel (+netstack via dep), iptables (fw4=nftables
# only), bakedroots (ca-bundle already a hard dep), logtail/netlog (TS_NO_LOGS_NO_SUPPORT),
# self-update, cloud/NAS integrations, taildrop, tap, tpm.
# NOTE: ts_omit_debug is deliberately NOT set — ipn/localapi/debug.go
# (gated !ts_omit_debug) serves "current-netmap" and "force-netmap-update",
# which tailscale-route-watchdog's `tailscale debug netmap|force-netmap-update`
# heal path depends on.
GO_PKG_TAGS:=ts_include_cli,ts_omit_ace,ts_omit_acme,ts_omit_appconnectors,ts_omit_aws,ts_omit_bakedroots,ts_omit_bird,ts_omit_captiveportal,ts_omit_capture,ts_omit_cliconndiag,ts_omit_clientmetrics,ts_omit_clientupdate,ts_omit_cloud,ts_omit_colorable,ts_omit_completion,ts_omit_completion_scripts,ts_omit_conn25,ts_omit_dbus,ts_omit_debugeventbus,ts_omit_debugportmapper,ts_omit_desktop_sessions,ts_omit_doctor,ts_omit_drive,ts_omit_flashappliance,ts_omit_gro,ts_omit_hujsonconf,ts_omit_identityfederation,ts_omit_iptables,ts_omit_kube,ts_omit_linkspeed,ts_omit_linuxdnsfight,ts_omit_listenrawdisco,ts_omit_logtail,ts_omit_netlog,ts_omit_netstack,ts_omit_networkmanager,ts_omit_oauthkey,ts_omit_outboundproxy,ts_omit_portlist,ts_omit_posture,ts_omit_qrcodes,ts_omit_relayserver,ts_omit_remoteconfig,ts_omit_resolved,ts_omit_routecheck,ts_omit_runtimemetrics,ts_omit_sdnotify,ts_omit_serve,ts_omit_serviceclientprefs,ts_omit_ssh,ts_omit_synology,ts_omit_syslog,ts_omit_syspolicy,ts_omit_systray,ts_omit_taildrop,ts_omit_tailnetlock,ts_omit_tap,ts_omit_tpm,ts_omit_tundevstats,ts_omit_useproxy,ts_omit_usermetrics,ts_omit_wakeonlan,ts_omit_webbrowser,ts_omit_webclient

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/tailscale
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Zero config VPN
  URL:=https://tailscale.com
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-tun
  PROVIDES:=tailscaled
endef

define Package/tailscale/description
  It creates a secure network between your servers, computers,
  and cloud instances. Even when separated by firewalls or subnets.
endef

define Package/tailscale/conffiles
/etc/config/tailscale
/etc/tailscale/
endef

define Package/tailscale/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/tailscaled $(1)/usr/sbin
	$(LN) tailscaled $(1)/usr/sbin/tailscale
	$(INSTALL_BIN) ./files//tailscale.init $(1)/etc/init.d/tailscale
	$(INSTALL_DATA) ./files//tailscale.conf $(1)/etc/config/tailscale
endef

$(eval $(call BuildPackage,tailscale))
