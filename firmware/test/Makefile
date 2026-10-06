CC ?= cc
CFLAGS ?= -O2 -std=gnu11 -Wall -Wextra -Werror
BUILD := build

# Firmware modules with no hardware dependencies, built and tested on the host.

$(BUILD):
	mkdir -p $@

$(BUILD)/test_unlock: test_unlock.c ../main/unlock.c ../main/unlock.h ../main/typing.h | $(BUILD)
	$(CC) $(CFLAGS) -I../main -o $@ test_unlock.c ../main/unlock.c

$(BUILD)/test_typing: test_typing.c ../main/typing.c ../main/typing.h | $(BUILD)
	$(CC) $(CFLAGS) -I../main -o $@ test_typing.c ../main/typing.c

test: $(BUILD)/test_unlock $(BUILD)/test_typing
	$(BUILD)/test_unlock
	$(BUILD)/test_typing

clean:
	rm -rf $(BUILD)

.PHONY: test clean
