
IDO_TARNAME := ido-5.3-recomp-linux.tar.gz
IDO_URL := https://github.com/decompals/ido-static-recomp/releases/latest/download/$(IDO_TARNAME)

# IDO
IDO_DIR   := ido5.3_recomp
IDO-5.3   := $(IDO_DIR)/cc

.PHONY: all clean distclean
all: $(IDO-5.3)

clean:

distclean: clean
	$(RM) -rf $(IDO_DIR)

# IDO

$(IDO-5.3): | $(IDO_DIR)
	wget $(IDO_URL)
	tar xf $(IDO_TARNAME) -C $(IDO_DIR)
	$(RM) $(IDO_TARNAME)

$(IDO_DIR):
	mkdir -p $@
