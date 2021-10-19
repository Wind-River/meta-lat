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
read_args() {
	CMDLINE=`cat /proc/cmdline`
	for arg in $CMDLINE; do
		optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
		case $arg in
			no_fatwrite=*)
				no_fatwrite="$optarg"
				;;
		esac
	done
}
read_args

partbase=`cat /proc/mounts |grep "sysroot " | awk '{print $1}'`
### ASSUME sysroot is on a partitio <= 9 ###
if [ "${partbase#/dev/mmcblk}" != ${partbase} ] ; then
	dev="${partbase::-2}"
elif [ "${partbase#/dev/nbd}" != ${partbase} ] ; then
	dev="${partbase::-2}"
elif [ "${partbase#/dev/nvme}" != ${partbase} ] ; then
	dev="${partbase::-2}"
elif [ "${partbase#/dev/loop}" != ${partbase} ] ; then
	dev="${partbase::-2}"
else
	dev="${partbase::-1}"
fi

part=${partbase::-1}'1'
tdir=`mktemp -d`
if [ "$tdir" != "" -a "$no_fatwrite" != yes ] ; then
	mount ${part} ${tdir}
	if grep -q ^.1WR ${tdir}/boot_cnt; then
		echo "WARNING: running on rollback partition"
		printf '01WR' > ${tdir}/boot_cnt
	else
		printf '00WR' > ${tdir}/boot_cnt
	fi
	umount ${tdir}
	rm -rf ${tdir}
elif [ "$tdir" != "" -a "$no_fatwrite" = yes ] ; then
	# offset 524288 = 1024 block * 512 byte
	hexdump ${dev} -n 4 -s 524288 -v -e '/1 "%c"' | grep -q ^.1WR
	if [ $? -eq 0 ]; then
		echo "WARNING: running on rollback partition"
		printf '01WR' | dd of=${dev} seek=1024
	else
		printf '00WR' | dd of=${dev} seek=1024
	fi
fi

