export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OITS

OITS_FILES = Tweak.xm
OITS_CFLAGS = -fobjc-arc
OITS_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += OITSPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	@cp OITSPrefs/Resources/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OITSPrefs.plist
