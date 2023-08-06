# If ORIG_COMPILER is 1, compile with QEMU_IRIX and the original compiler binary instead of IDO recomp
ORIG_COMPILER ?= 0
# If COMPARE is 1, compare to original binary (if present in root dir) after building
COMPARE ?= 1
# Cross-compiler toolchain prefix
CROSS := mips-linux-gnu-

TARGETS := pifrom.PAL pifrom.MPAL pifrom.NTSC ipl3.HW1 ipl3.6101 ipl3.6102_7101 ipl3.7102 ipl3.X103 ipl3.X105 ipl3.X106

ifeq ($(ORIG_COMPILER),1)
    # Find qemu_irix, either path set in an env var, somewhere in PATH, or a binary in the tools/ dir
    ifndef QEMU_IRIX
        QEMU_IRIX := $(shell which qemu-irix)
        ifeq (, $(QEMU_IRIX))
            $(error Please install qemu-irix package or set QEMU_IRIX env var to the full qemu-irix binary path)
        endif
    endif
    CC := $(QEMU_IRIX) -L tools/ido5.3_compiler tools/ido5.3_compiler/usr/bin/cc
else
    CC := tools/ido5.3_recomp/cc
endif

OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
LD      := $(CROSS)ld
STRIP   := $(CROSS)strip

BIN_FILES  := $(foreach f,$(TARGETS),build/$f.bin)

ASFLAGS := -Wab,-r4300_mul -non_shared -G 0 -verbose -fullwarn -Xcpluscomm -nostdinc -I include -mips2 -o32
OPTFLAGS := -O2

$(shell mkdir -p build)

.PHONY: all clean distclean setup $(TARGETS)
all: $(BIN_FILES)

setup:
	$(MAKE) -C tools

clean:
	$(RM) -rf build

distclean: clean
	$(MAKE) -C tools distclean

define MK_TARGET =
$(1): build/$(1).bin
endef
$(foreach p,$(TARGETS),$(eval $(call MK_TARGET,$(p))))

define SET_VARS = 
	ifneq ($(findstring pifrom,$(1)),)
		SOURCES := src/pifrom.s
		ADDRESS := 0xBFC00000
		DEFS := -DPIFROM_$(patsubst build/pifrom.%.bin,%,$(1))
	else
	ifneq ($(findstring ipl3,$(1)),)
		SOURCES := src/ipl3.s
		ADDRESS := 0xA4000040
		DEFS := -DIPL3_$(patsubst build/ipl3.%.bin,%,$(1))
	endif
	endif
endef

define COMPILE =
$(eval $(call SET_VARS,$(1)))

$(1): $(SOURCES)
	$(CC) $(ASFLAGS) $(OPTFLAGS) $(DEFS) -c $$^ -o $$(@:.bin=.o)
	@$(OBJDUMP) -drz $$(@:.bin=.o) > $$(@:.bin=.s)
	@$(STRIP) -N dummy_symbol_ $$(@:.bin=.o)
	$(LD) -T ipl.ld --defsym start=$(ADDRESS) $$(@:.bin=.o) -o $$(@:.bin=.elf)
	$(OBJCOPY) -O binary -j.text $$(@:.bin=.elf) $$@
ifeq ($(COMPARE),1)
	$$(if $$(wildcard $$(@F), $$(@F)), \
		cmp $$(@F) $$@ && \
		echo $$(@F:.bin=) OK \
	)
endif
endef

$(foreach p,$(BIN_FILES),$(eval $(call COMPILE,$(p))))
