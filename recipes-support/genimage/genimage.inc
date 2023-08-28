SUMMARY = "Full image create script"
DESCRIPTION = "Provide a tools to create full image."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=12f884d2ae1ff87c09e5b7ccc2c4ca7e"

SRC_URI = "\
           file://genimage/COPYING \
           file://bash_tab_completion.sh \
           file://crossscripts/depmodwrapper \
           file://crossscript_wrapper.in \
           file://genimage/__init__.py \
           file://genimage/genimage.py \
           file://genimage/genfitimage.py \
           file://genimage/genyaml.py \
           file://genimage/genXXX.py \
           file://genimage/exampleyamls.py \
           file://genimage/geninitramfs.py \
           file://genimage/gencontainer.py \
           file://genimage/utils.py \
           file://genimage/constant.py.in \
           file://genimage/debian_constant.py.in \
           file://genimage/fit_constant.py.in \
           file://genimage/package_manager/__init__.py \
           file://genimage/package_manager/rpm/__init__.py \
           file://genimage/package_manager/deb/__init__.py \
           file://genimage/rootfs.py \
           file://genimage/image.py \
           file://genimage/container.py \
           file://genimage/sysdef.py \
           file://genimage/data/pre_rootfs/create_merged_usr_symlinks.sh \
           file://genimage/data/pre_rootfs/update_pkgdata.sh \
           file://genimage/data/post_rootfs/add_gpg_key.sh \
           file://genimage/data/post_rootfs/add_sysdef_support.sh \
           file://genimage/data/post_rootfs/enable_dhcpcd_service.sh \
           file://genimage/data/post_rootfs/update_boot_scr.sh \
           file://genimage/data/post_rootfs/update_grub_cfg.sh \
           file://genimage/data/post_rootfs/set_systemd_default_target.sh \
           file://genimage/data/post_rootfs/run.ssh_allow_empty_password \
           file://genimage/data/post_rootfs/run.ssh_allow_root_login \
           file://genimage/data/post_ustart/nxp_s32g.sh \
           file://genimage/data/post_wic/nxp_s32g.sh \
           file://genimage/data/post_ustart/aptiv_cvc_sousa.sh \
           file://genimage/data/post_wic/aptiv_cvc_sousa.sh \
           file://genimage/data/post_ustart/aptiv_cvc_fl.sh \
           file://genimage/data/post_wic/aptiv_cvc_fl.sh \
           file://genimage/data/post_wic/intel_socfpga_64.sh \
           file://genimage/data/post_ustart/intel_socfpga_64.sh \
           file://genimage/data/yaml_example/feature/vboxguestdrivers.yaml \
           file://genimage/data/yaml_example/feature/xfce_desktop.yaml \
           file://genimage/data/yaml_example/feature/set_root_password.yaml \
           file://genimage/data/yaml_example/feature/package_management.yaml \
           file://genimage/data/yaml_example/feature/debug-tweaks.yaml \
           file://genimage/data/yaml_example/feature/expire-root-passwd.yaml \
           file://genimage/data/yaml_example/debian_feature/debian-verbose-log.yaml \
           file://genimage/data/yaml_example/images/core-image-minimal.yaml \
           file://genimage/data/yaml_example/images/core-image-sato.yaml \
           file://genimage/data/yaml_example/images/container-base.yaml \
           file://genimage/data/yaml_example/machine/intel-x86-64.yaml \
           file://genimage/data/yaml_example/machine/bcm-2xxx-rpi4.yaml \
           file://genimage/data/yaml_example/sysdef/add-user-home.yaml \
           file://genimage/data/yaml_example/sysdef/add-system-user.yaml \
           file://genimage/data/yaml_example/sysdef/contains-container-base.yaml.in \
           file://genimage/data/yaml_example/sysdef/files/sudoers_sudo \
           file://genimage/data/yaml_example/sysdef/files/dns.conf \
           file://genimage/data/yaml_example/sysdef/run_always.d/10_start_containers.sh \
           file://genimage/data/yaml_example/sysdef/run_on_upgrade.d/containers.dat \
           file://genimage/data/yaml_example/sysdef/run_on_upgrade.d/10_update_containers.sh \
           file://genimage/data/yaml_example/sysdef/run_once.d/10_add_system_user.sh \
           file://genimage/data/yaml_example/sysdef/run_once.d/20_add_user_home.sh \
           file://genimage/data/yaml_example/sysdef/run_once.d/30_set_hostname.sh \
           file://genimage/data/yaml_example/sysdef/run_once.d/40_set_ntp.sh \
           file://genimage/data/yaml_example/sysdef/set-hostname.yaml \
           file://genimage/data/yaml_example/sysdef/set-ntp.yaml \
           file://genimage/data/yaml_example/sysdef/set-dns.yaml \
           file://genimage/data/yaml_example/sysdef/update-containers.yaml \
           file://genimage/data/sysdef/sysdef.sh \
           file://genimage/data/sysdef/sysdef.service \
           file://genimage/data/pykwalify/genimage-schema.yaml \
           file://genimage/data/pykwalify/gencontainer-schema.yaml \
           file://genimage/data/pykwalify/geninitramfs-schema.yaml \
           file://genimage/data/pykwalify/genfitimage-schema.yaml \
           file://genimage/data/pykwalify/partial-schemas.yaml \
           file://genimage/data/pykwalify/ext.py \
           file://genimage/data/yaml_template/startup-container.yaml.in \
           file://genimage/data/yaml_template/hvp-vx-lx.yaml.in \
           file://genimage/data/wic/mkhybridiso.wks.in \
           file://genimage/data/kickstart/kickstart.README.md.in \
           file://genimage/data/kickstart/lat-disk.ks \
           file://genimage/data/kickstart/lat-installer.ks \
           file://genimage/data/kickstart/lat-installer-static-ipv4.ks \
           file://genimage/data/yaml_template/install-over-wifi-eap.yaml \
           file://genimage/data/yaml_template/install-over-wifi-psk.yaml \
           file://genimage/data/yaml_template/set-wifi-eap.yaml \
           file://genimage/data/yaml_template/set-wifi-psk.yaml \
           file://genimage/scripts/run.do_image_ostree \
           file://genimage/scripts/run.do_image_otaimg \
           file://genimage/scripts/run.do_image_wic \
           file://genimage/scripts/run.do_image_oci \
           file://genimage/doc/wic_bcm-2xxx-rpi4.README.md.in \
           file://genimage/doc/ustart_bcm-2xxx-rpi4.README.md.in \
           file://genimage/doc/wic_intel-x86-64.README.md.in \
           file://genimage/doc/ustart_intel-x86-64.README.md.in \
           file://genimage/doc/container.README.md.in \
           file://genimage/doc/iso_intel-x86-64.README.md.in \
           file://genimage/doc/pxe-efi_intel-x86-64.README.md.in \
           file://genimage/doc/pxe-bios_intel-x86-64.README.md.in \
           file://genimage/doc/target_xilinx-zynq.README.md.in \
           file://genimage/doc/target_xilinx-zynqmp.README.md.in \
           file://genimage/doc/target_nxp-imx6.README.md.in \
           file://genimage/doc/target_nxp-imx8.README.md.in \
           file://genimage/doc/target_marvell-cn96xx.README.md.in \
           file://genimage/doc/target_nxp-s32g.README.md.in \
           file://genimage/doc/target_aptiv_cvc_sousa.README.md.in \
           file://genimage/doc/target_aptiv-cvc-fl.README.md.in \
           file://genimage/doc/target_intel-socfpga-64.README.md.in \
           file://genimage/doc/target_ti-j72xx.README.md.in \
           file://genimage/doc/target_nxp-ls1028.README.md.in \
           file://genimage/doc/target_nxp-ls1043.README.md.in \
           file://genimage/doc/target_nxp-lx2xxx.README.md.in \
           file://genimage/doc/target_axxiaarm64.README.md.in \
           file://genimage/doc/target_axxiaarm.README.md.in \
           file://genimage/doc/target_amd-snowyowl-64.README.md.in \
           file://METADATA.in \
           file://README.md \
           file://setup.py \
"

