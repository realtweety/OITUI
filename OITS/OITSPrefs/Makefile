include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OITSPrefs

OITSPrefs_FILES = OITSRootListController.m
OITSPrefs_FRAMEWORKS = UIKit
OITSPrefs_INSTALL_PATH = /Library/PreferenceBundles
OITSPrefs_CFLAGS = -fobjc-arc
OITSPrefs_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib
ifeq ($(findstring simulator,$(TARGET)),simulator)
OITSPrefs_LDFLAGS += -Wl,-undefined,dynamic_lookup
else
OITSPrefs_PRIVATE_FRAMEWORKS = Preferences
endif

include $(THEOS_MAKE_PATH)/bundle.mk
