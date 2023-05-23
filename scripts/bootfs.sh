#!/bin/bash
#  This script will build a mini bootstrap image for a target system.
#
#* Copyright (c) 2019 Jason Wessel - Wind River Systems, Inc.
#* 
#* This program is free software; you can redistribute it and/or modify
#* it under the terms of the GNU General Public License version 2 as
#* published by the Free Software Foundation.
#* 
#* This program is distributed in the hope that it will be useful,
#* but WITHOUT ANY WARRANTY; without even the implied warranty of
#* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#* See the GNU General Public License for more details.
#* 
#* You should have received a copy of the GNU General Public License
#* along with this program; if not, write to the Free Software
#* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA


ENVFILE="auto"
PARTSIZE=${PARTSIZE=256}
COMPRESS="${COMPRESS=1}"
DO_BUILD_BOOTFS=1
MODIFY_BOOT_SCR=1
EXTRA_INST_ARGS=""
EXTRA_KERNEL_ARGS=""
INST_FLUX=1
INST_URL=""
INST_BRANCH=""
INST_DEV=""
INSTL=/sysroot/boot/efi/ostree_repo
SKIP_WIC=0
OUTDIR=$PWD/bootfs
LOCAL_REPO=0
LOCAL_REPO_DIR=""
UUID="auto"

usage() {
        cat<<EOF
usage: `basename $0` [args]

This command will build a small boot image which can be used for
deployment with OSTree.

Local Install Options:
 -L       Create an image with a copy of the OSTree repository
          from the deploy area, it will be used to for the initial
          device install
 -l <dir> Use a different directory for an install from a local
          repository
 -l 0     Create a local repository with only the deploy branch

Network Install options:
 -b <branch>  branch to use for net install instbr=
 -u <url>     url to use for net install insturl=
 -d <device>  device to use for net install instdev=
 -a <args>    Additional kernel boot argument for the install
 -k <args>    Additional kernel boot argument to installed image

Image Creation Options:
 -B         Skip build of the bootfs directory and use what ever is in there
 -e <file>  env file for reference image e.g. core-image-minimal.env
 -n         Turn off the commpression of the image
 -N         Do not modify the boot.scr file on the image
 -s <#>     Size in MB of the boot partition (default 256)
            Setting this to zero will make the partition as small as possible
 -U <UUID>  Use a specific UUID rather than generating one for the install media
 -w         Skip wic disk creation

EOF
        exit 0
}

fatal() {
	echo "$*"
	exit 1
}

