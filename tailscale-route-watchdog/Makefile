include $(TOPDIR)/rules.mk

PKG_NAME:=tailscale-route-watchdog
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=BSD-3-Clause

include $(INCLUDE_DIR)/package.mk

define Package/tailscale-route-watchdog
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Self-healing watchdog for Tailscale policy routing
  DEPENDS:= \
    +tailscale \
    +ucode \
    +ucode-mod-rtnl \
    +ucode-mod-fs \
    +ucode-mod-uci
endef

define Package/tailscale-route-watchdog/description
  Compares Tailscale's own view (tailscale status --json: peer addresses,
  primary subnet routes, exit node selection) against the kernel policy
  rules and routing table (default 52), and restores them when
  netifd/mwan3 churn leaves tailscaled with wiped routes it never re-applies.
  Heals via `tailscale debug force-netmap-update`, never by blindly restoring
  cached routes, so control-plane deletions are never fought. Runs one-shot
  cycles under a supervisor loop with a forkless snapshot fast path for
  CPU-limited routers. Designed for mwan3 setups per
  dl12345/mwan3-tailscale-setup.
endef

define Package/tailscale-route-watchdog/conffiles
/etc/config/tswatchdog
endef

define Build/Compile
endef

define Package/tailscale-route-watchdog/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) ./files/ts-watchdog.sh $(1)/usr/bin/ts-watchdog
	$(INSTALL_BIN) ./files/ts-watchdog.uc $(1)/usr/bin/ts-watchdog-cycle.uc
	$(INSTALL_BIN) ./files/tswatchdog.init $(1)/etc/init.d/tswatchdog
	$(INSTALL_CONF) ./files/tswatchdog.config $(1)/etc/config/tswatchdog
endef

$(eval $(call BuildPackage,tailscale-route-watchdog))
