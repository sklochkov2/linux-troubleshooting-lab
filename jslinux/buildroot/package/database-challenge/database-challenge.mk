################################################################################
#
# database-challenge
#
################################################################################

DATABASE_CHALLENGE_VERSION = 1.0
DATABASE_CHALLENGE_SITE = $(BR2_EXTERNAL_LAB_PATH)/package/database-challenge/src
DATABASE_CHALLENGE_SITE_METHOD = local

define DATABASE_CHALLENGE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -O2 -Wall -Wextra \
		-I$(BR2_EXTERNAL_LAB_PATH)/package/lab-endpoints/src \
		-o $(@D)/database1 $(@D)/database1.c
endef

define DATABASE_CHALLENGE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/database1 \
		$(TARGET_DIR)/usr/sbin/database1
endef

define DATABASE_CHALLENGE_USERS
	database1 -1 database1 -1 * /var/empty /bin/false - Database_challenge_service
endef

$(eval $(generic-package))