modify_boot_scr() {
	if [ ! -e $OUTDIR/boot.scr ] ; then
		return
	fi
	# Strip off original header
	tail -c+73 $OUTDIR/boot.scr > $OUTDIR/boot.scr.raw
	if [ $LOCAL_REPO = 1 ] ; then
		EXTRA_INST_ARGS="$EXTRA_INST_ARGS instl=$INSTL"
	fi
	extra_console=""
	for console in `echo $EXTRA_INST_ARGS | grep -o "console=[^ ]*"`;do
	    extra_console="$extra_console $console"
	done

	sed -i -e "/^setenv bootargs/s/console=[^ ^\"]*//g" \
	       -e "s/^\(setenv bootargs .*\)\"$/\1 ${OSTREE_CONSOLE}${extra_console} ${EXTRA_KERNEL_ARGS}\"/g" \
	    $OUTDIR/boot.scr.raw

	sed -i -e "/^setenv instdef/s/console=[^ ^\"]*//g" \
	       -e "s/^\(setenv instdef .*\)\"$/\1 ${OSTREE_CONSOLE}\"/g" \
	    $OUTDIR/boot.scr.raw

	sed -i -e "s#^\(setenv exinargs\).*#\1 $EXTRA_INST_ARGS#" $OUTDIR/boot.scr.raw

	perl -p -i -e "s#^( *setenv BRANCH) .*#\$1 $INST_BRANCH# if (\$_ !~ /oBRANCH/) " $OUTDIR/boot.scr.raw
	perl -p -i -e "s#Autostarting network install#Autostarting ERASE and INSTALL#" $OUTDIR/boot.scr.raw
	perl -p -i -e "s#Re-install from network=run#Re-install from ostree_repo=run#" $OUTDIR/boot.scr.raw
	perl -p -i -e "s#instab=[^ ]* #instab=$OSTREE_USE_AB #" $OUTDIR/boot.scr.raw

	iurl="$OSTREE_REMOTE_URL"
	if [ "$INST_URL" != "" ] ; then
		iurl="$INST_URL"
	fi
	perl -p -i -e "s#^( *setenv URL) .*#\$1 $iurl# if (\$_ !~ /oURL/) " $OUTDIR/boot.scr.raw

	if [ ${UUID} != "" ]; then
		fromdev="PUUID=_PUUID_,UUID=_UUID_"
		fromdev=$(echo "$fromdev" |sed "s/_PUUID_/${UUID}/g")
		fromdev=$(echo "$fromdev" |sed "s/_UUID_/$(echo ${UUID:0:4}-${UUID:4:4}|sed 's/[a-z]/\U&/g')/g")

		idev="PUUID=_PUUID_,UUID=_UUID_"
		idev=$(echo "$idev" |sed "s/_PUUID_/${UUID}/g")
		idev=$(echo "$idev" |sed "s/_UUID_/$(echo ${UUID:0:4}-${UUID:4:4}|sed 's/[a-z]/\U&/g')/g")
		perl -p -i -e "s#instdev=.*?([ \"])#instdev=$idev fromdev=$fromdev\$1#" $OUTDIR/boot.scr.raw
	fi

	if [ -n "$INST_DEV" ] ; then
		perl -p -i -e "s#instdev=.*?([ \"])#instdev=$INST_DEV\$1#" $OUTDIR/boot.scr.raw
	fi

	FOUND_ARGS=`cat $OUTDIR/boot.scr.raw | grep ^setenv\ instdef | sed -e 's/^setenv instdef "//;s/"$//;'`
	echo "Using \$BRANCH = $INST_BRANCH"
	echo "Using \$URL = $iurl"
	bootargs="$FOUND_ARGS $EXTRA_INST_ARGS"
	echo "Using bootargs: $bootargs"
	which mkimage > /dev/null
	if [ $? != 0 ] ; then
		fatal "ERROR: Could not locate mkimage utility"
	fi
	mkimage -A arm -T script -O linux -d $OUTDIR/boot.scr.raw $OUTDIR/boot.scr || fatal "ERROR: mkimage failed"
	# Update the existing FIT image as boot.scr
	if [ -e $OUTDIR/boot.itb ]; then
		mkimage -A arm -T script -O linux -f auto -C none -d $OUTDIR/boot.scr.raw $OUTDIR/boot.itb
	fi
	rm -f $OUTDIR/boot.scr.raw
}

do_cp_and_sig() {
	cp "$1" "$2"
	if [ -e "$1.sig" ] ; then
		cp "$1.sig" "$2.sig"
	fi
	if [ -e "$1.p7b" ] ; then
		cp "$1.p7b" "$2.p7b"
	fi
}

sign_grub() {
	GRUB_KEY=`mktemp -d`
	chmod 700 $GRUB_KEY
	echo allow-loopback-pinentry > $GRUB_KEY/gpg-agent.conf
	gpg --batch  --passphrase "$BOOT_GPG_PASSPHRASE" --pinentry-mode loopback --homedir $GRUB_KEY --import "$BOOT_KEYS_DIR/BOOT-GPG-PRIVKEY-$BOOT_GPG_NAME" || fatal "Error importing signing key"
	for e in `ls $OUTDIR/EFI/BOOT/grub.cfg`; do
		echo Signing: $e
		rm -f $e.sig
		echo "$BOOT_GPG_PASSPHRASE" | gpg --pinentry-mode loopback --homedir $GRUB_KEY -u "$BOOT_GPG_NAME" --batch --detach-sign --passphrase-fd 0 $e || fatal "Error signing $e"
	done
	rm -rf $GRUB_KEY
}

