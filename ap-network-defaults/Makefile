include $(TOPDIR)/rules.mk

# Feed-native package (no vendor repo): the single uci-defaults script that
# turns every `ap` profile image into dumb-AP networking. Selected on every
# `ap` profile via the builder's configs/ap.config (aurora, mt7621, ipq40xx).
# Feed dir == package name, as required by the builder's
# stamp_looperwrt_versions / verify_looperwrt paths.

PKG_NAME:=ap-network-defaults
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/ap-network-defaults
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Dumb-AP network defaults for ap-profile images
  PKGARCH:=all
endef

define Package/ap-network-defaults/description
  First-boot (uci-defaults) conversion of an ap-profile image into dumb-AP
  networking: every physical port becomes a br-lan port and the wan
  interface is removed, lan switches to a DHCP client, the DHCPv4, DHCPv6
  and RA servers are turned off (dnsmasq keeps serving DNS) and antilag is
  disabled because no L3 uplink remains to shape. Apply-once, guarded by
  the looperwrt.ap_netdefaults marker like the branch 99_*-defaults.
endef

define Build/Compile
endef

define Package/ap-network-defaults/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/etc/uci-defaults/zz-ap-network-defaults $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,ap-network-defaults))
