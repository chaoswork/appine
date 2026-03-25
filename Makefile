CC = clang

# 候选搜索路径（按优先级排列）
EMACS_HEADER_SEARCH_PATHS = \
    /Applications/Emacs.app/Contents/Resources/include \
    /usr/local/include

# 判断用户是否显式传入了 EMACS_INCLUDE_DIR
ifdef EMACS_INCLUDE_DIR
  # 用户传入了路径，验证头文件是否真实存在
  ifeq ($(wildcard $(EMACS_INCLUDE_DIR)/emacs-module.h),)
    $(error emacs-module.h not found in specified EMACS_INCLUDE_DIR="$(EMACS_INCLUDE_DIR)". \
Please make sure the path is correct. \
Usage example: make EMACS_INCLUDE_DIR=/Applications/Emacs.app/Contents/Resources/include)
  endif
else
  # 用户未传入，自动在候选路径中搜索
  EMACS_INCLUDE_DIR := $(firstword \
      $(foreach p,$(EMACS_HEADER_SEARCH_PATHS),\
          $(if $(wildcard $(p)/emacs-module.h),$(p),)))

  ifeq ($(EMACS_INCLUDE_DIR),)
    $(error emacs-module.h was not found in any of the default search paths: \
[$(EMACS_HEADER_SEARCH_PATHS)]. \
Please locate emacs-module.h manually and pass its directory via EMACS_INCLUDE_DIR. \
Usage example: make EMACS_INCLUDE_DIR=/path/to/your/emacs/include)
  endif
endif


CFLAGS  = -Wall -O2 -fPIC -Wextra -std=c11 -fobjc-arc -Wno-unused-parameter \
           -I"$(EMACS_INCLUDE_DIR)"
LDFLAGS = -dynamiclib \
           -framework Cocoa \
           -framework WebKit \
           -framework Quartz \
           -framework UniformTypeIdentifiers

TARGET = appine-module.dylib
SRCS   = module.c appine_core.m backend_web.m backend_pdf.m backend_quicklook.m

# 同时编译 Intel 和 Apple Silicon 架构
ARCH_FLAGS = -arch x86_64 -arch arm64

all: $(TARGET)

$(TARGET): $(SRCS)
	@echo "Using emacs-module.h from: $(EMACS_INCLUDE_DIR)"
	$(CC) $(CFLAGS) $(ARCH_FLAGS) $(LDFLAGS) -o $@ $(SRCS)

clean:
	rm -f $(TARGET)