create_grub_cfg() {
	if [ "$grubcfg" != "" ] ; then
		echo "Using grub.cfg: $grubcfg"
		cp $grubcfg $OUTDIR/EFI/BOOT/grub.cfg
		return
	fi
	if [ ${UUID} != "" ]; then
	    idev="PUUID=_PUUID_,UUID=_UUID_"
	else
	    idev="LABEL=instboot,LABEL=boot,LABEL=otaefi"
	fi
	if [ "$INST_DEV" != "" ] ; then
		idev=$INST_DEV
	fi
	if [ ${UUID} != "" ]; then
	    fromdev="PUUID=_PUUID_,UUID=_UUID_"
	    fromdev=$(echo "$fromdev" |sed "s/_PUUID_/${UUID}/g")
	    fromdev=$(echo "$fromdev" |sed "s/_UUID_/$(echo ${UUID:0:4}-${UUID:4:4}|sed 's/[a-z]/\U&/g')/g")
	    idev=$(echo "$idev" |sed "s/_PUUID_/${UUID}/g")
	    idev=$(echo "$idev" |sed "s/_UUID_/$(echo ${UUID:0:4}-${UUID:4:4}|sed 's/[a-z]/\U&/g')/g")
	fi
	ostree_dir=${DEPLOY_DIR_IMAGE}/ostree_repo
	iurl="$OSTREE_REMOTE_URL"
	if [ "$INST_URL" != "" ] ; then
		iurl="$INST_URL"
	fi
	bootargs="${OSTREE_CONSOLE} rdinit=/install instdev=$idev instname=${OSTREE_OSNAME} instbr=$INST_BRANCH insturl=$iurl instab=$OSTREE_USE_AB instsf=1 $EXTRA_INST_ARGS kernelparams=$EXTRA_KERNEL_ARGS fromdev=$fromdev"

	grep -q preempt-rt ${DEPLOY_DIR_IMAGE}/bzImage
	if [ $? -eq 0 ]; then
		bootargs="$bootargs efi=runtime"
	fi

	if [ "$OSTREE_FLUX_PART" = "luksfluxdata" -a "$EXTRA_INST_ARGS" = "${EXTRA_INST_ARGS/LUKS/}" ] ; then
		bootargs="$bootargs LUKS=1"
	fi
	if [ $LOCAL_REPO = 1 ] ; then
		bootargs="$bootargs instl=$INSTL"
	fi
	echo "Using bootargs: $bootargs"
	cat<<EOF> $OUTDIR/EFI/BOOT/grub.cfg
if [ "\${boot_part}" = "" ] ; then
  set default="0"
  set timeout=3
  set color_normal='light-gray/black'
  set color_highlight='light-green/blue'

  get_efivar -f uint8 -s secured SecureBoot
  if [ "\${secured}" = "1" ]; then
    # Enable user authentication to make grub unlockable
    set superusers="$OSTREE_GRUB_USER"
     password_pbkdf2 $OSTREE_GRUB_USER $(cat $OSTREE_GRUB_PW_FILE)
  else
    get_efivar -f uint8 -s unprovisioned SetupMode

    if [ "\${unprovisioned}" = "1" ]; then
        set timeout=0

        menuentry "Automatic Certificate Provision" --unrestricted {
            chainloader \${prefix}/LockDown.efi
        }
    fi
  fi
fi

menuentry "OSTree Install from $fromdev" --unrestricted {
    set fallback=1
    efi-watchdog enable 0 180
    linux \${prefix}/bzImage $bootargs
    initrd \${prefix}/initrd
}
EOF

	echo "$DISTRO_FEATURES" | grep -q efi-secure-boot
	if [ $? -ne 0 ]; then
		sed -i '/^  get_efivar/,/^  fi/d' $OUTDIR/EFI/BOOT/grub.cfg
	fi
}

build_efi_area() {
	bzimage=$(ls ${DEPLOY_DIR_IMAGE}/bzImage)
	if [ -z "${OSTREE_INITRD}" ]; then
		OSTREE_INITRD="initramfs-ostree-image"
	fi
	initramfs=$(ls ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRD}*.cpio.gz |grep -v rootfs)
	bootx64=$(ls ${DEPLOY_DIR_IMAGE}/bootx64.efi 2> /dev/null)
	lockdown=$(ls ${DEPLOY_DIR_IMAGE}/LockDown.efi 2> /dev/null)
	mmx64=$(ls ${DEPLOY_DIR_IMAGE}/mmx64.efi 2> /dev/null)

	mkdir -p $OUTDIR/EFI/BOOT

	echo "Using grub: $grub"
	echo "Using kernel: $bzimage"
	echo "Using initrd: $initramfs"
	if [ "$bootx64" != "" ] ; then
		echo "Using bootx64.efi: $bootx64"
		cp $bootx64 $OUTDIR/EFI/BOOT/bootx64.efi
	else
		echo "Using bootx64.efi: $grub"
		do_cp_and_sig $grub $OUTDIR/EFI/BOOT/bootx64.efi
	fi

	do_cp_and_sig $grub $OUTDIR/EFI/BOOT/grubx64.efi
	do_cp_and_sig $bzimage $OUTDIR/EFI/BOOT/bzImage
	do_cp_and_sig $initramfs $OUTDIR/EFI/BOOT/initrd
	if [ "$lockdown" != "" ] ; then
		do_cp_and_sig $lockdown $OUTDIR/EFI/BOOT/LockDown.efi
	fi
	if [ "$mmx64" != "" ] ; then
		do_cp_and_sig $mmx64 $OUTDIR/EFI/BOOT/mmx64.efi
	fi
	create_grub_cfg
	cp $OUTDIR/EFI/BOOT/grub.cfg $OUTDIR/EFI/BOOT/igrub.cfg
	if [ "$lockdown" != "" ] ; then
		sign_grub
		cp $OUTDIR/EFI/BOOT/grub.cfg.sig $OUTDIR/EFI/BOOT/igrub.cfg.sig
	fi
}


