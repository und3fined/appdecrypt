TARGET := iphone:clang:14.5:13.0
ARCHS = arm64
export ADDITIONAL_CFLAGS = -DTHEOS_LEAN_AND_MEAN -fobjc-arc

include $(THEOS)/makefiles/common.mk

TOOL_NAME = foulwrapper2

foulwrapper2_FILES = foulwrapper.m
foulwrapper2_CFLAGS = -fobjc-arc -Wno-unused-variable -Iinclude
foulwrapper2_CCFLAGS = $(foulwrapper2_CFLAGS)
foulwrapper2_CODESIGN_FLAGS = -Sentitlements.plist
foulwrapper2_FRAMEWORKS = Foundation MobileCoreServices
foulwrapper2_PRIVATE_FRAMEWORKS = MobileContainerManager

include $(THEOS_MAKE_PATH)/tool.mk

before-package::
	ls -lah $(THEOS_STAGING_DIR)/usr
	cp ../d3crypt $(THEOS_STAGING_DIR)/usr/bin/
