FILESEXTRAPATHS:prepend := "${THISDIR}:${THISDIR}/files:"

SRC_URI += " \
    file://0001-fsck-Throw-and-error-and-return-non-zero-for-non-ver.patch \
    file://0002-u-boot-add-bootdir-to-the-generated-uEnv.txt.patch \
    file://0003-tweak-regex-of-ostree-system-generator.patch \
    file://0004-deploy-using-etc-in-runtime-as-merge-source.patch \
    file://0005-create-links-to-the-deploy-directory-in-boot-and-ost.patch \
    file://0006-Allow-updating-files-in-the-boot-directory.patch \
    file://0007-get-output-of-ostree-prepare-root-back.patch \
    file://0008-no-warn-if-we-find-content-in-the-deployment-s-var.patch \
"
SRC_URI:append:x86-64 = " \
    file://0001-deploy-Handle-a-read-only-boot-efi.patch \
"
PACKAGECONFIG:append = " \
    builtin-grub2-mkconfig \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd libmount', '', d)} \
"
