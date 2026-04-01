CC = clang

# ---------------------------------------------------------------------------
# 路径配置
# ---------------------------------------------------------------------------
SRC_CORE_DIR    = src/core
SRC_BACKEND_DIR = src/backends

# ---------------------------------------------------------------------------
# EMACS_INCLUDE_DIR setup
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# 编译选项
# ---------------------------------------------------------------------------
CFLAGS = -Wall -O2 -fPIC -Wextra -std=c11 -fobjc-arc -Wno-unused-parameter \
         -I"$(EMACS_INCLUDE_DIR)" \
         -I"$(SRC_CORE_DIR)" \
         -I"$(SRC_BACKEND_DIR)"

LDFLAGS = -dynamiclib \
          -framework Cocoa \
          -framework WebKit \
          -framework Quartz \
          -framework UniformTypeIdentifiers

TARGET = appine-module.dylib

# 同时编译 Intel 和 Apple Silicon 架构
ARCH_FLAGS = -arch x86_64 -arch arm64

# ---------------------------------------------------------------------------
# 源文件（按新目录结构）
# ---------------------------------------------------------------------------
SRCS = $(SRC_CORE_DIR)/module.c \
       $(SRC_CORE_DIR)/appine_core.m \
       $(SRC_BACKEND_DIR)/backend_web.m \
       $(SRC_BACKEND_DIR)/backend_pdf.m \
       $(SRC_BACKEND_DIR)/backend_quicklook.m

# ---------------------------------------------------------------------------
# 构建规则
# ---------------------------------------------------------------------------
.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) $(LDFLAGS) -o $@ $(SRCS)

clean:
	rm -rf $(TARGET)
