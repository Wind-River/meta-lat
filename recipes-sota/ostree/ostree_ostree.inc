SRC_URI+= "\
           file://0001-ostree-first-2-patch.patch \
           file://0002-ostree-secure-boot-support-for-no-change-to-grub.cfg.patch \
           file://0003-Allow-updating-files-in-the-boot-directory.patch \
           file://0004-u-boot-add-bootdir-to-the-generated-uEnv.txt.patch \
           file://0005-uboot-add-non-default-for-bootdirs-to-uEnv.txt.patch \
           file://0006-ostree-swap-bootentry-atomically.patch \
           file://0007-using-bash-specifically.patch \
           file://0008-create-boot-symlink-based-on-relative-path.patch \
           file://0009-retrieve-correct-boot-prefix-at-runtime.patch \
           file://0010-encrypt-decrypt-password-of-remote-repository-uri.patch \
           file://0011-tweak-regex-of-ostree-system-generator.patch \
           file://0012-deploy-using-etc-in-runtime-as-merge-source.patch \
           file://0001-ostree-bootloader-uboot.c-Create-links-to-the-deploy.patch \
           file://0001-ostree-sysroot-deploy-if-OSTREE_ETC_MERGE_DIR-none-s.patch \
           file://0001-make-timezone-support-Hong-Kong.patch \
"

SRC_URI_append_x86-64 = " \
           file://0001-deploy-Handle-a-read-only-boot-efi.patch \
"

do_configure_prepend() {
    sed -i -e 's#@OSTREE_OSNAME@#${OSTREE_OSNAME}#g' ${S}/src/libostree/ostree-impl-system-generator.c
}