build_bootfs() {
	echo "Building: bootfs"
	rm -rf $OUTDIR
	$FAKEROOTCMD mkdir -p $OUTDIR
	if [ $LOCAL_REPO = 1 ] ; then
		if [ "$LOCAL_REPO_DIR" = "0" ] ; then
			echo "Creating new inst_ostree_repo with: $INST_BRANCH"
			rm -rf localfs inst_ostree_repo
			repo=${DEPLOY_DIR_IMAGE}/ostree_repo
			ostree init --repo=inst_ostree_repo --mode=archive-z2 || fatal "ostree repo init failed"
			ostree config --repo=inst_ostree_repo set core.mode archive-z2 || fatal "ostree repo config failed"
			ostree pull-local --repo=inst_ostree_repo $repo $INST_BRANCH || fatal "ostree repo pull-local failed"
			ostree summary -u --repo=inst_ostree_repo || fatal "ostree repo summary failed"
			cp -r inst_ostree_repo $OUTDIR/ostree_repo || \
				fatal "Could not copy ${LOCAL_REPO_DIR}"
		elif [ "$LOCAL_REPO_DIR" != "" ] ; then
			if which ostree >/dev/null 2>&1; then
				ostree show --repo=${LOCAL_REPO_DIR} $INST_BRANCH >/dev/null || \
				    fatal "ostree branch $INST_BRANCH does not exist in ostree_repo"
			fi
			cp -r ${LOCAL_REPO_DIR} $OUTDIR/ostree_repo || \
				fatal "Could not copy ${LOCAL_REPO_DIR}"
		else
			if which ostree >/dev/null 2>&1; then
				ostree show --repo=${DEPLOY_DIR_IMAGE}/ostree_repo $INST_BRANCH >/dev/null || \
				    fatal "ostree branch $INST_BRANCH does not exist in ostree_repo"
			fi
			cp -r ${DEPLOY_DIR_IMAGE}/ostree_repo $OUTDIR/ostree_repo || \
				fatal "Could not copy ${DEPLOY_DIR_IMAGE}/ostree_rep"
		fi
		# Validate ostree_repo
		local e
		for e in config refs objects ; do
			if [ ! -e $OUTDIR/ostree_repo/$e ] ; then
				fatal "ERROR: the $OUTDIR/ostree_repo is corrupt or missing '$e'"
			fi
		done
	fi
	# Copy IMAGE_BOOT_FILES
	set -f
	bfiles="${IMAGE_BOOT_FILES}"
	for f in $bfiles; do
		set +f
		argFROM=$(echo "$f" |sed -e 's#;.*##')
		argTO=$(echo "$f" |sed -e 's#.*;##')
		if [ "$argFROM" != "$argTO" ] ; then
			if [ ! -e $OUTDIR/$argTO ] ; then
				d=$(dirname $OUTDIR/$argTO)
				[ ! -d $d ] && mkdir $d
				argFROM_head=`echo $argFROM | cut -b 1`
				if [ "$argFROM_head" = "/"  ]; then
					cp $argFROM $OUTDIR/$argTO
				else
					cp ${DEPLOY_DIR_IMAGE}/$argFROM $OUTDIR/$argTO
				fi
			else
				fatal "Error locating: $argFROM"
			fi
		else
			cp ${DEPLOY_DIR_IMAGE}/$f $OUTDIR
		fi
	done
	set +f
	if [ "$grub" != "" ] ; then
		build_efi_area
	fi
}

