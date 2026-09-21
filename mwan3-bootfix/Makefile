include $(TOPDIR)/rules.mk

PKG_NAME:=mwan3-bootfix
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_MAINTAINER:=Luis Mita <luis@luismita.com>
PKG_LICENSE:=BSD-3-Clause

include $(INCLUDE_DIR)/package.mk

define Package/mwan3-bootfix
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=One-shot delayed mwan3 restart after boot
  DEPENDS:=+mwan3
endef

define Package/mwan3-bootfix/description
  mwan3 can apply itself incorrectly at boot (upstream bug). This package
  schedules a single `mwan3 restart` ~3 minutes after boot (UCI-tunable,
  default 180s, enabled by default). It skips when disabled or when mwan3
  is not installed/configured. Intended for the core profile only.
endef

define Package/mwan3-bootfix/conffiles
/etc/config/mwan3-bootfix
endef

define Build/Compile
endef

define Package/mwan3-bootfix/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/etc/rc.d
	$(INSTALL_BIN) ./files/mwan3-bootfix.sh $(1)/usr/sbin/mwan3-bootfix
	$(INSTALL_BIN) ./files/mwan3-bootfix.init $(1)/etc/init.d/mwan3-bootfix
	$(INSTALL_CONF) ./files/mwan3-bootfix.config $(1)/etc/config/mwan3-bootfix
	$(LN) ../init.d/mwan3-bootfix $(1)/etc/rc.d/S99mwan3-bootfix
endef

$(eval $(call BuildPackage,mwan3-bootfix))