S = "${WORKDIR}/genimage"

SETUPTOOLS_SETUP_PATH = "${WORKDIR}/sources"

inherit setuptools3

LAT_DEFAULT_IMAGE ??= "lat-image-base"

OCI_IMAGE_AUTHOR ?= "${PATCH_GIT_USER_NAME}"
OCI_IMAGE_AUTHOR_EMAIL ?= "${PATCH_GIT_USER_EMAIL}"
OCI_IMAGE_TAG ?= "latest"
OCI_IMAGE_RUNTIME_UID ?= ""
OCI_IMAGE_WORKINGDIR ?= ""

# List of ports to expose from a container running this image:
#  PORT[/PROT]
#     format: <port>/tcp, <port>/udp, or <port> (same as <port>/tcp).
OCI_IMAGE_PORTS ?= ""

# key=value list of labels
OCI_IMAGE_LABELS ?= ""

# key=value list of environment variables
OCI_IMAGE_ENV_VARS ?= ""

do_patch[vardeps] += "MACHINE PACKAGE_FEED_BASE_PATHS PACKAGE_FEED_ARCHS PACKAGE_FEED_URIS PACKAGE_CLASSES OSTREE_OSNAME"
do_patch[vardeps] += "DEBIAN_CUSTOMIZE_FEED_URI DEFAULT_DEBIAN_MIRROR"
do_patch[vardeps] += "OSTREE_USE_AB"

