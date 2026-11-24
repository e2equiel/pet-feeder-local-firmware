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
	$(CC) $(WARNINGS) -std=c11 -g -fsanitize=address,undefined src/json.c tests/test_json.c -o build/test_json
	./build/test_json
	$(CC) $(WARNINGS) -std=c11 -g -fsanitize=address,undefined src/journal.c tests/test_journal.c -o build/test_journal
	./build/test_journal

rtsp:
	mkdir -p build
	$(ARM_CC) $(WARNINGS) $(ARM_FLAGS) $(ARM_LINK) -o build/pf_local.so src/rtsp_hook.c src/local_api.c src/uart_hook.c src/mcu_protocol.c src/json.c src/journal.c -lgcc

clean:
	rm -rf build
