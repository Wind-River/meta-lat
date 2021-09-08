include wic.inc

RDEPENDS:${PN} += " \
    nativesdk-python3 \
    nativesdk-parted \
    nativesdk-syslinux \
    nativesdk-gptfdisk \
    nativesdk-dosfstools \
    nativesdk-mtools \
    nativesdk-bmap-tools \
    nativesdk-btrfs-tools \
    nativesdk-squashfs-tools \
    nativesdk-pseudo \
    nativesdk-e2fsprogs \
    nativesdk-e2fsprogs-mke2fs \
    nativesdk-e2fsprogs-e2fsck \
    nativesdk-util-linux \
    nativesdk-tar \
    nativesdk-chrpath \
"

FILES:${PN} += "${SDKPATHNATIVE}"

do_install:append() {
    ln -snf -r ${D}${datadir}/poky/meta/recipes-core/systemd/systemd-systemctl/systemctl ${D}${bindir}/systemctl
}

inherit nativesdk
