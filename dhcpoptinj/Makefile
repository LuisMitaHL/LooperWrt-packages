#
# dhcpoptinj - DHCP option injector daemon (nftables queue, procd).
#
# Vendored from the (now deprecated) LuisMitaHL/dhcpoptinj-openwrt recipe;
# this feed is the source of truth. Source comes from the LuisMitaHL fork of
# misje/dhcpoptinj at the pinned commit below (the fork adds the interface
# exclusion, the hex-buffer fix and fork docs on top of upstream 0.5.3).
# Rebase = bump PKG_SOURCE_VERSION (+ PKG_MIRROR_HASH); PKG_VERSION is the
# static base the builder HEAD-stamps and must stay separate from the pin.
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=dhcpoptinj
PKG_VERSION:=0.5.4
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/LuisMitaHL/dhcpoptinj
PKG_SOURCE_DATE:=2026-09-02
PKG_SOURCE_VERSION:=305001c1894b68417c500f70d5c404fb6ca2ea23

PKG_MIRROR_HASH:=skip

PKG_INSTALL:=1

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-3.0-or-later

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/dhcpoptinj
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=+libnetfilter-queue +nftables +kmod-nft-queue
  TITLE:=Inject DHCP options into DHCP requests
  URL:=https://github.com/misje/dhcpoptinj
endef

define Package/dhcpoptinj/description
 Inject DHCP options into DHCP requests
endef

define Package/dhcpoptinj/conffiles
/etc/config/dhcpoptinj
endef

define Package/dhcpoptinj/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/dhcpoptinj $(1)/usr/bin/
	$(INSTALL_BIN) ./files/dhcpoptinj-enc82.sh $(1)/usr/bin/dhcpoptinj-enc82
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/$(PKG_NAME).config $(1)/etc/config/$(PKG_NAME)
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/$(PKG_NAME).init $(1)/etc/init.d/$(PKG_NAME)
endef

$(eval $(call BuildPackage,dhcpoptinj))
