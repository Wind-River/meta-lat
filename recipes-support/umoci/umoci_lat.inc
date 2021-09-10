LIC_FILES_CHKSUM:class-nativesdk = "file://src/${GO_IMPORT}/COPYING;md5=3b83ef96387f14655fc854ddc3c6bd57"
SRC_URI:class-nativesdk = " \
    git://${GO_IMPORT}; \
"

SRCREV:class-nativesdk = "${SRCREV_umoci}"

S:class-nativesdk = "${WORKDIR}/git"

export GO111MODULE="off"
do_configure:class-nativesdk() {
	cd ${S}
    go_do_configure
}
do_compile:class-nativesdk() {
    go_do_compile
}
do_install:class-nativesdk() {
    go_do_install
}

INSANE_SKIP:${PN} += "already-stripped"
INSANE_SKIP:${PN}-dev = "file-rdeps"
