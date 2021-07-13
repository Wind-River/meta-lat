#!/bin/sh
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

create_merged_usr_symlinks() {
    root="$1"
    install -d $root/usr/bin $root/usr/sbin $root/usr/lib64
    ln --relative -snf $root/usr/bin $root/bin
    ln --relative -snf $root/usr/sbin $root/sbin
    ln --relative -snf $root/usr/lib64 $root/lib64

    install -d $root/usr/lib
    ln --relative -snf $root/usr/lib $root/lib

    # create base links for multilibs
    multi_libdirs="lib32"
    for d in $multi_libdirs; do
        install -d $root/usr/$d
        ln --relative -snf $root/usr/$d $root/$d
    done
}

create_merged_usr_symlinks ${IMAGE_ROOTFS}
