#
# Copyright (C) 2016 Wind River Systems, Inc.
#

LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

RDEPENDS:${PN} = "bash"

SRC_URI += "git://github.com/lwfinger/rtl8723bs_bt.git \
	   "
SRCREV = "07cda47e386f7bece859323f55b5a6a0df51c63b"	
S = "${WORKDIR}/git"

do_compile(){
	$CC ${CFLAGS} -o rtk_hciattach hciattach.c hciattach_rtk.c ${LDFLAGS}
}

do_install(){
	install -d ${D}${nonarch_base_libdir}/firmware/rtl_bt
	install -d ${D}/opt/rtl8723bs_bt
	install -m 0755 rtlbt_* ${D}${nonarch_base_libdir}/firmware/rtl_bt
	install -m 0755 rtk_hciattach ${D}/opt/rtl8723bs_bt
	install -m 0755 start_bt.sh ${D}/opt/rtl8723bs_bt
}

FILES:${PN} = "${nonarch_base_libdir}/firmware/* \
	     /opt/rtl8723bs_bt \
	     "
