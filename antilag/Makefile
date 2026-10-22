include $(TOPDIR)/rules.mk

#
# antilag - Adaptive CAKE qdisc bandwidth controller (daemon).
#
# git pin of LuisMitaHL/laotrared-openwrt-antilag (the dev repo), following
# the dhcpoptinj/ap-isolation pattern: this feed carries the packaging glue
# only; the daemon sources (src/) and the rootfs files (root/) come from the
# pinned commit below. Rebase = bump PKG_SOURCE_VERSION (+ PKG_SOURCE_DATE).
# PKG_VERSION is the static base the builder HEAD-stamps and must stay
# separate from the pin. The LuCI app is a separate package
# (luci-app-antilag) pinned to the same repo.
#

PKG_NAME    := antilag
PKG_VERSION := 1.0.0
PKG_RELEASE := 2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/LuisMitaHL/laotrared-openwrt-antilag
PKG_SOURCE_DATE:=2026-10-21
PKG_SOURCE_VERSION:=e12df9ce05a3304567ecdd52e849d2700479e104

PKG_MIRROR_HASH:=skip

PKG_LICENSE         := GPL-2.0-or-later
PKG_MAINTAINER      := kamikaonashi
PKG_BUILD_PARALLEL  := 1

include $(INCLUDE_DIR)/package.mk

define Package/antilag
  SECTION  := net
  CATEGORY := Network
  TITLE    := Antilag
  DEPENDS  := +libubox +libuci +kmod-ifb +kmod-sched-cake \
              +kmod-sched-core
endef

define Package/antilag/description
  Adaptive CAKE qdisc bandwidth controller for OpenWrt.
  Standalone - no sqm-scripts required.

  Supports ICMP Timestamp (type 13) for true per-direction OWD measurement.
  Manages the full IFB + CAKE plumbing lifecycle via netlink.

  Dynamic instances adapt the shaper rate from live OWD measurements.
  Static instances apply a fixed target download/upload rate with no
  reflectors or live changes (the sqm-scripts model), re-applied by an
  iface hotplug hook when the WAN interface comes back up.

  Web UI is provided separately by luci-app-antilag.
endef

define Package/antilag/conffiles
/etc/config/antilag
endef

define Package/antilag/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/antilag enable
/etc/init.d/antilag start
exit 0
endef

define Package/antilag/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/antilag stop
/etc/init.d/antilag disable
exit 0
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src \
		-f Makefile.local \
		--no-print-directory \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -O2 -pipe -I$(STAGING_DIR)/usr/include" \
		LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib -lubox -luci"
	$(TARGET_CROSS)strip --strip-unneeded \
		$(PKG_BUILD_DIR)/src/antilag
endef

define Package/antilag/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/antilag $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/antilag \
		$(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/root/etc/config/antilag \
		$(1)/etc/config/

	# iface hotplug hook: re-applies static instances on WAN up/down
	# (same model as sqm-scripts).
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) \
		$(PKG_BUILD_DIR)/root/etc/hotplug.d/iface/25-antilag \
		$(1)/etc/hotplug.d/iface/
endef

$(eval $(call BuildPackage,antilag))
