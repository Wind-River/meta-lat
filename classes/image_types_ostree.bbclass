# OSTree deployment

OSTREE_GPG_DEP = "${@'' if (d.getVar('GPG_BIN', True) or '').startswith('/') else 'gnupg-native:do_populate_sysroot pinentry-native:do_populate_sysroot'}"
GPG_BIN ??= ""
GPG_PATH ??= ""
OSTREE_COMMIT_DEV ??= "0"
OSTREE_CREATE_TARBALL ??= "0"

DEPENDS += "${@bb.utils.contains('DISTRO_FEATURES', 'selinux', 'policycoreutils-native', '', d)}"

do_image_ostree[depends] = "ostree-native:do_populate_sysroot \
                        openssl-native:do_populate_sysroot \
			coreutils-native:do_populate_sysroot \
                        wic-tools:do_populate_sysroot \
                        virtual/kernel:do_deploy \
                        ${OSTREE_INITRAMFS_IMAGE}:do_image_complete \
                        ${@'grub:do_populate_sysroot' if d.getVar('OSTREE_BOOTLOADER_INCLUDE', True) == 'grub' else ''} \
                        ${@'virtual/bootloader:do_deploy u-boot-tools-native:do_populate_sysroot' if d.getVar('OSTREE_BOOTLOADER_INCLUDE', True) == 'u-boot' else ''}"

do_prepare_recipe_sysroot[depends] += "${OSTREE_GPG_DEP}"

#export REPRODUCIBLE_TIMESTAMP_ROOTFS ??= "`date --date="20${WRLINUX_YEAR_VERSION}-01-01 +${WRLINUX_WW_VERSION}weeks" +%s`"
export BUILD_REPRODUCIBLE_BINARIES = "1"

export OSTREE_REPO
export OSTREE_BRANCHNAME

export SYSTEMD_USED = "${@oe.utils.ifelse(d.getVar('VIRTUAL-RUNTIME_init_manager', True) == 'systemd', 'true', '')}"
export GRUB_USED = "${@oe.utils.ifelse(d.getVar('OSTREE_BOOTLOADER', True) == 'grub', 'true', '')}"
export FLUXDATA = "${@bb.utils.contains('DISTRO_FEATURES', 'luks', 'luks_fluxdata', 'fluxdata', d)}"

repo_apache_config () {
    local _repo_path
    local _repo_alias

    cd $OSTREE_REPO && _repo_path=$(pwd) && cd -
    _repo_alias="/${OSTREE_OSNAME}/${MACHINE}/"

    echo "* Generating apache2 config fragment for $OSTREE_REPO..."
    (echo "Alias \"$_repo_alias\" \"$_repo_path/\""
     echo ""
     echo "<Directory $_repo_path>"
     echo "    Options Indexes FollowSymLinks"
     echo "    Require all granted"
     echo "</Directory>") > ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.http.conf
}

python ostree_check_rpm_public_key () {
    gpg_path = d.getVar('GPG_PATH', True)
    if not gpg_path:
        gpg_path = d.getVar('TMPDIR', True) + '/.gnupg'

    if not os.path.exists(gpg_path):
        status, output = oe.utils.getstatusoutput('mkdir -m 0700 -p %s' % gpg_path)
        if status:
            raise bb.build.FuncFailed('Failed to create gpg keying %s: %s' %
                                      (gpg_path, output))
    gpg_bin = d.getVar('GPG_BIN', True) or \
              bb.utils.which(os.getenv('PATH'), 'gpg')
    gpg_keyid = d.getVar('OSTREE_GPGID', True) or ''
    if gpg_keyid == "":
        return

    # Check OSTREE_GPG_NAME and OSTREE_GPG_PASSPHRASE
    cmd = "%s --homedir %s --list-keys \"%s\"" % \
            (gpg_bin, gpg_path, gpg_keyid)
    bb.note(cmd)
    status, output = oe.utils.getstatusoutput(cmd)
    if not status:
        return

    # Import RPM_GPG_NAME if not found
    gpg_key = d.getVar('OSTREE_GPGDIR', True) + '/' + 'RPM-GPG-PRIVKEY-' + gpg_keyid
    cmd = '%s --batch --homedir %s --passphrase %s --import "%s"' % \
            (gpg_bin, gpg_path, d.getVar('OSTREE_GPG_PASSPHRASE', True), gpg_key)
    bb.note(cmd)
    status, output = oe.utils.getstatusoutput(cmd)
    if status:
        bb.fatal('Could not import GPG key for ostree signing: %s' % output)
}
ostree_check_rpm_public_key[lockfiles] = "${TMPDIR}/gpg_key.lock"
do_package_write_rpm[prefuncs] += "ostree_check_rpm_public_key"
do_rootfs[prefuncs] += "ostree_check_rpm_public_key"

