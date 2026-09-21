#
# LooperWrt snmpd defaults - the "independent" set of snmpd settings.
#
# These are applied through /etc/uci-defaults instead of shipping a replacement
# /etc/config/snmpd: that file is the conffile owned by snmpd-nossl, so
# overwriting it would drop both the stock sections and any operator edits.
# The defaults script touches only the sections it owns and is idempotent.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=snmpd-defaults
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/snmpd-defaults
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LooperWrt snmpd defaults
  DEPENDS:=+snmpd-nossl
endef

define Package/snmpd-defaults/description
 LooperWrt defaults for the net-snmp daemon, useful on their own without any
 LibreNMS or wireless pieces: the LooperWrt agent port and read community,
 location/contact, and the always-available extends (temperature, conntrack,
 hardware).

 Uses replace semantics: the stock UDP:161 listener and the stock "public"
 read community are dropped so that only UDP:16161 and the LooperWrt
 community remain. Applied once via /etc/uci-defaults, safe to re-run.
endef

define Package/snmpd-defaults/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
if [ -x /etc/uci-defaults/99-snmpd-defaults ]; then
	/etc/uci-defaults/99-snmpd-defaults
	rm -f /etc/uci-defaults/99-snmpd-defaults
fi
exit 0
endef

define Build/Compile
endef

define Package/snmpd-defaults/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/99-snmpd-defaults $(1)/etc/uci-defaults/99-snmpd-defaults
endef

$(eval $(call BuildPackage,snmpd-defaults))
