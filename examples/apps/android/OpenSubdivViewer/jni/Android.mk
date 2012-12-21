LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE    := OpenSubdivjni
LOCAL_CFLAGS    := -Werror
LOCAL_SRC_FILES := OpenSubdiv.cpp
LOCAL_LDLIBS    := -llog -lEGL -lGLESv2
LOCAL_SHARED_LIBRARIES    := OpenSubdivOsdCPU OpenSubdivOsdGPU

include $(BUILD_SHARED_LIBRARY)

$(call import-module, OpenSubdiv)
