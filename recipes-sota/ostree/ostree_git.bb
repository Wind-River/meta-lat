SUMMARY = "Tool for managing bootable, immutable, versioned filesystem trees"
LICENSE = "GPLv2+"
LIC_FILES_CHKSUM = "file://COPYING;md5=5f30f0716dfdd0d91eb439ebec522ec2"

inherit autotools-brokensep pkgconfig systemd gobject-introspection

INHERIT_remove_class-native = "systemd"

SRC_URI = "gitsm://github.com/ostreedev/ostree.git;branch=main \
           file://system-export.sh \
           file://sample.conf \
           file://0001-fsck-Throw-and-error-and-return-non-zero-for-non-ver.patch \
           file://0001-boot-Replace-deprecated-StandardOutput-syslog-with-j.patch \
           file://0001-Drop-use-of-volatile.patch \
"
require ${@bb.utils.contains('DISTRO_FEATURES', 'ostree', '${BPN}_ostree.inc', '', d)}

SRCREV = "6649032a375238255052a43adb8bc56faac989ca"

CLEANBROKEN = "1"

PV = "2019.1+git${SRCPV}"

S = "${WORKDIR}/git"

BBCLASSEXTEND = "native nativesdk"

OSTREE_GIT_DEP = "${@'' if (d.getVar('GPG_BIN', True) or '').startswith('/') else 'gnupg-native gpgme-native'}"
DEPENDS += "attr libarchive glib-2.0 pkgconfig gpgme fuse libsoup-2.4 e2fsprogs gtk-doc-native curl bison-native"
DEPENDS_append_class-native = " ${OSTREE_GIT_DEP}"
DEPENDS_append = "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', ' systemd', '', d)}"
DEPENDS_remove_class-native = "systemd-native"

RDEPENDS_${PN}_append_class-target = " ostree-switchroot"

RDEPENDS_${PN} = "gnupg util-linux-libuuid util-linux-libblkid util-linux-libmount libcap xz bash openssl findutils"

RDEPENDS_${PN}_remove_class-native = "python-native"

RDEPENDS_${PN}_append_class-target = " pv"

RDEPENDS_${PN}_remove_class-nativesdk = "util-linux-libuuid util-linux-libblkid util-linux-libmount"
RDEPENDS_${PN}_append_class-nativesdk = " util-linux "

EXTRA_OECONF = "--with-libarchive --disable-gtk-doc --disable-gtk-doc-html --disable-gtk-doc-pdf --disable-man --with-smack --with-builtin-grub2-mkconfig  \
 --libdir=${libdir} "
EXTRA_OECONF_append_class-native = " --enable-wrpseudo-compat"
EXTRA_OECONF_append_class-nativesdk = " --disable-otmpfile"

# Path to ${prefix}/lib/ostree/ostree-grub-generator is hardcoded on the
#  do_configure stage so we do depend on it
SYSROOT_DIR = "${STAGING_DIR_TARGET}"
SYSROOT_DIR_class-native = "${STAGING_DIR_NATIVE}"
do_configure[vardeps] += "SYSROOT_DIR"

SYSTEMD_REQUIRED = "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}"
SYSTEMD_REQUIRED_class-native = ""

SYSTEMD_SERVICE_${PN} = "ostree-prepare-root.service ostree-remount.service"
SYSTEMD_SERVICE_${PN}_class-native = ""

PACKAGECONFIG ??= "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd', '', d)}"
PACKAGECONFIG_class-native = ""
PACKAGECONFIG[systemd] = "--with-systemdsystemunitdir=${systemd_unitdir}/system/ --with-dracut"

FILES_${PN} += "${libdir}/ostree/ ${libdir}/ostbuild"

export STAGING_INCDIR
export STAGING_LIBDIR

do_configure() {
 unset docdir
 NOCONFIGURE=1 ./autogen.sh
 oe_runconf
}

do_compile_prepend() {
 export BUILD_SYS="${BUILD_SYS}"
 export HOST_SYS="${HOST_SYS}"
}

export SYSTEMD_REQUIRED

do_install_append() {
 if [ -n ${SYSTEMD_REQUIRED} ]; then
  install -m 644 -p -D ${S}/src/boot/ostree-prepare-root.service ${D}${systemd_unitdir}/system/ostree-prepare-root.service
  install -m 644 -p -D ${S}/src/boot/ostree-remount.service ${D}${systemd_unitdir}/system/ostree-remount.service
 fi
 install -d ${D}/${sysconfdir}/ostree/remotes.d/
 install  ${WORKDIR}/sample.conf ${D}/${sysconfdir}/ostree/remotes.d/
 install -m 0755 ${WORKDIR}/system-export.sh ${D}/${bindir}/system-export
}

do_install_append_class-native() {
	create_wrapper ${D}${bindir}/ostree OSTREE_GRUB2_EXEC="${STAGING_LIBDIR_NATIVE}/ostree/ostree-grub-generator"
}


FILES_${PN} += " \
    ${@'${systemd_unitdir}/system/' if d.getVar('SYSTEMD_REQUIRED', True) else ''} \
    ${@'/usr/lib/dracut/modules.d/98ostree/module-setup.sh' if d.getVar('SYSTEMD_REQUIRED', True) else ''} \
    ${datadir}/gir-1.0 \
    ${datadir}/gir-1.0/OSTree-1.0.gir \
    ${datadir}/bash-completion \
    /usr/lib/girepository-1.0 \
    /usr/lib/girepository-1.0/OSTree-1.0.typelib \
    /usr/lib/ostree/ostree-grub-generator \
    /usr/lib/ostree/ostree-remount \
    ${systemd_unitdir} \
    /usr/lib/tmpfiles.d \
"

PACKAGES =+ "${PN}-switchroot"

FILES_${PN}-switchroot = "/usr/lib/ostree/ostree-prepare-root"
RDEPENDS_${PN}-switchroot = ""
DEPENDS_remove_class-native = "systemd-native"