write_wic() {
	echo "Writing ustart.env"
	echo "FAKEROOTCMD=\"${FAKEROOTCMD}\"" > ustart.env
	echo "RECIPE_SYSROOT_NATIVE=\"${RECIPE_SYSROOT_NATIVE}\"" >> ustart.env
	echo "IMAGE_ROOTFS=\"${OUTDIR}\"" >> ustart.env
	echo "DEPLOY_DIR_IMAGE=\"${DEPLOY_DIR_IMAGE}\"" >> ustart.env
	echo "Writing: ustart.wks"

	if [ "$grub" != "" ] ; then
		echo "bootloader --ptable gpt" > ustart.wks
	else
		echo "bootloader --ptable msdos" > ustart.wks
	fi
	PARTSZ=""
	if [ "$PARTSIZE" != "0" ] ; then
		PARTSZ="--fixed-size=$PARTSIZE"
	fi

	if [ -n "$OSTREE_FDISK_BLM" ]; then
		ALIGNSZ="--align $OSTREE_FDISK_BLM"
	else
		ALIGNSZ="--align 2048"
	fi

	if [ ${UUID} != "" ]; then
		echo "part / --source rootfs --rootfs-dir=$OUTDIR --ondisk sda --fstype=vfat --uuid ${UUID} --fsuuid $(echo ${UUID:0:8}|sed 's/[a-z]/\U&/g') --label instboot --active $ALIGNSZ $PARTSZ" >> ustart.wks
	else
		echo "part / --source rootfs --rootfs-dir=$OUTDIR --ondisk sda --fstype=vfat --label instboot --active $ALIGNSZ $PARTSZ" >> ustart.wks
	fi

	echo "Writing: ustart.img and ustart.img.bmap"
	rm -rf out-tmp
	mkdir out-tmp
	cmd="wic create -e ustart -v . -m -s ustart.wks -o out-tmp"
	$cmd 2>&1 > /dev/null | tee out-tmp/log 2>&1
	if [ ${PIPESTATUS[0]} != 0 ] ; then
		grep -E -q -e "(is larger|Disk full|No space left)" out-tmp/log
		if [ $? = 0 ] ; then
			echo "================================================"
			echo "Error with partition size too small"
			echo "   To use automatic partition size cacluation please run bootfs.sh with:"
                        echo "       -s 0"
			echo "   Or use a number in MB that is large enough to hold all the data"
			fatal
		else
			fatal "Error running: $cmd"
		fi
	fi
	echo "Rename `ls out-tmp/*.direct` to ustart.img"
	mv out-tmp/*.direct ustart.img
	mv out-tmp/*.bmap ustart.img.bmap
	rm -rf out-tmp
	if [ -n "$BOOTFS_EXTRA_CMD" ]; then
		echo "Running BOOTFS_EXTRA_CMD..."
		eval $BOOTFS_EXTRA_CMD
	fi
	if [ "$COMPRESS" = "1" ] ; then
		echo "Compressing image and writing: ustart.img.gz"
		pigz -f *ustart*.img
	fi
	echo "======================== SUCCESS ==============================="
	echo "==== Write image to device with one of the command(s) below ===="
	echo "================================================================"
	if ! which bmaptool > /dev/null ; then
		echo "### NOTE: bmaptool is not in your path, so you should run:"
		echo "  bitbake bmap-tools-native"
		echo "  bitbake build-sysroots"
		echo "  PATH=\$PWD/$(ls -trd tmp tmp-glibc 2> /dev/null |tail -1 )/sysroots/x86_64/usr/bin:\$PATH \\"
	fi
	if [ "$COMPRESS" = "1" ] ; then
		echo "   bmaptool copy --bmap ustart.img.bmap ustart.img.gz /dev/YOUR_DISK_DEVICE"
		echo "### or run ###"
		echo "   zcat ustart.img.gz | dd bs=1M of=/dev/YOUR_DISK_DEVICE"
	else
		echo "   bmaptool copy --bmap ustart.img.bmap ustart.img /dev/YOUR_DISK_DEVICE"
		echo "### or run ###"
		echo "   dd if=ustart.img bs=1M of=/dev/YOUR_DISK_DEVICE"
	fi
}

print_part_layout() {
	if [ "$grubcfg" != "" ] ; then
		pt1="mount: /boot/efi"
	fi
	useab=$OSTREE_USE_AB
	useflux=1
	FSZ=${OSTREE_FDISK_FSZ}
	BSZ=${OSTREE_FDISK_BSZ}
	RSZ=${OSTREE_FDISK_RSZ}
	VSZ=${OSTREE_FDISK_VSZ}
	for e in $bootargs; do
		[ "$e" != "${e#instab=}" ] && useab=${e#instab=}
		[ "$e" != "${e#FSZ=}" ] && FSZ=${e#FSZ=}
		[ "$e" != "${e#BSZ=}" ] && BSZ=${e#BSZ=}
		[ "$e" != "${e#RSZ=}" ] && RSZ=${e#RSZ=}
		[ "$e" != "${e#VSZ=}" ] && VSZ=${e#VSZ=}
		[ "$e" != "${e#instflux=}" ] && useflux=${e#instflux=}
		if [ "$e" != "${e#instsf=}" ] ; then
			if [ "$e" = "instsf=1" ] ; then
				if [ $PARTSIZE = 0 ] ; then
					FSZ=$(du -sm bootfs |awk '{print $1}')
					FSZ=$(($FSZ + $FSZ/10*8))
					PARTSIZE=$FSZ
				else
					FSZ=$PARTSIZE
				fi
			fi
		fi
	done
	if [ "$FSZ" != "${OSTREE_FDISK_FSZ}" ] ; then
		echo "NOTE: OSTREE_FDISK_FSZ($OSTREE_FDISK_FSZ) != FSZ($FSZ)"
		echo "      Please consider changing OSTREE_FDISK_FSZ in local.conf and rebuilding"
	fi
	if [ "$BSZ" != "${OSTREE_FDISK_BSZ}" ] ; then
		echo "NOTE: OSTREE_FDISK_BSZ($OSTREE_FDISK_BSZ) != BSZ($BSZ)"
		echo "      Please consider changing OSTREE_FDISK_BSZ in local.conf and rebuilding"
	fi
	if [ "$RSZ" != "${OSTREE_FDISK_RSZ}" ] ; then
		echo "NOTE: OSTREE_FDISK_RSZ($OSTREE_FDISK_RSZ) != RSZ($RSZ)"
		echo "      Please consider changing OSTREE_FDISK_RSZ in local.conf and rebuilding"
	fi
	if [ "$VSZ" != "${OSTREE_FDISK_VSZ}" ] ; then
		echo "NOTE: OSTREE_FDISK_VSZ($OSTREE_FDISK_VSZ) != VSZ($VSZ)"
		echo "      Please consider changing OSTREE_FDISK_VSZ in local.conf and rebuilding"
	fi
	sz=$(($FSZ + $OSTREE_FDISK_BSZ))
	echo -e "============= Installed Disk Layout ============="
	echo -e "Partition 1: fat32 size: ${FSZ}MB\t$pt1"
	pt=2
	echo -e "Partition $pt: ext4  size: ${BSZ}MB\tmount: /boot (A partition)"
	if [ $useflux = 0 -a $useab = 0 ] ; then
		if [ $VSZ = 0 ] ; then
			prsz="FILL"
		else
			prsz="${VSZ}MB"
			sz=$(($sz+${VSZ}))
		fi
		pt=$(($pt+1))
	else
		pt=$(($pt+1))
		sz=$(($sz+${RSZ}))
		prsz="${RSZ}MB"
	fi
	echo -e "Partition $pt: ext4  size: ${prsz}\tmount: / (A partition)"
	if [ $useab = 1 ] ; then
		pt=$(($pt+1))
		sz=$(($sz+${BSZ}))
		echo -e "Partition $pt: ext4  size: ${BSZ}MB\tmount: /boot (B partition)"
		pt=$(($pt+1))
		sz=$(($sz+${RSZ}))
		echo -e "Partition $pt: ext4  size: ${RSZ}MB\tmount: / (B partition)"
	fi
	if [ $useflux = 1 ] ; then
		pt=$(($pt+1))
		if [ $VSZ = 0 ] ; then
			echo -e "Partition $pt: ext4  size: FILL\tmount: /var"
		else
			echo -e "Partition $pt: ext4  size: ${RSZ}MB\tmount: /var"
			sz=$(($sz+${VSZ}))
		fi
	fi
	echo -e "Total allocation excluding auto fill: ${sz}MB"
	echo -e "================================================="
}

while getopts "a:Bb:d:e:hk:Ll:Nns:u:U:w" opt; do
	case ${opt} in
		a)
			EXTRA_INST_ARGS=$OPTARG
			;;
		b)
			INST_BRANCH=$OPTARG
			;;
		B)
			DO_BUILD_BOOTFS=0
			;;
		d)
			INST_DEV=$OPTARG
			;;
		e)
			ENVFILE=$OPTARG
			;;
		l)
			LOCAL_REPO_DIR=$OPTARG
			LOCAL_REPO=1
			;;
		L)
			LOCAL_REPO=1
			;;
		k)
			EXTRA_KERNEL_ARGS=$OPTARG
			;;
		s)
			PARTSIZE=$OPTARG
			;;
		n)
			COMPRESS=0
			;;
		N)
			MODIFY_BOOT_SCR=0
			;;
		U)
			UUID=$OPTARG
			;;
		u)
			INST_URL=$OPTARG
			;;
		h)
			usage
			;;
		w)
			SKIP_WIC=1
			;;
		*)
			usage
			;;
	esac
done

### Main ###
if [ "$ENVFILE" = "" -o "$ENVFILE" = "auto" ] ; then
	# Generate an env file if possible...
	latest=`ls -tr tmp*/deploy/images/*/ostree_repo/refs/heads/|tail -1`
	if [ "$latest" = "" ] ; then
		fatal "ERROR: No .env file or branch found the ostree_repo"
	fi
	ENVFILE=$PWD/$latest.env
	if [ ! -e $ENVFILE ] ; then
		echo "Running bitbake -e $latest > $ENVFILE"
		bitbake -e $latest > $ENVFILE
		if [ $? != 0 ] ; then
			rm $ENVFILE
			fatal "Error running bitbake"
		fi
	else
		echo "Using cached: $ENVFILE"
	fi
fi

if [ ! -e "$ENVFILE" ] ; then
	if [ "$ENVFILE" = "${ENVFILE%.env}" ] ; then
		echo "Appending .env to $ENVFILE"
		ENVFILE="$ENVFILE.env"
	fi
fi

if [ -e "$ENVFILE" -a "conf/local.conf" -nt "$ENVFILE" ] ; then
	echo "conf/local.conf is newer, removing $ENVFILE"
	rm "$ENVFILE"
fi

if [ ! -e "$ENVFILE" -a "$ENVFILE" != "${ENVFILE%.env}" ] ; then
	bbtarget=${ENVFILE%.env}
	bbtarget=${bbtarget##*/}
	echo "Running bitbake -e $bbtarget > $ENVFILE"
	bitbake -e $bbtarget > $ENVFILE
	if [ $? != 0 ] ; then
		rm $ENVFILE
		fatal "Error running bitbake"
	fi
