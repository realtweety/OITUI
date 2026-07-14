include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OITIPrefs

OITIPrefs_FILES = OITIRootListController.m OITIColorListController.m OITIScaleListController.m OITINotificationsListController.m
OITIPrefs_FRAMEWORKS = UIKit
OITIPrefs_INSTALL_PATH = /Library/PreferenceBundles
OITIPrefs_CFLAGS = -fobjc-arc
OITIPrefs_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib
ifeq ($(findstring simulator,$(TARGET)),simulator)
OITIPrefs_LDFLAGS += -Wl,-undefined,dynamic_lookup
else
OITIPrefs_PRIVATE_FRAMEWORKS = Preferences
endif

include $(THEOS_MAKE_PATH)/bundle.mk
