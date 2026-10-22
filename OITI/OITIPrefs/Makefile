include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OITIPrefs

OITIPrefs_FILES = OITIBaseListController.m OITIRootListController.m OITIColorListController.m OITIScaleListController.m OITINotificationsListController.m OITIDownloadsListController.m OITIStartupListController.m
OITIPrefs_FRAMEWORKS = UIKit
OITIPrefs_INSTALL_PATH = /Library/PreferenceBundles

# The package version from ../control, used as a fallback for the version line on the main settings page.
OITI_BUILD_VERSION := $(shell sed -n 's/^Version: *//p' $(CURDIR)/../control | head -n 1)
OITIPrefs_CFLAGS = -fobjc-arc -DOITI_BUILD_VERSION=\"$(OITI_BUILD_VERSION)\"
OITIPrefs_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib

ifeq ($(findstring simulator,$(TARGET)),simulator)
OITIPrefs_LDFLAGS += -Wl,-undefined,dynamic_lookup
else
OITIPrefs_PRIVATE_FRAMEWORKS = Preferences
endif

include $(THEOS_MAKE_PATH)/bundle.mk
