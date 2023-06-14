SUMMARY = "U-Boot boot.scr SD boot environment generation for ARM targets"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

INHIBIT_DEFAULT_DEPS = "1"
PACKAGE_ARCH = "${MACHINE_ARCH}"

DEPENDS = "u-boot-mkimage-native"

inherit deploy

DEFAULT_DTB ??= ""
OSTREE_UBOOT_CMD ??= "bootz"
OSTREE_BOOTSCR ??= "fs_links"
OSTREE_NET_INSTALL ??= "${@oe.utils.conditional('OSTREE_USE_FIT', '1', '0', '1', d)}"
OSTREE_NETINST_ARGS ??= "instab=${OSTREE_USE_AB}"
OSTREE_NETINST_BRANCH ??= "core-image-minimal"
OSTREE_NETINST_DEV ??= "/dev/mmcblk0"
OSTREE_BSP_ARGS ??= ""

bootscr_env_import() {
    cat <<EOF > ${WORKDIR}/uEnv.txt
setenv machine_name ${MACHINE}
setenv bretry 32
if test \${skip_script_fdt} != yes; then setenv fdt_file $default_dtb; fi
setenv A 5
setenv B 7
setenv ex _b
setenv filesize 99
fatsize mmc \${mmcdev}:1 no_ab
if test \${filesize} = 1;then setenv ex;setenv B \$A;fi
setenv mmcpart \$A
setenv rootpart ostree_root=LABEL=otaroot\${labelpre}
setenv bootpart ostree_boot=LABEL=otaboot\${labelpre}
setenv mmcpart_r \$B
setenv rootpart_r ostree_root=LABEL=otaroot\${ex}\${labelpre}
setenv bootpart_r ostree_boot=LABEL=otaboot\${ex}\${labelpre}
setenv bpart A
if test "\${no_setexpr}" = "yes"; then
  if fatload mmc \${mmcdev}:1 \${loadaddr} boot_ab_flag;then setenv bpartv \${loadaddr}; if test \${bpartv} = 42333231;then setenv bpart B;fi;fi
else
  if fatload mmc \${mmcdev}:1 \${loadaddr} boot_ab_flag;then setexpr.l bpartv *\${loadaddr} \& 0xffffffff; if test \${bpartv} = 42333231;then setenv bpart B;fi;fi
  setexpr loadaddr1 \${loadaddr} + 1
  setexpr loadaddr2 \${loadaddr} + 2
  setexpr bct_addr \${loadaddr} + 200
  setexpr bct_addr1 \${loadaddr} + 201
fi
setenv obpart \${bpart}
mw.l \${bct_addr} 52573030
setenv cntv 30
setenv bdef 30
setenv switchab if test \\\${bpart} = B\\;then setenv bpart A\\;else setenv bpart B\\;fi
if test "\${no_setexpr}" = "yes"; then
  if fatload mmc \${mmcdev}:1 \${loadaddr} boot_cnt;then setenv cntv0 \${loadaddr2};if test \${cntv0} = 5257;then setenv cntv \${loadaddr};setenv bdef \${loadaddr1};fi;fi
  if test \${bdef} = 31;then run switchab;fi
  if test \${cntv} > \${bretry};then run switchab;setenv cntv 30;if test \${bdef} = 31; then setenv bdef 30;else setenv bdef 31;fi;else setenv cntv 31;fi
else
  if fatload mmc \${mmcdev}:1 \${loadaddr} boot_cnt;then setexpr.w cntv0 *\${loadaddr2};if test \${cntv0} = 5257;then setexpr.b cntv *\${loadaddr};setexpr.b bdef *\${loadaddr1};fi;fi
  if test \${bdef} = 31;then run switchab;fi
  if test \${cntv} > \${bretry};then run switchab;setenv cntv 30;if test \${bdef} = 31; then setenv bdef 30;else setenv bdef 31;fi;else setexpr.b cntv \${cntv} + 1;fi
fi
mw.b \${bct_addr} \${cntv}
mw.b \${bct_addr1} \${bdef}
fatwrite mmc \${mmcdev}:1 \${bct_addr} boot_cnt 4
if test \${no_menu} != yes; then
 if test \${bdef} = 30;then
  setenv bootmenu_0 Boot Primary volume \${bpart}=
  setenv bootmenu_1 Boot Rollback=setenv bdef 31\;run switchab
 else
  setenv bootmenu_0 Boot Rollback \${bpart}=
  setenv bootmenu_1 Boot Primary volume=setenv bdef 30\;run switchab
 fi
 bootmenu \${menutimeout}
else
  setenv menu_0_main "Primary volume \${bpart}"
  setenv menu_1_back "Rollback"
  setenv menu_0_back "Rollback \${bpart}"
  setenv menu_1_main "Primary volume"
  if test \${bdef} = 30; then
    setenv menu_0 "\${menu_0_main}"
    setenv menu_1 "\${menu_1_back}"
  else
    setenv menu_0 "\${menu_0_back}"
    setenv menu_1 "\${menu_1_main}"
  fi
  echo
  echo
  echo "  *** U-Boot Boot Menu ***"
  echo
  echo "     * Boot \${menu_0}"
  echo "     * Boot \${menu_1}"
  echo "     * U-Boot console"
  echo
  echo
  echo "*** Booting \${menu_0} in 3 seconds, press Ctrl-C to boot next menu"
  echo
  echo
  if sleep 3; then
    echo
  else
    echo
    echo
    echo "*** Booting \${menu_1} in 3 seconds, press Ctrl-C to boot next menu"
    echo
    echo
    if sleep 3; then
      if test \${bdef} = 30; then
        setenv bdef 31
      else
        setenv bdef 30
      fi
      run switchab
    else
      exit
    fi
  fi
fi
if test \${bdef} = 30;then echo "==Booting default \${bpart}==";else echo "==Booting Rollback \${bpart}==";fi
if test \${bpart} = B; then
 setenv mmcpart \$B;
 setenv rootpart ostree_root=LABEL=otaroot\${ex}\${labelpre};
 setenv bootpart ostree_boot=LABEL=otaboot\${ex}\${labelpre};
 setenv mmcpart_r \$A;
 setenv rootpart_r ostree_root=LABEL=otaroot\${labelpre};
 setenv bootpart_r ostree_boot=LABEL=otaboot\${labelpre};
fi
if test -n \${rollback_f} && test \${rollback_f} = yes;then setenv bdef 31;setenv mmcpart \${mmcpart_r};setenv rootpart \${rootpart_r};setenv bootpart \${bootpart_r};echo "FORCED ROLLBACK";fi
setenv loadenvscript ext4load mmc \${mmcdev}:\${mmcpart} \${loadaddr} /loader/uEnv.txt
run loadenvscript && env import -t \${loadaddr} \${filesize}
setenv loadkernel ext4load mmc \${mmcdev}:\${mmcpart} \${loadaddr} /\${kernel_image}
setenv loadramdisk ext4load mmc \${mmcdev}:\${mmcpart} \${initrd_addr} /\${ramdisk_image}
setenv loaddtb ext4load mmc \${mmcdev}:\${mmcpart} \${fdt_addr} /\${bootdir}/\${fdt_file}
if test \${skip_script_wd} != yes; then setenv wdttimeout 120000; fi
run loadramdisk
run loaddtb
run loadkernel
if test \${bdef} = 31 && test "\${ex}" != "_b"; then
setenv bootargs \${bootargs2} \${bootpart} \${rootpart} ${OSTREE_CONSOLE} ${OSTREE_BSP_ARGS} \${smp} flux=fluxdata\${labelpre}
else
setenv bootargs \${bootargs} \${bootpart} \${rootpart} ${OSTREE_CONSOLE} ${OSTREE_BSP_ARGS} \${smp} flux=fluxdata\${labelpre}
fi
${OSTREE_UBOOT_CMD} \${loadaddr} \${initrd_addr} \${fdt_addr}
EOF
}

