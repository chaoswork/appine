CC = clang

# 如果外部没有传入 EMACS_INCLUDE_DIR，默认搜索当前目录 (.)
EMACS_INCLUDE_DIR ?= .

# 将 -I 参数加入到编译选项中
CFLAGS = -Wall -O2 -fPIC -Wextra -std=c11 -fobjc-arc -Wno-unused-parameter -I"$(EMACS_INCLUDE_DIR)"

LDFLAGS = -dynamiclib -framework Cocoa -framework WebKit -framework Quartz -framework UniformTypeIdentifiers
TARGET = appine-module.dylib
SRCS = module.c appine_core.m backend_web.m backend_pdf.m backend_quicklook.m

# 同时编译 Intel 和 Apple Silicon 架构
ARCH_FLAGS = -arch x86_64 -arch arm64

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) $(LDFLAGS) -o $@ $(SRCS)

clean:
	rm -f $(TARGET)
