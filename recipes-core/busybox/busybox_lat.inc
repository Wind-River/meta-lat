SRC_URI += "\
    file://partprobe.cfg \
"
FILESEXTRAPATHS:prepend := "${THISDIR}:${THISDIR}/busybox:"
