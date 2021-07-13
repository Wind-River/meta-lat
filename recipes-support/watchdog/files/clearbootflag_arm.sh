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

partbase=`cat /proc/mounts |grep "sysroot " | awk '{print $1}'`
### ASSUME sysroot is on a partitio <= 9 ###
part=${partbase::-1}'1'
tdir=`mktemp -d`
if [ "$tdir" != "" ] ; then
	mount ${part} ${tdir}
	grep -q ^.1WR ${tdir}/boot_cnt
	if grep -q ^.1WR ${tdir}/boot_cnt; then
		echo "WARNING: running on rollback partition"
		printf '01WR' > ${tdir}/boot_cnt
	else
		printf '00WR' > ${tdir}/boot_cnt
	fi
	umount ${tdir}
	rm -rf ${tdir}
fi

