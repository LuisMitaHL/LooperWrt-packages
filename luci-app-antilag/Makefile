include $(TOPDIR)/rules.mk

PKG_NAME    := luci-app-antilag
PKG_VERSION := 1.0.0
PKG_RELEASE := 1

PKG_LICENSE      := GPL-2.0-or-later
PKG_MAINTAINER   := kamikaonashi

# po2lmo is shipped by the luci-base host build; it compiles the po/
# catalogs below into LuCI .lmo files at package install time.
PKG_BUILD_DEPENDS += luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-antilag
  SECTION  := luci
  CATEGORY := LuCI
  SUBMENU  := 3. Applications
  TITLE    := Antilag web interface
  DEPENDS  := +antilag +luci-base +rpcd
endef

define Package/luci-app-antilag/description
  LuCI web interface for antilag: Services page, Overview status widget
  and per-tin CAKE statistics. Requires the antilag daemon package.
endef

define Package/luci-app-antilag/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/rpcd reload
exit 0
endef

define Build/Compile
endef

define Package/luci-app-antilag/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) \
		./files/usr/share/luci/menu.d/luci-app-antilag.json \
		$(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) \
		./files/usr/share/rpcd/acl.d/luci-app-antilag.json \
		$(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/antilag
	$(INSTALL_DATA) \
		./files/www/luci-static/resources/antilag/status.js \
		$(1)/www/luci-static/resources/antilag/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) \
		./files/www/luci-static/resources/view/antilag.js \
		$(1)/www/luci-static/resources/view/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status/include
	$(INSTALL_DATA) \
		./files/www/luci-static/resources/view/status/include/75_antilag.js \
		$(1)/www/luci-static/resources/view/status/include/

	# LuCI translations: compile po/<lang>/<domain>.po into the .lmo
	# catalogs the web UI loads from /usr/lib/lua/luci/i18n.
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(STAGING_DIR_HOSTPKG)/bin/po2lmo \
		./po/es/antilag.po \
		$(1)/usr/lib/lua/luci/i18n/antilag.es.lmo
endef

$(eval $(call BuildPackage,luci-app-antilag))
