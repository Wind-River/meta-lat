#!/bin/bash
#
# Copyright (c) 2021 Wind River Systems, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
set -x

## Require environments
# OSTREE_CONSOLE
# KERNEL_PARAMS

# Modify the boot.scr
update_boot_scr() {
    rootfs=$1
    branch=$2
    ab=$3
    url=$4
    if [ ! -e $rootfs/boot/boot.scr ] ; then
        exit 0
    fi
    tail -c+73 $rootfs/boot/boot.scr > $rootfs/boot/boot.scr.raw

    sed -i -e "/^setenv bootargs/s/console=[^ ^\"]*//g" \
           -e "s/^\(setenv bootargs .*\)\"$/\1 ${OSTREE_CONSOLE} ${KERNEL_PARAMS}\"/g" \
        $rootfs/boot/boot.scr.raw

    sed -i -e "/^setenv instdef/s/console=[^ ^\"]*//g" \
        -e "s/^\(setenv instdef .*\)\"$/\1 ${OSTREE_CONSOLE}\"/g" \
        $rootfs/boot/boot.scr.raw

    perl -p -i -e "s#^( *setenv BRANCH) .*#\$1 $branch# if (\$_ !~ /oBRANCH/) " $rootfs/boot/boot.scr.raw
    perl -p -i -e "s#^( *setenv URL) .*#\$1 $url# if (\$_ !~ /oURL/) " $rootfs/boot/boot.scr.raw
    perl -p -i -e "s#instab=[^ ]* #instab=$ab #" $rootfs/boot/boot.scr.raw

    mkimage -A arm -T script -O linux -d $rootfs/boot/boot.scr.raw $rootfs/boot/boot.scr
    if [ -e $rootfs/boot/boot.itb ] ; then
        mkimage -A arm -T script -O linux -f auto -C none -d $rootfs/boot/boot.scr.raw $rootfs/boot/boot.itb
    fi

    rm -f $rootfs/boot/boot.scr.raw
}

update_boot_scr $1 $2 $3 $4
