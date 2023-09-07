
# IDO

IDO_DIR   := ido5.3_recomp

IDO-5.3   := $(IDO_DIR)/cc
IDO_TARNAME := ido-5.3-recomp-linux.tar.gz
IDO_URL := https://github.com/decompals/ido-static-recomp/releases/latest/download/$(IDO_TARNAME)

# EGCS

EGCS_DIR := egcs

EGCS-AS := $(EGCS_DIR)/as
EGCS_BINUTILS_TARNAME := mips-binutils-egcs-2.9.5-linux.tar.gz
EGCS_BINUTILS_URL := https://github.com/decompals/mips-binutils-egcs-2.9.5/releases/latest/download/$(EGCS_BINUTILS_TARNAME)

EGCS-1.1.2 := $(EGCS_DIR)/gcc
EGCS_GCC_TARNAME := mips-gcc-egcs-2.91.66-linux.tar.gz
EGCS_GCC_URL := https://github.com/decompals/mips-gcc-egcs-2.91.66/releases/latest/download/$(EGCS_GCC_TARNAME)



.PHONY: all clean distclean

all: $(IDO-5.3) $(EGCS-AS) $(EGCS-1.1.2)

clean:

distclean: clean
	$(RM) -rf $(IDO_DIR) $(EGCS_DIR)



# IDO

$(IDO-5.3): | $(IDO_DIR)
	wget $(IDO_URL)
	tar xf $(IDO_TARNAME) -C $(IDO_DIR)
	$(RM) $(IDO_TARNAME)

$(IDO_DIR):
	mkdir -p $@

# EGCS

$(EGCS-AS): | $(EGCS_DIR)
	wget $(EGCS_BINUTILS_URL)
	tar xf $(EGCS_BINUTILS_TARNAME) -C $(EGCS_DIR)
	$(RM) $(EGCS_BINUTILS_TARNAME)

$(EGCS-1.1.2): | $(EGCS_DIR)
	wget $(EGCS_GCC_URL)
	tar xf $(EGCS_GCC_TARNAME) -C $(EGCS_DIR)
	$(RM) $(EGCS_GCC_TARNAME)

$(EGCS_DIR):
	mkdir -p $@
