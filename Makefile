CC ?= cc
ARM_CC ?= arm-linux-gnueabi-gcc
WARNINGS = -Wall -Wextra -Werror
ARM_FLAGS = -shared -fPIC -nostdlib -fno-stack-protector -marm -march=armv5te -Os
ARM_LINK = -Wl,--hash-style=both

.PHONY: test rtsp clean
test:
	mkdir -p build
	$(CC) $(WARNINGS) -std=c11 -g -fsanitize=address,undefined src/mcu_protocol.c tests/test_mcu_protocol.c -o build/test_mcu_protocol
	./build/test_mcu_protocol

rtsp:
	mkdir -p build
	$(ARM_CC) $(WARNINGS) $(ARM_FLAGS) $(ARM_LINK) -o build/pf_rtsp.so src/rtsp_hook.c

clean:
	rm -rf build