selinux_set_labels (){
    touch ${OSTREE_ROOTFS}/usr/${sysconfdir}/selinux/fixfiles_exclude_dirs
    echo "/ostree" >> ${OSTREE_ROOTFS}/usr/${sysconfdir}/selinux/fixfiles_exclude_dirs
    echo "/sysroot" >> ${OSTREE_ROOTFS}/usr/${sysconfdir}/selinux/fixfiles_exclude_dirs
    if [ -f ${OSTREE_ROOTFS}/.autorelabel ]; then
        mv ${OSTREE_ROOTFS}/.autorelabel ${OSTREE_ROOTFS}/usr/${sysconfdir}
    fi
    sed -i '\/bin\/rm/a \\t/usr/sbin/setfiles -F -q  /etc/selinux/wr-mls/contexts/files/file_contexts /etc' ${OSTREE_ROOTFS}/usr/bin/selinux-autorelabel.sh
    sed -i "s/.autorelabel/etc\/.autorelabel/g" ${OSTREE_ROOTFS}/usr/bin/selinux-autorelabel.sh

    POL_TYPE=$(sed -n -e "s&^SELINUXTYPE[[:space:]]*=[[:space:]]*\([0-9A-Za-z_]\+\)&\1&p" ${OSTREE_ROOTFS}/usr/${sysconfdir}/selinux/config)
    if ! setfiles -m -r ${OSTREE_ROOTFS} ${OSTREE_ROOTFS}/usr/${sysconfdir}/selinux/${POL_TYPE}/contexts/files/file_contexts ${OSTREE_ROOTFS}
    then
        bb.fatal "selinux_set_labels error."
        exit 0
    fi
}

