# X protocol C Proto

XCB_PROTO_VERSION := 1.12
XCB_PROTO_URL := https://www.x.org/archive/individual/xcb/xcb-proto-$(XCB_PROTO_VERSION).tar.bz2

ifeq ($(call need_pkg,"xcb-proto"),)
PKGS_FOUND += xcb-proto
endif

$(TARBALLS)/xcb-proto-$(XCB_PROTO_VERSION).tar.bz2:
	$(call download_pkg,$(XCB_PROTO_URL),xcp-proto)

.sum-xcb-proto: xcb-proto-$(XCB_PROTO_VERSION).tar.bz2

xcb-proto: xcb-proto-$(XCB_PROTO_VERSION).tar.bz2 .sum-xcb-proto
	$(UNPACK)
	# XCB 1.12's generators predate Python 3.12.
	sed -i 's/from fractions import gcd/from math import gcd/' $(UNPACK_DIR)/xcbgen/align.py
	expand -t 8 $(UNPACK_DIR)/xcbgen/align.py > $(UNPACK_DIR)/xcbgen/align.py.tmp && mv $(UNPACK_DIR)/xcbgen/align.py.tmp $(UNPACK_DIR)/xcbgen/align.py
	sed -E -i '/^[[:space:]]*print \(/! s/^([[:space:]]*)print (.*)$$/\1print(\2)/' $(UNPACK_DIR)/xcbgen/xtypes.py
	$(MOVE)

.xcb-proto: xcb-proto
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install PYTHON=true
	touch $@
