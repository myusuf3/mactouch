CC ?= cc
CFLAGS ?= -O2 -std=gnu11 -Wall -Wextra -Werror
BUILD := build

all: $(BUILD)/pam_mactouch.so

$(BUILD):
	mkdir -p $@

$(BUILD)/pam_mactouch.so: pam_mactouch.c approve.c approve.h | $(BUILD)
	$(CC) $(CFLAGS) -bundle -o $@ pam_mactouch.c approve.c -lpam

$(BUILD)/test_approve: tests/test_approve.c approve.c approve.h ../firmware/main/vectors.h | $(BUILD)
	$(CC) $(CFLAGS) -I. -I../firmware/main -o $@ tests/test_approve.c approve.c

test: $(BUILD)/test_approve
	$(BUILD)/test_approve

clean:
	rm -rf $(BUILD)

.PHONY: all test clean
