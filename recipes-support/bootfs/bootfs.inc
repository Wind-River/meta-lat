SUMMARY = "OSTree Network/Disk Image deployment tool"

LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=12f884d2ae1ff87c09e5b7ccc2c4ca7e"

S = "${WORKDIR}"

SRC_URI = "file://COPYING \
           file://bootfs.sh \
           file://bootfs_wrapper.sh \
           file://marvell-cn96xx-sd.sh \
          "
FILESEXTRAPATHS:prepend := "${LAYER_PATH_lat-layer}/scripts:"

FILES:${PN} += "${datadir}/bootfs \
	"

do_install() {
    install -d ${D}${datadir}/bootfs/scripts/
    install -m 0755 ${S}/bootfs.sh ${D}${datadir}/bootfs/scripts/

    install -d ${D}${datadir}/bootfs/boot_keys
    install -m 0644 ${OSTREE_GRUB_PW_FILE} ${D}${datadir}/bootfs/boot_keys/ostree_grub_pw
    if [ -n "${BOOT_KEYS_DIR}" ]; then
        cp -rf  ${BOOT_KEYS_DIR}/* ${D}${datadir}/bootfs/boot_keys/
    fi

    if [ -n "${UEFI_SB_KEYS_DIR}" -a -e "${UEFI_SB_KEYS_DIR}/DB.crt" ]; then
        install -m 0644 ${UEFI_SB_KEYS_DIR}/DB.crt ${D}${datadir}/bootfs/boot_keys/
    fi

    install -d ${D}${bindir}
    install -m 0755 ${S}/marvell-cn96xx-sd.sh ${D}${bindir}/marvell-cn96xx-sd.sh
    install -m 0755 ${S}/bootfs_wrapper.sh ${D}${bindir}/bootfs.sh
}
