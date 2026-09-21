################################################################################
#
# endpoint3-js
#
################################################################################

ENDPOINT3_JS_VERSION = 1.0
ENDPOINT3_JS_SITE = $(BR2_EXTERNAL_LAB_PATH)/package/endpoint3-js/src
ENDPOINT3_JS_SITE_METHOD = local

define ENDPOINT3_JS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -O2 -Wall -Wextra \
		-o $(@D)/endpoint3-js $(@D)/server.c
endef

define ENDPOINT3_JS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/endpoint3-js \
		$(TARGET_DIR)/usr/sbin/endpoint3
endef

define ENDPOINT3_JS_USERS
	endpoint3 -1 endpoint3 -1 * /var/lib/endpoint3 /bin/false - Endpoint_3_service
endef

$(eval $(generic-package))
