# Build the reference runtime for one profile:
#   make PROFILE=../profiles/reference-x.json
# Output: reference/build/runtime/<profile name>/{libzkvm_ref.a,link.ld}

REF := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
ROOT := $(abspath $(REF)/..)
PROFILE ?= $(REF)/profiles/reference-x.json
NAME := $(shell python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' $(PROFILE))
OUT := $(REF)/build/runtime/$(NAME)

CC := riscv64-unknown-elf-gcc
AR := riscv64-unknown-elf-ar
CFLAGS := -march=rv64im_zicclsm -mabi=lp64 -mcmodel=medany -O2 -ffreestanding -fno-builtin \
          -fno-jump-tables -nostdlib -I $(ROOT)/standards/io-interface

OBJS := $(OUT)/start.o $(OUT)/zkvm_ref.o $(OUT)/memops.o

all: $(OUT)/libzkvm_ref.a $(OUT)/link.ld

$(OUT)/%.o: $(REF)/runtime/%.S | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/%.o: $(REF)/runtime/%.c | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/libzkvm_ref.a: $(OBJS)
	rm -f $@
	$(AR) rcs $@ $^

$(OUT)/link.ld: $(REF)/runtime/link.ld.in $(REF)/runtime/gen-ld.py $(PROFILE) | $(OUT)
	python3 $(REF)/runtime/gen-ld.py $(PROFILE) > $@

$(OUT):
	mkdir -p $@

.PHONY: all
