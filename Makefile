include $(TOPDIR)/rules.mk

PKG_NAME:=red-merle
PKG_VERSION:=2.19.1
PKG_RELEASE:=$(AUTORELEASE)

PKG_MAINTAINER:=Franck FERMAN <franckferman@users.noreply.github.com>
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE LICENSE.md

include $(INCLUDE_DIR)/package.mk

define Package/red-merle
	SECTION:=utils
	CATEGORY:=Utilities
	EXTRA_DEPENDS:=luci-base, gl-sdk4-mcu, coreutils-shred, python3-pyserial
	TITLE:=Anonymity Enhancements for GL-E750 Mudi
endef

define Package/red-merle/description
	The red-merle package enhances anonymity and reduces forensic traceability of the GL-E750 Mudi 4G mobile wi-fi router
endef

define Package/red-merle/conffiles
/etc/config/red-merle
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/red-merle/install
	$(CP) ./files/* $(1)/
	$(INSTALL_BIN) ./files/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/gl-switch.d/* $(1)/etc/gl-switch.d/
	$(INSTALL_BIN) ./files/usr/bin/* $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/libexec/red-merle $(1)/usr/libexec/red-merle
	$(INSTALL_BIN) ./files/lib/red-merle/imei_generate.py  $(1)/lib/red-merle/imei_generate.py
	$(INSTALL_BIN) ./files/usr/share/red-merle/patch-branding.py $(1)/usr/share/red-merle/patch-branding.py
	$(INSTALL_BIN) ./files/www/cgi-bin/redmerle-api $(1)/www/cgi-bin/redmerle-api
	rm -rf $(1)/usr/share/red-merle/__pycache__ $(1)/lib/red-merle/__pycache__
endef

define Package/red-merle/preinst
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] && exit 0	# if run within buildroot exit
	
	ABORT_GLVERSION () {
		echo
		if [ -f "/tmp/sysinfo/model" ] && [ -f "/etc/glversion" ]; then
			echo "You have a `cat /tmp/sysinfo/model`, running firmware version `cat /etc/glversion`."
		fi
		echo "red-merle has only been tested with GL-E750 Mudi Versions up to 4.3.26"
		echo "The device or firmware version you are using have not been verified to work with red-merle."
		echo -n "Would you like to continue on your own risk? (y/N): "
		read answer
		case $$answer in
				y*) answer=0;;
				y*) answer=0;;
				*) answer=1;;
		esac
		if [ "$$answer" -eq 0 ]; then
			exit 0
		else
			exit 1
		fi
	}

	if grep -q "GL.iNet GL-E750" /proc/cpuinfo; then
	    GL_VERSION=$$(cat /etc/glversion)
	    case $$GL_VERSION in
		4.3.26)
		    echo Version $$GL_VERSION is supported
		    exit 0
		    ;;
		4.*)
	            echo Version $$GL_VERSION is *probably* supported
	            ABORT_GLVERSION
	            ;;
	        *)
	            echo Unknown version $$GL_VERSION
	            ABORT_GLVERSION
	            ;;
        esac
        CHECK_MCUVERSION
	else
		ABORT_GLVERSION
	fi

    # Our volatile-mac service gets started during the installation
    # but it modifies the client database held by the gl_clients process.
    # So we stop that process now, have the database put onto volatile storage
    # and start the service after installation
    /etc/init.d/gl_clients stop
endef

define Package/red-merle/postinst
	#!/bin/sh
	uci set switch-button.@main[0].func='sim'
	uci commit switch-button

	/etc/init.d/gl_clients start

	echo {\"msg\": \"Successfully installed Red Merle\"} > /dev/ttyS0

	# LuCI caches its menu tree and rpcd reads ACL files only at start, so a
	# freshly installed page stays invisible until something invalidates them.
	rm -f /tmp/luci-indexcache* 2>/dev/null
	rm -rf /tmp/luci-modulecache 2>/dev/null
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1

	# Every GL panel / SSH banner version string comes from this one script, so
	# a reinstall refreshes them all instead of leaving stale ones behind.
	if [ -f /usr/share/red-merle/patch-branding.py ]; then \
		python3 /usr/share/red-merle/patch-branding.py '$(PKG_VERSION)' || true; \
	fi

	# Activate the /redmerle/ nginx drop-in. If nginx rejects our file, take it
	# back out: a bad config here would kill the whole panel at the next restart.
	if command -v nginx >/dev/null 2>&1; then \
		if ! nginx -t >/dev/null 2>&1; then \
			mv /etc/nginx/gl-conf.d/red-merle.conf /tmp/red-merle.conf.rejected 2>/dev/null; \
			if nginx -t >/dev/null 2>&1; then \
				echo "red-merle: nginx rejected the /redmerle/ drop-in, left it out"; \
			else \
				mv /tmp/red-merle.conf.rejected /etc/nginx/gl-conf.d/red-merle.conf 2>/dev/null; \
			fi; \
		fi; \
		if nginx -t >/dev/null 2>&1; then \
			if [ -f /var/run/nginx.pid ]; then \
				kill -HUP "$$(cat /var/run/nginx.pid)" 2>/dev/null || /etc/init.d/nginx restart >/dev/null 2>&1; \
			else \
				/etc/init.d/nginx restart >/dev/null 2>&1; \
			fi; \
		fi; \
	fi
endef

define Package/red-merle/postrm
	#!/bin/sh
	uci set switch-button.@main[0].func='tor'
	# opkg parks a copy of the shipped config next to the live one when they
	# differ and owns neither: remove it or it outlives the package.
	rm -f /etc/config/red-merle-opkg
	# our nginx drop-in went away with the package: reload so it stops serving
	if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1 && [ -f /var/run/nginx.pid ]; then \
		kill -HUP "$$(cat /var/run/nginx.pid)" 2>/dev/null || true; \
	fi
	exit 0
endef
$(eval $(call BuildPackage,$(PKG_NAME)))
