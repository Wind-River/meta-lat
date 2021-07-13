#!/bin/sh

#* Copyright (c) 2018 Wind River Systems, Inc.
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

envfile=/boot/efi/EFI/BOOT/boot.env
rw=0
if [ ! -w /boot/efi ] ; then
	dev=$(cat /proc/mounts |grep \ /boot/efi | cut -f 1 -d " ")
	rw=1
	tmp=$(mktemp -d)
	if [ ! -d "$tmp" ] ; then
		echo "Error: no tmpdir"
		exit 1
	fi
	if [ ! -e "$dev" ] ; then
		echo "Error: could not locate efi dir"
		exit 1
	fi
	# Use a read-only mount and transition it to a rw mount
	mount -r $dev $tmp 2> /dev/null
	if [ $? = 0 ] ; then
		mount -o remount,rw $dev $tmp || (umount $tmp; exit 1) || exit 1
	else
		mount -w $dev $tmp || exit 1
	fi
	envfile=$tmp/EFI/BOOT/boot.env
fi

if [ -f $envfile ] ; then
	/usr/bin/grub-editenv $envfile set boot_tried_count=0
	if /usr/bin/grub-editenv $envfile list |grep -q ^default=1 ; then
		echo "WARNING: running on rollback partition"
	fi
else
	/usr/bin/grub-editenv $envfile create
fi

if [ $rw = 1 ] ; then
	umount $tmp
	rmdir $tmp
fi
