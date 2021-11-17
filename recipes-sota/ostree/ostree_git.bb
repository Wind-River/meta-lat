SUMMARY = "Tool for managing bootable, immutable, versioned filesystem trees"
LICENSE = "GPLv2+"
LIC_FILES_CHKSUM = "file://COPYING;md5=5f30f0716dfdd0d91eb439ebec522ec2"

inherit autotools-brokensep pkgconfig systemd gobject-introspection

INHERIT:remove:class-native = "systemd"

SRC_URI = "gitsm://github.com/ostreedev/ostree.git;branch=main;protocol=https \
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
DEPENDS:append:class-native = " ${OSTREE_GIT_DEP}"
DEPENDS:append = "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', ' systemd', '', d)}"
DEPENDS:remove:class-native = "systemd-native"

RDEPENDS:${PN}:append:class-target = " ostree-switchroot"

RDEPENDS:${PN} = "gnupg util-linux-libuuid util-linux-libblkid util-linux-libmount libcap xz bash openssl findutils"

RDEPENDS:${PN}:remove:class-native = "python-native"

RDEPENDS:${PN}:append:class-target = " pv"

RDEPENDS:${PN}:remove:class-nativesdk = "util-linux-libuuid util-linux-libblkid util-linux-libmount"
RDEPENDS:${PN}:append:class-nativesdk = " util-linux "

EXTRA_OECONF = "--with-libarchive --disable-gtk-doc --disable-gtk-doc-html --disable-gtk-doc-pdf --disable-man --with-smack --with-builtin-grub2-mkconfig  \
 --libdir=${libdir} "
EXTRA_OECONF:append:class-native = " --enable-wrpseudo-compat"
EXTRA_OECONF:append:class-nativesdk = " --disable-otmpfile"

# Path to ${prefix}/lib/ostree/ostree-grub-generator is hardcoded on the
#  do_configure stage so we do depend on it
SYSROOT_DIR = "${STAGING_DIR_TARGET}"
SYSROOT_DIR:class-native = "${STAGING_DIR_NATIVE}"
do_configure[vardeps] += "SYSROOT_DIR"

SYSTEMD_REQUIRED = "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}"
SYSTEMD_REQUIRED:class-native = ""

SYSTEMD_SERVICE:${PN} = "ostree-prepare-root.service ostree-remount.service"
SYSTEMD_SERVICE:${PN}:class-native = ""

PACKAGECONFIG ??= "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd', '', d)}"
PACKAGECONFIG:class-native = ""
PACKAGECONFIG[systemd] = "--with-systemdsystemunitdir=${systemd_unitdir}/system/ --with-dracut"

FILES:${PN} += "${libdir}/ostree/ ${libdir}/ostbuild"

export STAGING_INCDIR
export STAGING_LIBDIR

do_configure() {
 unset docdir
 NOCONFIGURE=1 ./autogen.sh
 oe_runconf
}

do_compile:prepend() {
 export BUILD_SYS="${BUILD_SYS}"
 export HOST_SYS="${HOST_SYS}"
}

export SYSTEMD_REQUIRED

do_install:append() {
 if [ -n ${SYSTEMD_REQUIRED} ]; then
  install -m 644 -p -D ${S}/src/boot/ostree-prepare-root.service ${D}${systemd_unitdir}/system/ostree-prepare-root.service
  install -m 644 -p -D ${S}/src/boot/ostree-remount.service ${D}${systemd_unitdir}/system/ostree-remount.service
 fi
 install -d ${D}/${sysconfdir}/ostree/remotes.d/
 install  ${WORKDIR}/sample.conf ${D}/${sysconfdir}/ostree/remotes.d/
 install -m 0755 ${WORKDIR}/system-export.sh ${D}/${bindir}/system-export
}

do_install:append:class-native() {
	create_wrapper ${D}${bindir}/ostree OSTREE_GRUB2_EXEC="${STAGING_LIBDIR_NATIVE}/ostree/ostree-grub-generator"
}


FILES:${PN} += " \
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

FILES:${PN}-switchroot = "/usr/lib/ostree/ostree-prepare-root"
RDEPENDS:${PN}-switchroot = ""
DEPENDS:remove:class-native = "systemd-native"

