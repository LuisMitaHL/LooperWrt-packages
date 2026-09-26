include $(TOPDIR)/rules.mk

# Feed-native package (no vendor repo): pins tailscaled's GOMEMLIMIT heap
# ceiling to 40MiB on RAM-tight profiles (the init default is 90MiB, see
# tailscale/files/tailscale.init). Selected ONLY by the builder's
# configs/core_lite.config -- that fragment is the decision point; the
# 40MiB value lives in the single uci-defaults below (spec-006 style:
# one source, builder assertion verify_lowmem checks both ends).
# Feed dir == package name, as required by the builder's
# stamp_looperwrt_versions / verify_looperwrt paths.

PKG_NAME:=tailscale-lowmem
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/tailscale-lowmem
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=40MiB GOMEMLIMIT ceiling for tailscale on RAM-tight profiles
  DEPENDS:=+tailscale
  PKGARCH:=all
endef

define Package/tailscale-lowmem/description
  One-shot uci-defaults that pins tailscaled's GOMEMLIMIT to 40MiB
  (init fallback is 90MiB). Applied only when the option is unset or
  still the stock 90MiB default, so manual overrides survive re-flashes.
  The builder selects it on the core_lite profile; core images keep 90MiB.
endef

define Build/Compile
endef

define Package/tailscale-lowmem/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/60-tailscale-lowmem $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,tailscale-lowmem))