fi

echo "Env settings from: $ENVFILE"

eval `grep ^FAKEROOTCMD $ENVFILE`
eval `grep ^RECIPE_SYSROOT_NATIVE $ENVFILE`
eval `grep ^IMAGE_BOOT_FILES $ENVFILE`
eval `grep ^DEPLOY_DIR_IMAGE $ENVFILE`
eval `grep ^IMAGE_BASENAME $ENVFILE`
eval `grep ^BOOT_ $ENVFILE`
eval `grep ^STAGING_DIR= $ENVFILE`
eval `grep ^OSTREE_ $ENVFILE | sed -e 's#\(^[^=]*\):#\1_#g' | perl -p -e '($a,$b) = split(/=/,$_,2); $a =~ s/-/_/g; $_ = "$a=$b"'`
eval `grep ^OSTREE_CONSOLE= $ENVFILE | sed -e 's:\\\\::g' -e "s:\":':g"`
eval `grep ^DISTRO_FEATURES= $ENVFILE`
eval `grep ^BOOTFS_EXTRA_CMD= $ENVFILE`
eval `grep ^OSTREE_FDISK_BLM= $ENVFILE`
eval `grep ^OSTREE_KERNEL_ARGS= $ENVFILE`
eval `grep ^OSTREE_INST_ARGS= $ENVFILE`
eval `grep 'export OSTREE_OSNAME=' $ENVFILE`

