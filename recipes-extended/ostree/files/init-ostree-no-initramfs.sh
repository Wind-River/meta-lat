#!/bin/sh
#/*
#*init.sh , a script to init the ostree system in initramfs
#* 
#* Copyright (c) 2023 Wind River Systems, Inc.
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
#* 
#*/ 
set -x

log_info() { echo "$0[$$]: $*" >&2; }
log_error() { echo "$0[$$]: ERROR $*" >&2; }

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib/ostree:/usr/lib64/ostree

OSTREE_LABEL_FLUXDATA="fluxdata"
export datapart=""

do_mount_fs() {
	echo "mounting FS: $*"
	[[ -e /proc/filesystems ]] && { grep -q "$1" /proc/filesystems || { log_error "Unknown filesystem"; return 1; } }
	[[ -d "$2" ]] || mkdir -p "$2"
	[[ -e /proc/mounts ]] && { grep -q -e "^$1 $2 $1" /proc/mounts && { log_info "$2 ($1) already mounted"; return 0; } }
	mount -t "$1" "$1" "$2"
}

early_setup() {
	do_mount_fs proc /proc
	do_mount_fs sysfs /sys
	mount -t devtmpfs none /dev
	do_mount_fs tmpfs /tmp
	do_mount_fs tmpfs /run
}

read_args() {
	[ -z "$CMDLINE" ] && CMDLINE=`cat /proc/cmdline`
	for arg in $CMDLINE; do
		optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
		case $arg in
			debugfatal)
				DEBUGFATAL=1 ;;
			flux=*)
				OSTREE_LABEL_FLUXDATA=$optarg ;;
		esac
	done
}

expand_fluxdata() {

	fluxdata_label=$OSTREE_LABEL_FLUXDATA
	[ -z $fluxdata_label ] && return 0

	# expanding FLUXDATA
	datapart=$(blkid -s LABEL | grep "LABEL=\"$fluxdata_label\"" |head -n 1| awk -F: '{print $1}')

	datadev=$(lsblk $datapart -n -o PKNAME | head -n 1)
	[ -z ${datadev} ] && return 0
	datadevnum=$(echo ${datapart} | sed 's/\(.*\)\(.\)$/\2/')

	disk_sect=`fdisk -l /dev/$datadev | head -n 1 |awk '{print $7}'`
	part_end=`fdisk -l /dev/$datadev | grep ^${datapart} | awk '{print $3}'`
	disk_end=$(expr $disk_sect - 1026)
	if [ $part_end -ge $disk_end ]; then
		if [ -e /.resizevar ]; then
			echo "Expanding FS for ${fluxdata_label} ..."
			resize2fs -f ${datapart} && e2fsck -y ${datapart}
			rm /.resizevar
			return 0
		else
			datapart=""
			echo "No fluxdata expansion." && return 0
		fi
	fi

	nextpartnum=$(($datadevnum+1))
	nextpart=$(echo ${datapart} | sed 's/\(.*\)\(.\)$/\1/')${nextpartnum}
	blkid ${nextpart} >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		datapart=""
		echo "The fluxdata ${datapart} is not last partitioin, no expansion." && return 0
	fi

	echo "Expanding partition for ${fluxdata_label} ..."
	echo ", +" | sfdisk -N $datadevnum --force --no-reread /dev/$datadev
	if [ $? -eq 0 ]; then
		touch /.resizevar
		sync
		# Reboot to apply expanding FS
		echo b > /proc/sysrq-trigger
	fi
}

#######################################

early_setup

read_args

expand_fluxdata

OSTREE_DEPLOY=$1

which lsattr >/dev/null && which chattr >/dev/null && has_immutable_test=1
if [ -n "$has_immutable_test" ]; then
	lsattr $OSTREE_DEPLOY -d -l | grep Immutable -q
	if [ $? -ne 0 ]; then
		chattr +i $OSTREE_DEPLOY
	fi
fi

exec /sbin/init
