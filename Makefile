
TARGETS := pifrom.PAL pifrom.NTSC ipl3.6101 ipl3.6102_7101 ipl3.7102 ipl3.X103 ipl3.X105 ipl3.X106
COMPARE ?= 1

# Find qemu_irix, either path set in an env var, somewhere in PATH, or a binary in the tools/ dir
QEMU_IRIX ?= $(shell which qemu-irix)
ifeq (, $(QEMU_IRIX))
  QEMU_IRIX := tools/qemu-irix
  ifeq (, $(wildcard $(QEMU_IRIX)))
	$(error Qemu-irix not found. Please either install qemu-irix package, set a QEMU_IRIX env var to the full path, or place the qemu-irix binary in the tools dir)
  endif
endif

CC = $(QEMU_IRIX) -L tools/ido5.3_compiler tools/ido5.3_compiler/usr/bin/cc

CROSS := mips-linux-gnu-

OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
LD      := $(CROSS)ld
STRIP   := $(CROSS)strip

BIN_FILES  := $(foreach f,$(TARGETS),build/$f.bin)

ASFLAGS := -Wab,-r4300_mul -non_shared -G 0 -verbose -fullwarn -Xcpluscomm -nostdinc -I include -mips2 -o32
OPTFLAGS := -O2

$(shell mkdir -p build)

.PHONY: all clean $(TARGETS)
all: $(BIN_FILES)

clean:
	$(RM) -rf build

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
