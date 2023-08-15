def get_arch_setting_watchdog(bb, d):
    if d.getVar('TRANSLATED_TARGET_ARCH') in [ 'x86-64', 'i686', 'i586' ]:
        return "x86_64"
    else:
        return "arm"

ARCH_WATCHDOG_SETTING = "${@get_arch_setting_watchdog(bb, d)}"


SRC_URI += "\
	file://clearbootflag_${ARCH_WATCHDOG_SETTING}.sh \
"
FILESEXTRAPATHS:prepend := "${THISDIR}:${THISDIR}/files:"

RDEPENDS:${PN} += " \
    util-linux-findmnt \
"

do_install:append() {
	install -d ${D}${sbindir}
	install -m 0755 ${WORKDIR}/clearbootflag_${ARCH_WATCHDOG_SETTING}.sh ${D}${sbindir}/clearbootflag.sh
	if [ -e "${D}${systemd_system_unitdir}/watchdog.service" ] ; then
		sed -i "/ExecStart=/a ExecStartPost=-/usr/sbin/clearbootflag.sh" ${D}${systemd_system_unitdir}/watchdog.service
	fi
}

FILES:${PN} += " \
	${sbindir}/clearbootflag.sh \
"

SYSTEMD_AUTO_ENABLE = "enable"
