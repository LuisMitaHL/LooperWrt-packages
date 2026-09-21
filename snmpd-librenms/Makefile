#
# snmpd-librenms - LibreNMS OpenWrt agent + dynamic wireless extends.
#
# The collector scripts are fetched at build time from the pinned librenms-agent
# commit below (PKG_HASH verified, cached in dl/). They are deliberately not
# vendored into this feed: rebasing is a one-line PKG_SOURCE_VERSION/PKG_HASH
# bump once the new tarball hash is known.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=snmpd-librenms
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

# Pinned upstream commit (librenms/librenms-agent). Kept separate from
# PKG_VERSION so the builder's HEAD stamp of PKG_VERSION cannot disturb the
# download URL or the unpacked directory name.
PKG_SOURCE_VERSION:=37a7d54aa7eb4e219913af173f02ef66c73bfcb0
PKG_SOURCE:=librenms-agent-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/librenms/librenms-agent/tar.gz/$(PKG_SOURCE_VERSION)?
PKG_HASH:=3564f54219e955765c3818f987e3f2349217f48af956573e6c0ece1913aa6cdb
# Must match the archive's top-level directory: the default unpack extracts
# into $(PKG_BUILD_DIR)/.. and then builds in $(PKG_BUILD_DIR).
PKG_BUILD_DIR:=$(BUILD_DIR)/librenms-agent-$(PKG_SOURCE_VERSION)

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/snmpd-librenms
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LibreNMS agent and dynamic wireless extends for snmpd
  DEPENDS:=+snmpd-defaults +iw +iwinfo
endef

define Package/snmpd-librenms/description
 Ships the LibreNMS OpenWrt collector scripts under /etc/librenms and keeps
 snmpd's extend configuration in step with the live wireless interfaces.

 The OS-detection script and the wireless collector scripts are downloaded at
 build time from librenms-agent. A procd service watches hostapd for bss.add /
 bss.remove events and reconciles /etc/config/snmpd and
 /etc/librenms/wlInterfaces.txt only when the set of AP interfaces actually
 changes, so wireless churn does not wear the flash.
endef

define Package/snmpd-librenms/conffiles
/etc/config/snmpd-librenms
endef

define Package/snmpd-librenms/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/snmpd-librenms enable
/etc/init.d/snmpd-librenms start
exit 0
endef

define Package/snmpd-librenms/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/snmpd-librenms stop
/etc/init.d/snmpd-librenms disable
exit 0
endef

define Build/Compile
endef

define Package/snmpd-librenms/install
	$(INSTALL_DIR) $(1)/etc/librenms
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/Openwrt/wlClients.sh $(1)/etc/librenms/wlClients.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/Openwrt/wlFrequency.sh $(1)/etc/librenms/wlFrequency.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/Openwrt/wlNoiseFloor.sh $(1)/etc/librenms/wlNoiseFloor.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/Openwrt/wlRate.sh $(1)/etc/librenms/wlRate.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/Openwrt/wlSNR.sh $(1)/etc/librenms/wlSNR.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/snmp/distro $(1)/etc/librenms/distro

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/snmpd-librenms-sync $(1)/usr/sbin/snmpd-librenms-sync

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/snmpd-librenms.init $(1)/etc/init.d/snmpd-librenms

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/snmpd-librenms.config $(1)/etc/config/snmpd-librenms
endef

$(eval $(call BuildPackage,snmpd-librenms))
