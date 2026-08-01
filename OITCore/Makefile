export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:16.5:16.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = OITCore

OITCore_FILES = $(wildcard Sources/*.m)
OITCore_CFLAGS = -fobjc-arc -Iinclude -Iinclude/OITCore
OITCore_FRAMEWORKS = Foundation UIKit
OITCore_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk

after-stage::
	@mkdir -p $(THEOS)/include/OITCore
	@cp -f include/OITCore/*.h $(THEOS)/include/OITCore/
