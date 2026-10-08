include $(TOPDIR)/rules.mk

# ap-isolation - public-AP client isolation via nftables.
#
# The package root lives in the vendor repo below (repo root == package root).
# This feed recipe only pins and installs it, following the dhcpoptinj pattern:
# bump PKG_SOURCE_VERSION (+ PKG_SOURCE_DATE) when the vendor repo changes.
# PKG_VERSION stays the static base the builder HEAD-stamps and is unrelated to
# the source pin. Feed dir == package name (ap-isolation) as required by the
# builder's stamp_looperwrt_versions / verify_looperwrt paths.

PKG_NAME:=ap-isolation
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/LuisMitaHL/openwrt-public-ap-isolation
PKG_SOURCE_DATE:=2026-10-08
PKG_SOURCE_VERSION:=a52cd9d6187b63f34b1b2cf87d1bf063ff1a5da8

PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/ap-isolation
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AP Client Isolation via nftables
  DEPENDS:=+nftables
  PKGARCH:=all
endef

define Package/ap-isolation/description
  Implements client isolation on public Wi-Fi access points using nftables.
  Reads UCI wireless config to determine which interfaces need isolation,
  and applies bridge-level nftables rules.

  Two tiers via the 'mode' option:
    filter  - filters ARP, broadcast and multicast between clients (default);
    gateway - default-drop gateway allowlist: clients may only exchange
              traffic with the configured main router.
endef

define Package/ap-isolation/conffiles
/etc/config/ap-isolation
endef

define Build/Compile
endef

define Package/ap-isolation/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/config/ap-isolation $(1)/etc/config/ap-isolation
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/ap-isolation $(1)/etc/init.d/ap-isolation
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/sbin/ap-isolation.sh $(1)/usr/sbin/ap-isolation.sh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/etc/hotplug.d/net/50-ap-isolation $(1)/etc/hotplug.d/net/50-ap-isolation
endef

$(eval $(call BuildPackage,ap-isolation))
