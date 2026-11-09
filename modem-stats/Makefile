#
# modem-stats - Huawei HiLink modem statistics collector (ucode daemon).
#
# Feed-native package (no vendor repo): polls a Huawei HiLink MiFi modem
# (verified against the E5576-508, fw 11.0.1.1(H697SP3C266)) over its
# XML-over-HTTP API and exposes the result as a JSON snapshot in
# /tmp/modem-stats.json plus a ubus object so LuCI/other daemons can read
# the data without re-polling the modem.
#
# Authentication is the firmware's SCRAM flow (password_type=4):
# GET /api/webserver/SesTokInfo -> POST /api/user/challenge_login ->
# POST /api/user/authentication_login, using the challenge response's
# __RequestVerificationToken header (NOT the SesTokInfo token) and then the
# __RequestVerificationTokenone header from the auth response. Session is
# kept alive with /api/user/heartbeat and re-established on 125002/125003.
#
# Designed for weak targets (mt7628, 16 MiB flash): pure ucode, HTTP spoken
# directly via ucode-mod-socket (already selected in all fleet images), no
# uclient-fetch subprocess, no curl, no extra libraries. The daemon sleeps
# between polls and keeps at most one snapshot in /tmp.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=modem-stats
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/modem-stats
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Wireless
  TITLE:=Huawei HiLink modem statistics collector (ucode)
  DEPENDS:=+ucode +ucode-mod-socket +ucode-mod-digest +ucode-mod-uci +ucode-mod-ubus +ucode-mod-fs
endef

define Package/modem-stats/description
  Collects LTE metadata, battery status and traffic statistics from a
  Huawei HiLink modem-router (E5576 family, XML-over-HTTP API) and exposes
  them as a JSON snapshot (/tmp/modem-stats.json) and a ubus object
  modem-stats (method "all" returns the snapshot, "refresh" forces a poll).

  Uses the SCRAM login required by modern HiLink firmware (password_type=4)
  and keeps the session alive with heartbeat calls. Pure ucode; HTTP is
  implemented on top of ucode-mod-socket, so nothing besides ucode and its
  fleet-standard modules is needed.
endef

define Package/modem-stats/conffiles
/etc/config/modem-stats
endef

define Build/Compile
endef

define Package/modem-stats/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/modem-stats.uc $(1)/usr/bin/modem-stats
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/init $(1)/etc/init.d/modem-stats
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/config $(1)/etc/config/modem-stats
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/zz-modem-stats $(1)/etc/uci-defaults/zz-modem-stats
endef

$(eval $(call BuildPackage,modem-stats))
