export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OITInspector

OITInspector_FILES = Tweak.m
OITInspector_CFLAGS = -fobjc-arc
OITInspector_LDFLAGS += $(THEOS)/lib/iphone/rootless/OITCore.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += OITDumpTrigger
include $(THEOS_MAKE_PATH)/aggregate.mk
