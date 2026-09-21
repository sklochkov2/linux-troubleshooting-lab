################################################################################
#
# lab-endpoints
#
################################################################################

LAB_ENDPOINTS_VERSION = 1.0
LAB_ENDPOINTS_SITE = $(BR2_EXTERNAL_LAB_PATH)/package/lab-endpoints/src
LAB_ENDPOINTS_SITE_METHOD = local

define LAB_ENDPOINTS_BUILD_CMDS
	for endpoint in endpoint1 endpoint2 endpoint4; do \
		$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -O2 -Wall -Wextra \
			-I$(@D) -o $(@D)/$${endpoint} $(@D)/$${endpoint}.c || exit 1; \
	done
endef

define LAB_ENDPOINTS_INSTALL_TARGET_CMDS
	for endpoint in endpoint1 endpoint2 endpoint4; do \
		$(INSTALL) -D -m 0755 $(@D)/$${endpoint} \
			$(TARGET_DIR)/usr/sbin/$${endpoint} || exit 1; \
	done
endef

define LAB_ENDPOINTS_USERS
	endpoint1 -1 endpoint1 -1 * /var/empty /bin/false - Endpoint_1_service
	endpoint2 -1 endpoint2 -1 * /var/log/endpoint2 /bin/false - Endpoint_2_service
	endpoint4 -1 endpoint4 -1 * /var/lib/endpoint4 /bin/false - Endpoint_4_service
endef

$(eval $(generic-package))
