include $(TOPDIR)/rules.mk

# Feed-native package (no vendor repo): Pasankalla defaults for the Cudy
# TR3000 / TR1200 mobile routers. Selected only on the pasankalla and
# pasankalla_lite profiles via the builder's configs/pasankalla.config.
#
# It owns two pieces of behaviour that the stock image does not have:
#   * a second, OWE-only guest AP ("Pasankalla gratis") on the built-in
#     radios, active only while the slider (BTN_0, EV_SW) is on; and
#   * a small uplink/LED state machine: ethernet WAN -> white:status solid,
#     travelmate on the built-in 5 GHz radio -> white slow blink, travelmate
#     on a USB WiFi radio -> white fast blink, no internet -> white off and
#     red:power slow blink.
# The state machine is event driven (hotplug button/iface/ieee80211) with a
# low-frequency 30 s poll as a safety net, and uses the kernel LED timer
# trigger instead of a blinking daemon so the MT7628 stays idle.

PKG_NAME:=pasankalla
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/pasankalla
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Wireless
  TITLE:=Pasankalla mobile-router guest AP and uplink/LED defaults
  DEPENDS:=+travelmate +jsonfilter +wpad-mbedtls +kmod-gpio-button-hotplug
endef

define Package/pasankalla/description
  Pasankalla defaults for the Cudy TR3000 and TR1200 mobile routers.

  Adds an OWE-only guest AP with SSID "Pasankalla gratis" on the built-in
  2.4/5 GHz radios, enabled only while the case slider (BTN_0) is on. The
  guest network uses a dedicated bridge/subnet (100.102.13.37/16 by default),
  lives in the lan firewall zone like the original Pasankalla setup, and is
  disabled on the 5 GHz radio while travelmate uses that same radio as its
  wwan uplink.

  Also runs a four-state uplink watchdog: ethernet WAN (white:status solid),
  travelmate on the built-in 5 GHz radio (white slow blink), travelmate on a
  hot-plugged USB WiFi radio (white fast blink), and no internet at all
  (white off, red:power slow blink). Travelmate uplinks are moved between
  the built-in and USB radios automatically, and the LEDs use kernel timer
  triggers so no userspace process has to blink them.
endef

define Package/pasankalla/conffiles
/etc/config/pasankalla
endef

# uci-defaults run from default_postinst, but the new lanclientes/trm_wwan
# netifd interfaces and the firewall/DHCP entries only appear after their
# services reload. On a live install or upgrade (IPKG_INSTROOT empty) do
# that and restart the daemon so it starts from the live interfaces;
# during image build the init scripts/netifd start in the normal order and
# this branch is skipped.
define Package/pasankalla/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/network reload
# The guest network may have moved from a VLAN device to br-guest; reattach
# hostapd to the new bridge before the state machine re-enables the BSSes.
[ -x /sbin/wifi ] && /sbin/wifi reload
[ -x /etc/init.d/firewall ] && /etc/init.d/firewall reload
[ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq reload
/etc/init.d/pasankalla restart
exit 0
endef

define Build/Compile
endef

define Package/pasankalla/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/pasankalla $(1)/etc/config/pasankalla

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/pasankalla $(1)/etc/init.d/pasankalla

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/pasankalla $(1)/usr/sbin/pasankalla

	$(INSTALL_DIR) $(1)/etc/hotplug.d/button $(1)/etc/hotplug.d/iface $(1)/etc/hotplug.d/ieee80211
	$(INSTALL_BIN) ./files/etc/hotplug.d/button/20-pasankalla $(1)/etc/hotplug.d/button/20-pasankalla
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/90-pasankalla $(1)/etc/hotplug.d/iface/90-pasankalla
	$(INSTALL_BIN) ./files/etc/hotplug.d/ieee80211/20-pasankalla $(1)/etc/hotplug.d/ieee80211/20-pasankalla

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/zz-pasankalla $(1)/etc/uci-defaults/zz-pasankalla
endef

$(eval $(call BuildPackage,pasankalla))
