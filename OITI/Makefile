export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OITI

OITI_FILES = Tweak.xm
OITI_CFLAGS = -fobjc-arc
OITI_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += OITIPrefs
SUBPROJECTS += OITIRestoreGestalt
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	@cp OITIPrefs/Resources/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OITIPrefs.plist