bootscr_fs_links() {
    NETINST_ARGS="${OSTREE_NETINST_ARGS}"

    cat <<EOF > ${WORKDIR}/uEnv.txt
${OSTREE_BOOTSCR_PRECMD}
setenv machine_name ${MACHINE}
setenv bretry 32
if test \${skip_script_fdt} != yes; then setenv fdt_file $default_dtb; fi
if test -n "\${load_fitimage_addr}"; then
  setenv ninst 0
else
  setenv ninst ${OSTREE_NET_INSTALL}
fi
setenv A 5
setenv B 7
setenv ex _b
setenv filesize 99
if test ! -n "\${devtype}"; then
 setenv devtype mmc
fi
if test ! -n "\${devnum}"; then
 setenv devnum 0
fi
setenv devcmd \${devtype}
fatload \${devtype} \${devnum}:1 \${loadaddr} no_ab
if test \${filesize} = 1;then setenv ex;setenv B \$A;fi
setenv mmcpart \$A
setenv rootpart ostree_root=LABEL=otaroot\${labelpre}
setenv bootpart ostree_boot=LABEL=otaboot\${labelpre}
if test -n "\${lat_fit}"; then
 setenv fitconfig wrhv
 setenv fitconfig_r wrhv\${ex}
else
 setenv fitconfig \${fit_config_header}\${fdt_file}
 setenv fitconfig_r \${fit_config_header}\${fdt_file}
fi
setenv mmcpart_r \$B
setenv rootpart_r ostree_root=LABEL=otaroot\${ex}\${labelpre}
setenv bootpart_r ostree_boot=LABEL=otaboot\${ex}\${labelpre}
setenv bpart A

if fatload \${devtype} \${devnum}:1 \${loadaddr} boot_ab_flag;then setenv bpartv \${loadaddr}; if itest.l 42333231 == *\${loadaddr};then setenv bpart B; fi; fi
setenv obpart \${bpart}
setenv cntv 30
setenv bdef 30
setenv switchab if test \\\${bpart} = B\\;then setenv bpart A\\;else setenv bpart B\\;fi
if fatload \${devtype} \${devnum}:1 \$loadaddr boot_cnt 4;then
 if test "\${no_fatwrite}" = yes; then
  \${devcmd} dev \${devnum} && \${devcmd} read \${loadaddr} 0x400 0x1
 fi
 if itest.l 52573030 == *\$loadaddr;then setenv cntv 31
 elif itest.l 52573031 == *\$loadaddr;then setenv cntv 32
 elif itest.l 52573032 == *\$loadaddr;then setenv cntv 33
 elif itest.l 52573033 == *\$loadaddr;then setenv cntv 30;setenv bdef 31;run switchab
 elif itest.l 52573130 == *\$loadaddr;then setenv cntv 31;setenv bdef 31;run switchab
 elif itest.l 52573131 == *\$loadaddr;then setenv cntv 32;setenv bdef 31;run switchab
 elif itest.l 52573132 == *\$loadaddr;then setenv cntv 33;setenv bdef 31;run switchab;fi
else
 setenv cntv 31
fi
mw.l \${initrd_addr} 5257\${bdef}\${cntv}
if test "\${no_fatwrite}" != yes; then
 fatwrite \${devtype} \${devnum}:1 \${initrd_addr} boot_cnt 4
else
 \${devcmd} write \${initrd_addr} 0x400 0x1
fi
if test -n \${oURL}; then
 setenv URL "\${oURL}"
else
 setenv URL "${OSTREE_REMOTE_URL}"
fi
if test -n \${oBRANCH}; then
 setenv BRANCH \${oBRANCH}
else
 setenv BRANCH ${OSTREE_NETINST_BRANCH}
fi
setenv fdtargs
setenv netinstpre
if test -n \${fdt_file}; then
  fatload \${devtype} \${devnum}:1 \${fdt_addr} \${fdt_file}
fi
if test -n \${use_fdtdtb} && test \${use_fdtdtb} -ge 1; then
 fdt addr \${fdt_addr}
 if test \${use_fdtdtb} -ge 2; then
  fdt get value fdtargs /chosen bootargs
 fi
else
 if test -n \${fdt_file}; then
  setenv netinstpre "fatload \${devtype} \${devnum}:1 \${fdt_addr} \${fdt_file};"
 fi
fi
setenv exinargs
setenv instdef "$NETINST_ARGS"
if test -n \${instargs_ext}; then
 echo "Add extra install args \${instargs_ext} from U-Boot shell"
fi
if test -n \${ninstargs}; then
 setenv netinst "\${ninstargs} \${instargs_ext}"
else
 if test -n "\${load_fitimage_addr}"; then
  setenv netinst "\${netinstpre}fatload \${devtype} \${devnum}:1 \${load_fitimage_addr} ${OSTREE_KERNEL}; setenv bootargs \\"\${fdtargs} \${instdef} ${OSTREE_BSP_ARGS} \${instargs_ext}  \${exinargs}\\"; bootm \${load_fitimage_addr}#\${fitconfig}"
 else
  setenv netinst "\${netinstpre}fatload \${devtype} \${devnum}:1 \${loadaddr} ${OSTREE_KERNEL};fatload \${devtype} \${devnum}:1 \${initrd_addr} initramfs; setenv bootargs \\"\${fdtargs} \${instdef} ${OSTREE_BSP_ARGS} \${instargs_ext}  \${exinargs}\\";${OSTREE_UBOOT_CMD} \${loadaddr} \${initrd_addr} \${fdt_addr}"
 fi
fi
setenv autoinst echo "!!!Autostarting network install, you have 5 seconds to reset the board!!!"\;sleep 5\;run netinst
if test "\${no_autonetinst}" != 1 && test -n \${URL} ; then
 if test "\${ex}" != "_b"; then
  if test ! -e \${devtype} \${devnum}:\$mmcpart 1/vmlinuz && test ! -e \${devtype} \${devnum}:\$mmcpart 2/vmlinuz; then
    run autoinst
  fi
 else
  if test ! -e \${devtype} \${devnum}:\$mmcpart 1/vmlinuz && test ! -e \${devtype} \${devnum}:\$mmcpart_r 1/vmlinuz; then
    run autoinst
  fi
 fi
fi
setenv go 0
if test \${no_menu} != yes; then
 if test \${bdef} = 30;then
  setenv bootmenu_0 Boot Primary volume \${bpart}=setenv go 1
  setenv bootmenu_1 Boot Rollback=setenv bdef 31\;run switchab\;setenv go 1
 else
  setenv bootmenu_0 Boot Rollback \${bpart}=\;setenv go 1
  setenv bootmenu_1 Boot Primary volume=setenv bdef 30\;run switchab\;setenv go 1
 fi
 if test -n \${URL} && test \${ninst} = 1; then
  setenv bootmenu_2 Re-install from network=run netinst
 else
  setenv bootmenu_2
 fi
 if bootmenu \${menutimeout}; then echo; else setenv go 1; fi
else
  setenv menu_0_main "Primary volume \${bpart}"
  setenv menu_1_back "Rollback"
  setenv menu_0_back "Rollback \${bpart}"
  setenv menu_1_main "Primary volume"
  if test \${bdef} = 30; then
    setenv menu_0 "\${menu_0_main}"
    setenv menu_1 "\${menu_1_back}"
  else
    setenv menu_0 "\${menu_0_back}"
    setenv menu_1 "\${menu_1_main}"
  fi
  echo
  echo
  echo "  *** U-Boot Boot Menu ***"
  echo
  echo "     * Boot \${menu_0}"
  echo "     * Boot \${menu_1}"
  if test -n \${URL} && test \${ninst} = 1; then
    echo "     * Re-install from ostree_repo"
  fi
  echo "     * U-Boot console"
  echo
  echo
  echo "*** Booting \${menu_0} in 3 seconds, press Ctrl-C to boot next menu"
  echo
  echo
  if sleep 3; then
    setenv go 1
  else
    echo
    echo
    echo "*** Booting \${menu_1} in 3 seconds, press Ctrl-C to boot next menu"
    echo
    echo
    if sleep 3; then
      if test \${bdef} = 30; then
        setenv bdef 31
      else
        setenv bdef 30
      fi
      run switchab
      setenv go 1
    fi
  fi
  if test \${go} = 0 && test -n \${URL} && test \${ninst} = 1; then
    echo
    echo
    echo "*** Re-installing from ostree_repo in 3 seconds, press Ctrl-C to U-boot console"
    echo
    echo
    if sleep 3; then
      if test "\${no_fatwrite}" = yes; then
        mw.l \${initrd_addr} 52573030
        \${devcmd} dev \${devnum} && \${devcmd} write \${initrd_addr} 0x400 0x1
      fi
      run netinst
    else
      setenv netboot ""
      exit
    fi
  fi
fi
if test \${go} = 1; then
if test \${bdef} = 30;then echo "==Booting default \${bpart}==";else echo "==Booting Rollback \${bpart}==";fi
if test \${bpart} = B; then
 setenv mmcpart \$B;
 setenv rootpart ostree_root=LABEL=otaroot\${ex}\${labelpre};
 setenv bootpart ostree_boot=LABEL=otaboot\${ex}\${labelpre};
 if test -n "\${lat_fit}"; then setenv fitconfig wrhv\${ex}; fi
 setenv mmcpart_r \$A;
 setenv rootpart_r ostree_root=LABEL=otaroot\${labelpre};
 setenv bootpart_r ostree_boot=LABEL=otaboot\${labelpre};
 if test -n "\${lat_fit}"; then setenv fitconfig_r wrhv; fi
fi
if test -n \${rollback_f} && test \${rollback_f} = yes;then setenv bdef 31;setenv mmcpart \${mmcpart_r};setenv rootpart \${rootpart_r};setenv bootpart \${bootpart_r};setenv fitconfig \${fitconfig_r};echo "FORCED ROLLBACK";fi
if test \${bdef} = 31 && test "\${ex}" != "_b"; then
setenv ostver 2
else
setenv ostver 1
fi
if test \${skip_script_wd} != yes; then setenv wdttimeout 120000; fi
if test -n "\${load_fitimage_addr}"; then
  setenv loadfit ext4load \${devtype} \${devnum}:\${mmcpart} \${load_fitimage_addr} \${ostver}/vmlinuz
else
  setenv loadkernel ext4load \${devtype} \${devnum}:\${mmcpart} \${loadaddr} \${ostver}/vmlinuz
  setenv loadramdisk ext4load \${devtype} \${devnum}:\${mmcpart} \${initrd_addr} \${ostver}/initramfs
fi
setenv bootargs "\${fdtargs} \${bootpart} ostree=/ostree/\${ostver} \${rootpart} ${OSTREE_CONSOLE} ${OSTREE_BSP_ARGS} \${smp} flux=fluxdata\${labelpre}"
if test "\${no_fatwrite}" = yes; then
 setenv bootargs "\${bootargs} no_fatwrite=yes"
fi

if test ! -n \${use_fdtdtb} || test \${use_fdtdtb} -lt 1; then
 if test -n \${fdt_file}; then
  setenv loaddtb ext4load \${devtype} \${devnum}:\${mmcpart} \${fdt_addr} \${ostver}/\${fdt_file};run loaddtb
 fi
fi
if test -n "\${load_fitimage_addr}"; then
  run loadfit
  bootm \${load_fitimage_addr}#\${fitconfig}
  if test \$? -ne 0; then
    echo "bootm \${load_fitimage_addr}#\${fitconfig} failed";
    if test \${bpart} = A; then
      reset;
    fi
  fi
else
  run loadramdisk
  run loadkernel
  ${OSTREE_UBOOT_CMD} \${loadaddr} \${initrd_addr} \${fdt_addr}
fi
fi
EOF
}