do_patch:append() {
    bb.build.exec_func('do_write_py_template', d)
    bb.build.exec_func('do_copy_src', d)
    bb.build.exec_func('do_create_cross_cmd_wrapper', d)
}

CROSS_CMDS ?= " \
    /usr/bin/glib-compile-schemas \
    /usr/bin/gconftool-2 \
"

QEMU_ARGS[gconftool-2] = "-E GCONF_BACKEND_DIR=$D/usr/lib/GConf/2"

python do_create_cross_cmd_wrapper () {
    # cmd_wrapper.in -> glib-compile-schemas or ...
    cross_cmds = (d.getVar("CROSS_CMDS") or "").split()
    dest = os.path.join(d.getVar("WORKDIR"), "crossscripts")
    wrapper_template = os.path.join(d.getVar("WORKDIR"),"crossscript_wrapper.in")
    with open(wrapper_template, "r") as template:
        cmd_content = template.read()
        for cmd in cross_cmds:
            cmd_name = os.path.basename(cmd)
            qemuargs = d.getVarFlag('QEMU_ARGS', cmd_name) or ""
            with open(os.path.join(dest, cmd_name), "w") as cmd_f:
                content = cmd_content.replace("@COMMAND@", cmd)
                content = content.replace("@QEMU_ARGS@", qemuargs)
                cmd_f.write(content)
}

# Refer insert_feeds_uris in oe-core/meta/lib/oe/package_manager.py
# https://docs.yoctoproject.org/ref-manual/variables.html#term-PACKAGE_FEED_ARCHS
def get_remote_uris(feed_uris, feed_base_paths, feed_archs):
    def _construct_uris(uris, base_paths):
        """
        Construct URIs based on the following pattern: uri/base_path where 'uri'
        and 'base_path' correspond to each element of the corresponding array
        argument leading to len(uris) x len(base_paths) elements on the returned
        array
        """
        def _append(arr1, arr2, sep='/'):
            res = []
            narr1 = [a.rstrip(sep) for a in arr1]
            narr2 = [a.rstrip(sep).lstrip(sep) for a in arr2]
            for a1 in narr1:
                if arr2:
                    for a2 in narr2:
                        res.append("%s%s%s" % (a1, sep, a2))
                else:
                    res.append(a1)
            return res
        return _append(uris, base_paths)

    remote_uris = []
    for uri in _construct_uris(feed_uris.split(), feed_base_paths.split()):
        if feed_archs:
            for arch in feed_archs.split():
                repo_uri = uri + "/" + arch
                remote_uris.append(repo_uri)
        else:
            remote_uris.append(uri)
    return ' '.join(remote_uris)

