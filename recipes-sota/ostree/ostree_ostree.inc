SRC_URI+= "\
           file://0004-u-boot-add-bootdir-to-the-generated-uEnv.txt.patch \
           file://0005-uboot-add-non-default-for-bootdirs-to-uEnv.txt.patch \
           file://0010-encrypt-decrypt-password-of-remote-repository-uri.patch \
           file://0011-tweak-regex-of-ostree-system-generator.patch \
           file://0012-deploy-using-etc-in-runtime-as-merge-source.patch \
           file://0001-ostree-sysroot-deploy-if-OSTREE_ETC_MERGE_DIR-none-s.patch \
           file://0001-make-timezone-support-Hong-Kong.patch \
           file://0001-create-links-to-the-deploy-directory-in-boot-and-ost.patch \
           file://0001-Allow-updating-files-in-the-boot-directory.patch \
"

SRC_URI:append:x86-64 = " \
           file://0001-deploy-Handle-a-read-only-boot-efi.patch \
"

do_configure:prepend() {
    sed -i -e 's#@OSTREE_OSNAME@#${OSTREE_OSNAME}#g' ${S}/src/libostree/ostree-impl-system-generator.c
}