if [ -n "${OSTREE_KERNEL_ARGS}" ]; then
    EXTRA_KERNEL_ARGS="${OSTREE_KERNEL_ARGS} ${EXTRA_KERNEL_ARGS}"
fi
if [ -n "${OSTREE_INST_ARGS}" ]; then
    EXTRA_INST_ARGS="${OSTREE_INST_ARGS} ${EXTRA_INST_ARGS}"
fi

if [ -n "${OSTREE_FDISK_BLM}" ]; then
    EXTRA_INST_ARGS="BLM=${OSTREE_FDISK_BLM} ${EXTRA_INST_ARGS}"
fi

if [ -n "${OSTREE_FDISK_FSZ}" ]; then
    EXTRA_INST_ARGS="FSZ=${OSTREE_FDISK_FSZ} ${EXTRA_INST_ARGS}"
fi

if [ -n "${OSTREE_FDISK_BSZ}" ]; then
    EXTRA_INST_ARGS="BSZ=${OSTREE_FDISK_BSZ} ${EXTRA_INST_ARGS}"
fi

if [ -n "${OSTREE_FDISK_RSZ}" ]; then
    EXTRA_INST_ARGS="RSZ=${OSTREE_FDISK_RSZ} ${EXTRA_INST_ARGS}"
fi

if [ -n "${OSTREE_FDISK_VSZ}" ]; then
    EXTRA_INST_ARGS="VSZ=${OSTREE_FDISK_VSZ} ${EXTRA_INST_ARGS}"
fi

grub=$(ls $DEPLOY_DIR_IMAGE/grubx64.efi 2> /dev/null)
if [ "$grub" = "" ] ; then
	# Look for bootx variant
	grub=$(ls $DEPLOY_DIR_IMAGE/grub-efi-bootx64.efi 2> /dev/null)
