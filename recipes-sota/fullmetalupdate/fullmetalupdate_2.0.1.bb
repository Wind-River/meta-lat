DESCRIPTION = "FullMetalUpdate Python daemon"
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/LGPL-2.1-only;md5=1a6d268fd218675ffea8be556788b780"

inherit systemd

RDEPENDS:${PN} += " \ 
    ostree \
    python3 \
    python3-aiohttp \
    systemd \
    dbus \
    python3-pydbus \
    python3-pygobject \
    socat \
" 

SRC_URI += " \ 
    git://github.com/FullMetalUpdate/fullmetalupdate.git;branch=master;protocol=https \
    file://fullmetalupdate.sh \
    file://fullmetalupdate.service \
    file://0001-async_timeout-stop-use-loop-argument.patch \
    file://0001-remove-function-for-set-uboot-enviroment.patch \
    file://0001-stop-use-deprecate-disutils.patch \
    file://0001-fix-python-3.10-compatibility.patch \
    ${@bb.utils.contains('DISTRO_FEATURES', 'ostree', '', 'file://0001-remove-init-of-os-ostree-repo.patch', d)} \
"

SRCREV = "39ec5045e2a4debc8491f62b33b1d364aa14b489"

S="${WORKDIR}/git"

FILES:${PN} += " \ 
    ${base_bindir}/fullmetalupdate \
    ${base_bindir}/fullmetalupdate.service \
    ${APP_DIRECTORY} \
"

SYSTEMD_SERVICE:${PN} = "fullmetalupdate.service"

do_compile[noexec] = "1"

CLEANBROKEN = "1"

do_install() {
    install -d ${D}${base_bindir}/fullmetalupdate/
    cp -r --no-dereference --preserve=mode,links -v ${WORKDIR}/git/* ${D}${base_bindir}/fullmetalupdate/
    rm -rf ${D}${base_bindir}/fullmetalupdate/.git/

    install -d ${D}/${APP_DIRECTORY}
    install -d ${D}${sysconfdir}/fullmetalupdate
   
    install -m 755 ${HAWKBIT_CONFIG_FILE} ${D}${sysconfdir}/fullmetalupdate/config.cfg

    install -m 755 ${WORKDIR}/fullmetalupdate.sh ${D}${base_bindir}/fullmetalupdate/fullmetalupdate.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644  ${WORKDIR}/fullmetalupdate.service ${D}${systemd_system_unitdir}

    sed -i -e 's,@BASEBINDIR@,${base_bindir},g' ${D}${systemd_system_unitdir}/fullmetalupdate.service
    sed -i -e "s;PATH_APPS = '/apps';PATH_APPS = '${APP_DIRECTORY}';g" ${D}${base_bindir}/fullmetalupdate/fullmetalupdate/updater.py
}

FILES:${PN}-doc = "${base_bindir}/fullmetalupdate/fullmetalupdate/doc"

python __anonymous() {
    config_file = d.getVar('HAWKBIT_CONFIG_FILE')
    if not config_file:
        raise bb.parse.SkipRecipe("HAWKBIT_CONFIG_FILE not defined, please config it.")
    elif not os.path.isfile(config_file):
        raise bb.parse.SkipRecipe("HAWKBIT_CONFIG_FILE(" + config_file + ") is not a file, please fix the path." , config_file)
}