create_tarball_and_ostreecommit[vardepsexclude] = "DATETIME"
create_tarball_and_ostreecommit() {
	local _image_basename=$1
	local _timestamp=$2

	# The timestamp format of ostree requires
	_timestamp=`LC_ALL=C date --date=@$_timestamp`

	if [ ${OSTREE_CREATE_TARBALL} = "1" ] ; then
		# Create a tarball that can be then commited to OSTree repo
		OSTREE_TAR=${DEPLOY_DIR_IMAGE}/${_image_basename}-${MACHINE}-${DATETIME}.rootfs.ostree.tar.bz2
		tar -C ${OSTREE_ROOTFS} --xattrs --xattrs-include='*' -cjf ${OSTREE_TAR} .
		sync

		ln -snf ${_image_basename}-${MACHINE}-${DATETIME}.rootfs.ostree.tar.bz2 \
		    ${DEPLOY_DIR_IMAGE}/${_image_basename}-${MACHINE}.rootfs.ostree.tar.bz2
	fi

	# Commit the result
	if [ -z "${OSTREE_GPGID}" ]; then
		bbwarn "You are using an unsupported configuration by using ostree repo without gpg. " \
		       "This usually indicates a failure to find /usr/bin/gpg, " \
		       "or you tried to use an invalid GPG database.  " \
		       "It could also be possible that OSTREE_GPGID, OSTREE_GPG_PASSPHRASE, " \
		       "OSTREE_GPGDIR has a bad value."
		ostree --repo=${OSTREE_REPO_TEMP} commit \
			--tree=dir=${OSTREE_ROOTFS} \
			--skip-if-unchanged \
			--branch=${_image_basename} \
			--timestamp="${_timestamp}" \
			--subject="Commit-id: ${_image_basename}-${MACHINE}-${DATETIME}"
		# Pull new commmit into old repo
		flock ${OSTREE_REPO}.lock ostree --repo=${OSTREE_REPO} pull-local ${OSTREE_REPO_TEMP} ${_image_basename}
	else
		# Setup gpg key for signing
		if [ -n "${OSTREE_GPGID}" ] && [ -n "${OSTREE_GPG_PASSPHRASE}" ] && [ -n "$gpg_path" ] ; then
			gpg_ver=`$gpg_bin --version | head -1 | awk '{ print $3 }' | awk -F. '{ print $1 }'`
			echo '#!/bin/bash' > ${WORKDIR}/gpg
			echo 'exarg=""' >> ${WORKDIR}/gpg
			if [ "$gpg_ver" = "1" ] ; then
				# GPGME has to be tricked into running a helper script to provide a passphrase when using gpg 1
				echo 'echo "$@" |grep -q batch && exarg="--passphrase ${OSTREE_GPG_PASSPHRASE}"' >> ${WORKDIR}/gpg
			elif [ "$gpg_ver" = "2" ] ; then
				gpg_connect=$(dirname $gpg_bin)/gpg-connect-agent
				if [ ! -f $gpg_connect ] ; then
					bb.fatal "ERROR Could not locate gpg-connect-agent at: $gpg_connect"
				fi
				if [ -f "$gpg_path/gpg-agent.conf" ] ; then
					if ! grep -q allow-loopback-pin "$gpg_path/gpg-agent.conf" ; then
						echo allow-loopback-pinentry >> "$gpg_path/gpg-agent.conf"
						$gpg_connect --homedir $gpg_path reloadagent /bye
					fi
				else
					echo allow-loopback-pinentry > "$gpg_path/gpg-agent.conf"
					$gpg_connect --homedir $gpg_path reloadagent /bye
				fi
				$gpg_bin --homedir=$gpg_path -o /dev/null -u "${OSTREE_GPGID}" --pinentry=loopback --passphrase ${OSTREE_GPG_PASSPHRASE} -s /dev/null
			fi
			echo "exec $gpg_bin \$exarg \$@" >> ${WORKDIR}/gpg
			chmod 700 ${WORKDIR}/gpg
		fi
		if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'selinux', 'Y', '', d)}" ]; then
			PATH="${WORKDIR}:$PATH" ostree --repo=${OSTREE_REPO_TEMP} commit \
				--tree=dir=${OSTREE_ROOTFS} \
				--selinux-policy ${OSTREE_ROOTFS} \
				--skip-if-unchanged \
				--gpg-sign="${OSTREE_GPGID}" \
				--gpg-homedir=$gpg_path \
				--branch=${_image_basename} \
				--timestamp="${_timestamp}" \
				--subject="Commit-id: ${_image_basename}-${MACHINE}-${DATETIME}"
		else
			PATH="${WORKDIR}:$PATH" ostree --repo=${OSTREE_REPO_TEMP} commit \
				--tree=dir=${OSTREE_ROOTFS} \
				--skip-if-unchanged \
				--gpg-sign="${OSTREE_GPGID}" \
				--gpg-homedir=$gpg_path \
				--branch=${_image_basename} \
				--timestamp="${_timestamp}" \
				--subject="Commit-id: ${_image_basename}-${MACHINE}-${DATETIME}"
		fi
		# Pull new commmit into old repo
		flock ${OSTREE_REPO}.lock ostree --repo=${OSTREE_REPO} pull-local ${OSTREE_REPO_TEMP} ${_image_basename}

		gpgconf=$(dirname $gpg_bin)/gpgconf
		if [ ! -f $gpgconf ] ; then
			bb.fatal "ERROR Could not find $gpgconf"
		fi
		GNUPGHOME="$gpg_path" flock ${OSTREE_REPO}.lock $gpgconf --kill gpg-agent
        fi
}