fi
if [ "$grub" = "" ] ; then
	# Fall back to looking optional non-signed binary
	grub=$(ls $DEPLOY_DIR_IMAGE/grub-efi-grubx64.efi 2> /dev/null)
fi

if [ "$INST_URL" != "" ] ; then
	OSTREE_REMOTE_URL="$INST_URL"
fi
if [ "$OSTREE_REMOTE_URL" = "" ] ; then
	if [ $LOCAL_REPO = 1 ] ; then
		OSTREE_REMOTE_URL=file://$INSTL
		echo "WARNING: Setting url to: $OSTREE_REMOTE_URL"
	else
	    fatal 'ERROR: OSTREE_REMOTE_URL = "your_ostree_repo_url" must be defined in local.conf'
	fi
fi

if [ -z "$RECIPE_SYSROOT_NATIVE" ]; then
	fatal "The RECIPE_SYSROOT_NATIVE is not set"
fi

if [ ! -d "$RECIPE_SYSROOT_NATIVE" ] ; then
	if [ ! -d "${STAGING_DIR}/x86_64" ] ; then
		echo "Running: bitbake build-sysroots"
		bitbake build-sysroots
	fi
	if [ ! -d "${STAGING_DIR}/x86_64" ] ; then
		fatal "Could not locate sysroot binaries"
	fi
	RECIPE_SYSROOT_NATIVE="${STAGING_DIR}/x86_64"
fi

PATH=$RECIPE_SYSROOT_NATIVE/usr/bin:$RECIPE_SYSROOT_NATIVE/bin:$PATH
if [ -d $RECIPE_SYSROOT_NATIVE/usr/bin/perl-native ]; then
	PATH=$RECIPE_SYSROOT_NATIVE/usr/bin/perl-native:$PATH
fi

if [ "$UUID" = "auto" ] ; then
	UUID=$(uuidgen)
fi

if [ ${UID} = "0" ]; then
	FAKEROOTCMD=""
else
	export PSEUDO_PREFIX=$RECIPE_SYSROOT_NATIVE/usr
	export PSEUDO_LOCALSTATEDIR=$PWD/pseudo
	export PSEUDO_PASSWD=$PWD/rootfs/etc
	export PSEUDO_NOSYMLINKEXP=1

	# Double check the FAKEROOTCMD and PSEUDO_PREFIX
	if [ ! -e "${FAKEROOTCMD}" ] ; then
		echo "ERROR: Could not locate $FAKEROOTCMD"
		exit 1
	fi
	if [ ! -d "$PSEUDO_PREFIX" ] ; then
		PSEUDO_PREFIX=$(dirname $(dirname $FAKEROOTCMD))
	fi
fi

if [ -z "$INST_BRANCH" ] ; then
	INST_BRANCH=$IMAGE_BASENAME
fi

[ $DO_BUILD_BOOTFS = 1 ] && build_bootfs
if [ ! -e $OUTDIR ] ; then
	fatal "ERROR: The build directory '$OUTDIR' does not exist"
fi
[ $MODIFY_BOOT_SCR = 1 ] && modify_boot_scr

print_part_layout

if [ $SKIP_WIC = 1 ] ; then
	echo "bootfs.sh completed succesfully."
else
	write_wic
fi

exit 0

# TODO... 
# Instructions for trail with a sample disk
# bootfs.sh -n
# qemu-img create -f raw img 10G
# dd if=ustart.img of=img conv=notrunc
# LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH swtpm socket --tpm2 --tpmstate dir=$PWD/my_tpm --ctrl type=unixio,path=$PWD/my_tpm/tpm-sock & qemu-system-x86_64 --enable-kvm --nographic -vnc :5 -drive file=OVMF_CODE.fd,format=raw,readonly,if=pflash,unit=0 -drive if=pflash,format=raw,unit=1,file=OVMF_VARS.fd -chardev "socket,id=chrtpm0,path=$PWD/my_tpm/tpm-sock" -tpmdev 'emulator,id=tpm0,chardev=chrtpm0' -device 'tpm-tis,tpmdev=tpm0' -drive file=img,if=virtio,format=raw -m 1024 -serial mon:stdio -netdev type=user,id=h1,tftp=bootfs,bootfile=EFI/BOOT/bootx64.efi -device e1000,netdev=h1,mac=00:55:55:01:01:01 -usbdevice tablet -cpu qemu64,+ssse3,+sse4.1,+sse4.2,+x2apic,rdrand -device virtio-rng-pci