DEFAULT_PACKAGE_FEED = ""

IMAGE_BOOT_FILES ??= ""

KERNEL_DEVICETREE ??= ""

PKG_MNGT_PACKAGE = " \
    ${@oe.utils.conditional('IMAGE_PKGTYPE', 'rpm', 'dnf rpm', '', d)} \
    ${@oe.utils.conditional('IMAGE_PKGTYPE', 'deb', 'apt dpkg', '', d)} \
"

do_copy_src() {
    install -d ${SETUPTOOLS_SETUP_PATH}
    install -m 0644 ${WORKDIR}/genimage/COPYING ${SETUPTOOLS_SETUP_PATH}/
    install -d ${SETUPTOOLS_SETUP_PATH}/genimage
    install -m 0644 ${WORKDIR}/genimage/*.py ${SETUPTOOLS_SETUP_PATH}/genimage
    cp -rf ${WORKDIR}/genimage/package_manager ${SETUPTOOLS_SETUP_PATH}/genimage/

    install -m 0644 ${WORKDIR}/METADATA.in ${SETUPTOOLS_SETUP_PATH}
    install -m 0644 ${WORKDIR}/README.md ${SETUPTOOLS_SETUP_PATH}
    install -m 0644 ${WORKDIR}/setup.py ${SETUPTOOLS_SETUP_PATH}
}

python do_write_py_template () {
    # constant.py.in -> constant.py and expand variables
    py_templates = [os.path.join(d.getVar("WORKDIR"),"genimage","constant.py.in"),
                    os.path.join(d.getVar("WORKDIR"),"genimage","fit_constant.py.in"),
                    os.path.join(d.getVar("WORKDIR"),"genimage","debian_constant.py.in")]
    for py_t in py_templates:
        body = "null"
        with open(py_t, "r") as pytf:
            body = pytf.read()
            d.setVar("_PY_TEMPLATE", body)
            body = d.getVar("_PY_TEMPLATE")
        py = os.path.splitext(py_t)[0]
        with open(py, "w") as pyf:
            pyf.write(body)
}

BOOT_SINGED_SHIM ??= ""
BOOT_SINGED_SHIMTOOL ??= ""
BOOT_SINGED_GRUB ??= ""
BOOT_EFITOOL ??= ""
BOOT_NOSIG_GRUB ??= ""
BOOT_GRUB_CFG ??= ""

LAT_XFCE_THEMES ??= ""

do_install:append() {
	install -d ${D}${datadir}/genimage/
	cp -rf ${WORKDIR}/genimage/data ${D}${datadir}/genimage/
	cp -rf ${WORKDIR}/genimage/scripts ${D}${datadir}/genimage/
	cp -rf ${WORKDIR}/genimage/doc ${D}${datadir}/genimage/
	install -d ${D}${datadir}/genimage/rpm_keys/
	cp ${OSTREE_GPGDIR}/RPM-GPG-PRIVKEY-${OSTREE_GPGID} ${D}${datadir}/genimage/rpm_keys/

	install -d ${D}${datadir}/genimage/data/wic/
	cp -f ${LAYER_PATH_lat-layer}/wic/ostree-*.wks.in ${D}${datadir}/genimage/data/wic/

	install -d ${D}${bindir}/crossscripts
	install -m 0755 ${WORKDIR}/crossscripts/* ${D}${bindir}/crossscripts

	if [ -n "${LAT_XFCE_THEMES}" ]; then
		sed -i "/packages:/a - ${LAT_XFCE_THEMES}" \
		    ${D}${datadir}/genimage/data/yaml_example/feature/xfce_desktop.yaml
	fi
}

USTART_POST_SCRIPT ??= ""
USTART_POST_SCRIPT:nxp-s32g = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_ustart/nxp_s32g.sh"
USTART_POST_SCRIPT:aptiv_cvc_sousa = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_ustart/aptiv_cvc_sousa.sh"
USTART_POST_SCRIPT:aptiv-cvc-fl = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_ustart/aptiv_cvc_fl.sh"
USTART_POST_SCRIPT:intel-socfpga-64 = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_ustart/intel_socfpga_64.sh"
WIC_POST_SCRIPT ??= ""
WIC_POST_SCRIPT:nxp-s32g = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_wic/nxp_s32g.sh"
WIC_POST_SCRIPT:aptiv_cvc_sousa = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_wic/aptiv_cvc_sousa.sh"
WIC_POST_SCRIPT:aptiv-cvc-fl = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_wic/aptiv_cvc_fl.sh"
WIC_POST_SCRIPT:intel-socfpga-64 = "$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/post_wic/intel_socfpga_64.sh"

DEFAULT_DEBIAN_MIRROR ??= "http://ftp.us.debian.org/debian"
DEFAULT_DEBIAN_DISTRO ??= "bullseye"
DEBIAN_CUSTOMIZE_FEED_URI ??= "not_set"
DEBIAN_OSTREE_VERSION ??= "2019.1-1"
DEFAULT_EXTERNAL_DEB_PACKAGE_FEED ?= "deb ${DEFAULT_DEBIAN_MIRROR} ${DEFAULT_DEBIAN_DISTRO} main contrib;"

SUPPORTED_PKGTYPES ?= " \
    ${@bb.utils.contains('PACKAGE_CLASSES','package_rpm','rpm','',d)} \
    ${@bb.utils.contains('PACKAGE_CLASSES','package_deb','deb','',d)} \
"

PACKAGE_FEED_URIS ??= ""
RPM_PACKAGE_FEED_URIS ??= "${PACKAGE_FEED_URIS}"
DEB_PACKAGE_FEED_URIS ??= "${PACKAGE_FEED_URIS}"

PACKAGE_FEED_BASE_PATHS ??= ""
RPM_PACKAGE_FEED_BASE_PATHS ??= "${PACKAGE_FEED_BASE_PATHS}"
DEB_PACKAGE_FEED_BASE_PATHS ??= "${PACKAGE_FEED_BASE_PATHS}"

RPM_PACKAGE_FEED_ARCHS ??= ""
DEB_PACKAGE_FEED_ARCHS ??= ""
DEFAULT_RPM_PACKAGE_FEED ??= ""
DEFAULT_DEB_PACKAGE_FEED ??= ""
REMOTE_RPM_PKGDATADIR ??= ""
REMOTE_DEB_PKGDATADIR ??= ""
DEPLOY_URIS ??= "$DEPLOY_URIS"
DEPLOY_URIS:class-native ?= "${DEPLOY_DIR}"
DEPLOY_BASE_PATHS ??= ""
DEPLOY_BASE_PATHS:class-native ?= "/images/${MACHINE}"

PLATFORM ??= ""
PLATFORM:aptiv_cvc_sousa = "aptiv_cvc_sousa"
PLATFORM:aptiv-cvc-fl = "aptiv_cvc_fl"

UBOOT_ENTRYPOINT ??= "0xa4000000"
UBOOT_LOADADDRESS ??= "0xa4000000"
UBOOT_DTB_LOADADDRESS ??= "0xb4000000"
UBOOT_RAMDISK_LOADADDRESS ??= "0xb8000000"

IMAGE_BOOT_FILES_LATFIT = "boot.scr ${@bb.utils.contains('IMAGE_INSTALL', 'pfe', 's32g_pfe_class.fw s32g_pfe_util.fw', '', d)}"

FIT_LX_FDT ?= ""
FIT_LX_FDT:aptiv_cvc_sousa = "${@os.path.basename(d.getVar('DTB_FILES', False))}"
FIT_LX_FDT:aptiv-cvc-fl = "${@os.path.basename(d.getVar('DTB_FILES', False).split()[0])}"

do_configure[prefuncs] += "check_package_feed_uris"

python check_package_feed_uris() {
    if not (d.getVar('RPM_PACKAGE_FEED_URIS') or d.getVar('DEB_PACKAGE_FEED_URIS')):
        bb.warn('Both RPM_PACKAGE_FEED_URIS and DEB_PACKAGE_FEED_URIS are NULL, please set valid URIs for them via PACKAGE_FEED_URIS.')
}

python __anonymous () {
    machine = d.getVar('MACHINE')
    if machine == 'intel-x86-64':
        if d.getVar('DEBIAN_CUSTOMIZE_FEED_URI') != 'not_set':
            d.appendVar("SUPPORTED_PKGTYPES", " external-debian")
            d.appendVar("DEFAULT_EXTERNAL_DEB_PACKAGE_FEED", d.expand("deb [trusted=yes] ${DEBIAN_CUSTOMIZE_FEED_URI} ./"))

    if not d.getVar('DEB_PACKAGE_FEED_BASE_PATHS'):
        d.setVar('DEB_PACKAGE_FEED_BASE_PATHS', 'deb')
    if not d.getVar('RPM_PACKAGE_FEED_BASE_PATHS'):
        d.setVar('RPM_PACKAGE_FEED_BASE_PATHS', 'rpm')

    rpm_uris = d.getVar('RPM_PACKAGE_FEED_URIS') or ""
    rpm_base_paths = d.getVar('RPM_PACKAGE_FEED_BASE_PATHS') or ""
    remote_rpm_uris = get_remote_uris(rpm_uris, rpm_base_paths, d.getVar('RPM_PACKAGE_FEED_ARCHS'))
    d.setVar("DEFAULT_RPM_PACKAGE_FEED", remote_rpm_uris)

    if not d.getVar('REMOTE_RPM_PKGDATADIR'):
        if rpm_uris and rpm_base_paths:
            rpm_uris_list = rpm_uris.split()
            rpm_base_paths_list = rpm_base_paths.split()
            if len(rpm_uris_list) > 1:
                bb.note("Found multiple RPM_PACKAGE_FEED_URIS, default pkgdata to the first one")
            if len(rpm_base_paths_list) > 1:
                bb.note("Found multiple RPM_PACKAGE_FEED_BASE_PATHS, default pkgdata to the first one")
            d.setVar("REMOTE_RPM_PKGDATADIR", "%s/%s" % (rpm_uris_list[0], rpm_base_paths_list[0]))

    deb_uris = d.getVar('DEB_PACKAGE_FEED_URIS') or ""
    if deb_uris:
        deb_base_paths = d.getVar('DEB_PACKAGE_FEED_BASE_PATHS') or ""
        remote_deb_uris = get_remote_uris(deb_uris, deb_base_paths, d.getVar('DEB_PACKAGE_FEED_ARCHS'))
        d.setVar("DEFAULT_DEB_PACKAGE_FEED", remote_deb_uris)

        if not d.getVar("REMOTE_DEB_PKGDATADIR"):
            if deb_uris and deb_base_paths:
                deb_uris_list = deb_uris.split()
                deb_base_paths_list = deb_base_paths.split()
                if len(deb_uris_list) > 1:
                    bb.note("Found multiple DEB_PACKAGE_FEED_URIS, default pkgdata to the first one")
                if len(deb_base_paths_list) > 1:
                    bb.note("Found multiple DEB_PACKAGE_FEED_BASE_PATHS, default pkgdata to the first one")
                d.setVar("REMOTE_DEB_PKGDATADIR", "%s/%s" % (deb_uris_list[0], deb_base_paths_list[0]))
            d.setVar("REMOTE_DEB_PKGDATADIR", d.expand("${@d.getVar('DEB_PACKAGE_FEED_URIS').split()[0]}/${DEB_PACKAGE_FEED_BASE_PATHS}"))
}
