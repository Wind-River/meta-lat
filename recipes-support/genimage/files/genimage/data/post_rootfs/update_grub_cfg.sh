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
# EFI_SECURE_BOOT

# Modify the grub.cfg
update_grub_cfg() {
    rootfs=$1
    if [ ! -e $rootfs/boot/efi/EFI/BOOT/grub.cfg ] ; then
        exit 0
    fi

    sed -i -e "s#^\(set ostree_console\).*#\1=\"$OSTREE_CONSOLE\"#g" $rootfs/boot/efi/EFI/BOOT/grub.cfg
    sed -i -e "s#^\(set kernel_params\).*#\1=\"$KERNEL_PARAMS\"#g" $rootfs/boot/efi/EFI/BOOT/grub.cfg

    # Remove secure content from grub.cfg if secure boot disable
    if [ "${EFI_SECURE_BOOT}" != "enable" ]; then
        sed -i '/^get_efivar/,/^fi/d' $rootfs/boot/efi/EFI/BOOT/grub.cfg
    fi

}

update_grub_cfg $1