BOOT_SCR_FIT ??= "${@bb.utils.contains('IMAGE_BOOT_FILES', 'boot.itb', 'true', 'false', d)}"
SKIP_SCRIPT_FDT ??= "no"

do_compile() {

    default_dtb="${DEFAULT_DTB}"
    if [ "$default_dtb" = "" ] ; then
        for k in `echo ${KERNEL_DEVICETREE} |grep -v dtbo`; do
            default_dtb="$(basename $k)"
            break;
        done
        if [ "${SKIP_SCRIPT_FDT}" = "no" ]; then
            bbwarn 'DEFAULT_DTB=""'
            bbwarn "boot.scr set to DEFAULT_DTB=$default_dtb"
        fi
    fi
    if [ "${OSTREE_BOOTSCR}" = "fs_links" ] ; then
        bootscr_fs_links
    else
        bootscr_env_import
    fi

    build_date=`date -u +%s`
    sed -i -e  "s/instdate=BUILD_DATE/instdate=@$build_date/" ${WORKDIR}/uEnv.txt
    if [ "${MACHINE}" = "xilinx-zynqmp" ] ; then
        sed -i '3a\setenv loadaddr 0x10000000\nsetenv fdt_addr 0xE0000\nsetenv initrd_addr 0x40000000\nsetenv console  ttyPS0\nsetenv baudrate 115200' ${WORKDIR}/uEnv.txt
    fi
    mkimage -A arm -T script -O linux -d ${WORKDIR}/uEnv.txt ${WORKDIR}/boot.scr
    if ${BOOT_SCR_FIT}; then
        mkimage -A arm -T script -O linux -f auto -C none -d ${WORKDIR}/uEnv.txt ${WORKDIR}/boot.itb
    fi
}

FILES:${PN} += "/boot/boot.scr \
    /boot/boot.itb \
"

do_install() {
    install -d  ${D}/boot
    for f in boot.scr boot.itb; do
        bs=${WORKDIR}/$f
        if [ -e $bs ]; then
            install -Dm 0644 $bs ${D}/boot/
        fi
    done
}

do_deploy() {
    for f in boot.scr boot.itb; do
        bs=${WORKDIR}/$f
        if [ -e $bs ]; then
            install -Dm 0644 $bs ${DEPLOYDIR}/
        fi
    done
}
addtask do_deploy after do_compile before do_build

COMPATIBLE_HOST = "(aarch64|arm).*-linux"

inherit features_check
REQUIRED_DISTRO_FEATURES = "ostree"
