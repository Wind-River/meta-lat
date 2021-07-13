SUMMARY = "ostree upgrade config manager"
DESCRIPTION = "Example of how to run some postinstall and postrm \
operations to complete an upgrade with ostree"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=12f884d2ae1ff87c09e5b7ccc2c4ca7e"

S = "${WORKDIR}"

RDEPENDS_${PN} += "util-linux-lsblk"

SRC_URI = "file://COPYING \
           file://ostree_upgrade.sh \
	   file://ostree_reset.sh \
          "

FILES_${PN} += "/usr/bin/ostree_upgrade.sh \
	/usr/bin/ostree_reset.sh \
	"

do_install() {
	install -d ${D}/usr/bin
	install -m 0755 ${S}/ostree_upgrade.sh ${D}/usr/bin/ostree_upgrade.sh
	install -m 0755 ${S}/ostree_reset.sh ${D}/usr/bin/ostree_reset.sh
}

RDEPENDS_${PN} += "watchdog"

pkg_postinst_ontarget_${PN}() {
	if [ ! -d /var/home ] ; then
		mkdir -p /var/home
	fi

	# 1-time only copy of any static home directories
	for dir in $(ls -1 /usr/homedirs/home); do
		if [ ! -d /home/$dir ] ; then
			cp -a /usr/homedirs/home/$dir /home/
		fi
	done
}