IMAGE_CMD:ostree () {
	gpg_path="${GPG_PATH}"
	if [ -z "$gpg_path" ] ; then
		gpg_path="${TMPDIR}/.gnupg"
	fi
	gpg_bin="${GPG_BIN}"
	if [ -z "$gpg_bin" ] ; then
		gpg_bin=`which gpg`
	fi
	if [ "${gpg_bin#/}" = "$gpg_bin" ] ; then
		bb.fatal "The GPG_BIN variable must be an absolute path to the gpg binary"
	fi

	if [ -z "$OSTREE_REPO" ]; then
		bbfatal "OSTREE_REPO should be set in your local.conf"
	fi

	if [ -z "$OSTREE_BRANCHNAME" ]; then
		bbfatal "OSTREE_BRANCHNAME should be set in your local.conf"
	fi

	OSTREE_REPO_TEMP="${WORKDIR}/ostree_repo.temp.$$"
	OSTREE_ROOTFS=`mktemp -du ${WORKDIR}/ostree-root-XXXXX`
	cp -a ${IMAGE_ROOTFS} ${OSTREE_ROOTFS}
	if [ "${@oe.types.boolean(d.getVar('IS_FMU_ENABLED'))}" = "True" ]; then
		rm -rf ${OSTREE_ROOTFS}${APP_DIRECTORY}/*
	fi
	chmod a+rx ${OSTREE_ROOTFS}
	sync

	cd ${OSTREE_ROOTFS}

	# Create sysroot directory to which physical sysroot will be mounted
	mkdir sysroot
	ln -sf sysroot/ostree ostree

	rm -rf tmp/*
	ln -sf sysroot/tmp tmp

	mkdir -p usr/rootdirs

	mv etc usr/
	# Implement UsrMove
	dirs="bin sbin lib lib64"

	for dir in ${dirs} ; do
		if [ -d ${dir} ] && [ ! -L ${dir} ] ; then 
			mv ${dir} usr/rootdirs/
			rm -rf ${dir}
			ln -sf usr/rootdirs/${dir} ${dir}
		fi
	done
	
	if [ -n "$SYSTEMD_USED" ]; then
		mkdir -p usr/etc/tmpfiles.d
		tmpfiles_conf=usr/etc/tmpfiles.d/00ostree-tmpfiles.conf
		echo "d /var/rootdirs 0755 root root -" >>${tmpfiles_conf}
		# disable the annoying logs on the console
		echo "w /proc/sys/kernel/printk - - - - 3" >> ${tmpfiles_conf}
	else
		mkdir -p usr/etc/init.d
		tmpfiles_conf=usr/etc/init.d/tmpfiles.sh
		echo '#!/bin/sh' > ${tmpfiles_conf}
		echo "mkdir -p /var/rootdirs; chmod 755 /var/rootdirs" >> ${tmpfiles_conf}

		ln -s ../init.d/tmpfiles.sh usr/etc/rcS.d/S20tmpfiles.sh
	fi

	# Preserve data in /home to be later copied to /var/home by
	#   sysroot generating procedure
	mkdir -p usr/homedirs
	if [ -d "home" ] && [ ! -L "home" ]; then
		mv home usr/homedirs/home
		mkdir var/home
		ln -sf var/home home
		echo "d /var/home 0755 root root -" >>${tmpfiles_conf}
	fi

	echo "d /var/rootdirs/opt 0755 root root -" >>${tmpfiles_conf}
	if [ -d opt ]; then
		mkdir -p usr/rootdirs/opt
		for dir in `ls opt`; do
			mv opt/$dir usr/rootdirs/opt/
			echo "L /opt/$dir - - - - /usr/rootdirs/opt/$dir" >>${tmpfiles_conf}
		done
	fi
	rm -rf opt
	ln -sf var/rootdirs/opt opt

	if [ -d var/lib/rpm ]; then
	    mkdir -p usr/rootdirs/var/lib/
	    mv var/lib/rpm usr/rootdirs/var/lib/
	    echo "L /var/lib/rpm - - - - /usr/rootdirs/var/lib/rpm" >>${tmpfiles_conf}
	fi
	if [ -d var/lib/dnf ]; then
	    mkdir -p usr/rootdirs/var/lib/
	    mv var/lib/dnf usr/rootdirs/var/lib/
	    echo "L /var/lib/dnf - - - - /usr/rootdirs/var/lib/dnf " >>${tmpfiles_conf}
	fi

	# Move persistent directories to /var
	dirs="mnt media srv"

	for dir in ${dirs}; do
		if [ -d ${dir} ] && [ ! -L ${dir} ]; then
			if [ "$(ls -A $dir)" ]; then
				bbwarn "Data in /$dir directory is not preserved by OSTree. Consider moving it under /usr"
			fi

			if [ -n "$SYSTEMD_USED" ]; then
				echo "d /var/rootdirs/${dir} 0755 root root -" >>${tmpfiles_conf}
			else
				echo "mkdir -p /var/rootdirs/${dir}; chown 755 /var/rootdirs/${dir}" >>${tmpfiles_conf}
			fi
			rm -rf ${dir}
			ln -sf var/rootdirs/${dir} ${dir}
		fi
	done

	if [ -d root ] && [ ! -L root ]; then
        	if [ "$(ls -A root)" ]; then
                	bberror "Data in /root directory is not preserved by OSTree."
		fi

		if [ -n "$SYSTEMD_USED" ]; then
                       echo "d /var/rootdirs/root 0755 root root -" >>${tmpfiles_conf}
		else
                       echo "mkdir -p /var/rootdirs/root; chown 755 /var/rootdirs/root" >>${tmpfiles_conf}
		fi

		rm -rf root
		ln -sf var/rootdirs/root root
	fi

	# deploy SOTA credentials
	if [ -n "${SOTA_AUTOPROVISION_CREDENTIALS}" ]; then
		EXPDATE=`openssl pkcs12 -in ${SOTA_AUTOPROVISION_CREDENTIALS} -password "pass:" -nodes 2>/dev/null | openssl x509 -noout -enddate | cut -f2 -d "="`

		if [ `date +%s` -ge `date -d "${EXPDATE}" +%s` ]; then
			bberror "Certificate ${SOTA_AUTOPROVISION_CREDENTIALS} has expired on ${EXPDATE}"
		fi

		mkdir -p var/sota
		cp ${SOTA_AUTOPROVISION_CREDENTIALS} var/sota/sota_provisioning_credentials.p12
		if [ -n "${SOTA_AUTOPROVISION_URL_FILE}" ]; then
			export SOTA_AUTOPROVISION_URL=`cat ${SOTA_AUTOPROVISION_URL_FILE}`
		fi
		echo "SOTA_GATEWAY_URI=${SOTA_AUTOPROVISION_URL}" > var/sota/sota_provisioning_url.env
	fi


	# Creating boot directories is required for "ostree admin deploy"

	mkdir -p boot/loader.0
	mkdir -p boot/loader.1
	ln -sf boot/loader.0 boot/loader
	
	checksum=`sha256sum ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} | cut -f 1 -d " "`

#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} boot/vmlinuz-${checksum}
#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT} boot/initramfs-${checksum}

        #deploy the device tree file 
        mkdir -p usr/lib/ostree-boot
        cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} usr/lib/ostree-boot/vmlinuz-${checksum}
        cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT} usr/lib/ostree-boot/initramfs-${checksum}
	if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'Y', '', d)}" ]; then
		if [ -f ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.p7b ] ; then
			cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.p7b usr/lib/ostree-boot/vmlinuz.p7b
			cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT}.p7b usr/lib/ostree-boot/initramfs.p7b
		fi
		if [ -f ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.sig ] ; then
			cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.sig usr/lib/ostree-boot/vmlinuz.sig
			cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT}.sig usr/lib/ostree-boot/initramfs.sig
		fi
	fi
        if [ -d boot/efi ]; then
	   	cp -a boot/efi usr/lib/ostree-boot/
	fi

        if [ -f ${DEPLOY_DIR_IMAGE}/uEnv.txt ]; then
		cp ${DEPLOY_DIR_IMAGE}/uEnv.txt usr/lib/ostree-boot/
        fi

        if [ -f ${DEPLOY_DIR_IMAGE}/boot.scr ]; then
		cp ${DEPLOY_DIR_IMAGE}/boot.scr usr/lib/ostree-boot/boot.scr
		# Modify the boot.scr
		if [ -e usr/lib/ostree-boot/boot.scr ] ; then
			tail -c+73 usr/lib/ostree-boot/boot.scr > usr/lib/ostree-boot/boot.scr.raw
			if [ -e /bin/perl ] ; then
				/bin/perl -p -i -e "s#^( *setenv BRANCH) .*#\$1 ${OSTREE_BRANCHNAME}# if (\$_ !~ /oBRANCH/) " usr/lib/ostree-boot/boot.scr.raw
			else
				/usr/bin/perl -p -i -e "s#^( *setenv BRANCH) .*#\$1 ${OSTREE_BRANCHNAME}# if (\$_ !~ /oBRANCH/) " usr/lib/ostree-boot/boot.scr.raw
			fi
			mkimage -A arm -T script -O linux -d usr/lib/ostree-boot/boot.scr.raw usr/lib/ostree-boot/boot.scr
			if [ -f $DEPLOY_DIR_IMAGE/boot.itb ]; then
				mkimage -A arm -T script -O linux -f auto -C none -d usr/lib/ostree-boot/boot.scr.raw usr/lib/ostree-boot/boot.itb
			fi
			rm -f usr/lib/ostree-boot/boot.scr.raw
		fi
		mkdir -p boot
		cp usr/lib/ostree-boot/boot.scr boot/
        fi

        for i in ${KERNEL_DEVICETREE}; do
		if [ -f ${DEPLOY_DIR_IMAGE}/$(basename $i) ]; then
			if [ "$(dirname $i)" = "overlays" ] ; then
				[ ! -d usr/lib/ostree-boot/overlays ] && mkdir -p usr/lib/ostree-boot/overlays
				cp ${DEPLOY_DIR_IMAGE}/$(basename $i) usr/lib/ostree-boot/overlays
			else
				cp ${DEPLOY_DIR_IMAGE}/$(basename $i) usr/lib/ostree-boot/
			fi
		fi
        done 

	#deploy the GPG pub key
	if [ -n "${OSTREE_GPGID}" ]; then
		if [ -f $gpg_path/pubring.gpg ]; then
			cp $gpg_path/pubring.gpg usr/share/ostree/trusted.gpg.d/pubring.gpg
		fi
		if [ -f $gpg_path/pubring.kbx ]; then
			cp $gpg_path/pubring.kbx usr/share/ostree/trusted.gpg.d/pubkbx.gpg
		fi
	fi

#        cp ${DEPLOY_DIR_IMAGE}/${MACHINE}.dtb usr/lib/ostree-boot
        touch usr/lib/ostree-boot/.ostree-bootcsumdir-source

	# Copy image manifest
	cat ${IMAGE_MANIFEST} | cut -d " " -f1,3 > usr/package.manifest

	# add the required mount
	echo "LABEL=otaboot     /boot    auto   defaults 0 0" >>usr/etc/fstab
        if [ -n "${GRUB_USED}" ]; then
	    echo "LABEL=otaefi     /boot/efi    auto   ro 0 0" >>usr/etc/fstab
        fi
	echo "LABEL=fluxdata	 /var    auto   defaults 0 0" >>usr/etc/fstab
	if [ "${@oe.types.boolean(d.getVar('IS_FMU_ENABLED'))}" = "True" ]; then
		echo "LABEL=apps    /apps  auto   defaults 0 0" >>usr/etc/fstab
	fi

	# Install a trap handler to remove the temporary ostree_repo
	trap "rm -rf ${OSTREE_REPO_TEMP}" EXIT
	cd ${WORKDIR}

	rm -rf ${OSTREE_REPO_TEMP}
	ostree --repo=${OSTREE_REPO_TEMP} init --mode=bare
	if [ ! -d ${OSTREE_REPO} ]; then
		flock ${OSTREE_REPO}.lock ostree --repo=${OSTREE_REPO} init --mode=archive-z2
	else
		ostree pull-local --repo=${OSTREE_REPO_TEMP} ${OSTREE_REPO} ${OSTREE_BRANCHNAME} || (exit 0)
	fi

	# Preserve OSTREE_BRANCHNAME for future information
	mkdir -p ${OSTREE_ROOTFS}/usr/share/sota/

	if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'selinux', 'Y', '', d)}" ]; then
		selinux_set_labels
	fi

	timestamp=`date +%s`
	if [ "${OSTREE_COMMIT_DEV}" = "1" ] ; then
		echo -n "${OSTREE_BRANCHNAME}-dev" > ${OSTREE_ROOTFS}/usr/share/sota/branchname
		create_tarball_and_ostreecommit "${OSTREE_BRANCHNAME}-dev" "$timestamp"
	fi

	if [ "${OSTREE_NORPMDATA}" = 1 ] || [ ! -e ${OSTREE_ROOTFS}/usr/bin/rpm ] ; then
		# Clean up package management data for factory deploy
		rm -rf ${OSTREE_ROOTFS}/usr/rootdirs/var/lib/rpm/*
		rm -rf ${OSTREE_ROOTFS}/usr/rootdirs/var/lib/dnf/*
	fi

	# Make factory older than development which is helpful for ostree admin upgrade
	timestamp=`expr $timestamp - 1`
	echo -n "${OSTREE_BRANCHNAME}" > ${OSTREE_ROOTFS}/usr/share/sota/branchname
	create_tarball_and_ostreecommit "${OSTREE_BRANCHNAME}" "$timestamp"

	# Cleanup and remove trap handler
	rm -rf ${OSTREE_REPO_TEMP}
	trap - EXIT

	flock ${OSTREE_REPO}.lock ostree summary -u --repo=${OSTREE_REPO}
	repo_apache_config

	rm -rf ${OSTREE_ROOTFS}
}

python __anonymous() {
    gpg_path = d.getVar('GPG_PATH', True)
    if not gpg_path:
        gpg_path = d.getVar('TMPDIR', True) + '/.gnupg'
    if len(gpg_path) > 80:
        msg =  "The default GPG_PATH '%s'\n" % gpg_path
        msg += "of %d characters is too long.\n" % len(gpg_path)
        msg += "Due to GPG homedir path length limit, please set GPG_PATH shorter than 80 characters"
        raise bb.parse.SkipRecipe(msg)
}

def get_fluxdata_size(d):
    import subprocess

    overhead_factor = float(d.getVar("IMAGE_OVERHEAD_FACTOR"))
    fluxdata_dir = d.expand("${WORKDIR}/rootfs_ota_var")
    output = subprocess.check_output(["du", "-ks", fluxdata_dir])
    size_kb = int(output.split()[0])
    base_size = size_kb * overhead_factor
    bb.debug(1, '%f = %d * %f' % (base_size, size_kb, overhead_factor))

    if base_size != int(base_size):
        base_size = int(base_size + 1)
    else:
        base_size = int(base_size)

    # Extra 512MB for /var
    base_size += 512*1024
    bb.debug(1, 'returning %d' % (base_size))
    return base_size

def get_apps_size(d):
    import subprocess

    overhead_factor = float(d.getVar("IMAGE_OVERHEAD_FACTOR"))
    fluxdata_dir = d.expand("${WORKDIR}/rootfs_ota_apps")
    output = subprocess.check_output(["du", "-ks", fluxdata_dir])
    size_kb = int(output.split()[0])
    base_size = size_kb * overhead_factor
    bb.debug(1, '%f = %d * %f' % (base_size, size_kb, overhead_factor))

    if base_size != int(base_size):
        base_size = int(base_size + 1)
    else:
        base_size = int(base_size)

    # Extra 512MB for /apps
    base_size += 512*1024
    bb.debug(1, 'returning %d' % (base_size))
    return base_size

python do_write_wks_template:prepend() {
    fluxdata_dir = d.expand("${WORKDIR}/rootfs_ota_var")
    if os.path.exists(fluxdata_dir):
        root_size = d.getVar("OSTREE_WKS_ROOT_SIZE") or None
        if root_size is None:
            # KB --> MB
            _size = get_rootfs_size(d)//1024 + 1
            root_size = "--size=%dM --overhead-factor 1" % _size
        d.setVar('OSTREE_WKS_ROOT_SIZE', root_size)

        if oe.types.boolean(d.getVar('IS_FMU_ENABLED')):
            apps_size = d.getVar("OSTREE_WKS_APPS_SIZE") or None
            if apps_size is None:
                _size = get_apps_size(d)
                apps_size = "--size=%dM --overhead-factor 1" % _size
            d.setVar('OSTREE_WKS_APPS_SIZE', apps_size)

        fluxdata_size = d.getVar("OSTREE_WKS_FLUX_SIZE") or None
        if fluxdata_size is None:
            # KB --> MB
            _size = get_fluxdata_size(d)//1024 + 1
            fluxdata_size = "--size=%dM --overhead-factor 1" % _size
        d.setVar('OSTREE_WKS_FLUX_SIZE', fluxdata_size)
}

# Need add do_write_wks_template firstly, otherwise
# do_write_wks_template:prepend doesn't work
python () {
    if d.getVar('USING_WIC'):
        wks_file_u = d.getVar('WKS_FULL_PATH', False)
        wks_file = d.expand(wks_file_u)
        base, ext = os.path.splitext(wks_file)
        if ext == '.in' and os.path.exists(wks_file):
            bb.build.addtask('do_write_wks_template', 'do_image_wic', 'do_image_otaimg', d)
}
