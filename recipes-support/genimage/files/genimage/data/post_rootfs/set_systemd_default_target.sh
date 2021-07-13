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
set -e

set_systemd_default_target () {
    rootfs=$1
    default_target=$2
    if [ -d $rootfs/etc/systemd/system -a -e $rootfs/usr/lib/systemd/system/$default_target ]; then
        ln -sf /usr/lib/systemd/system/$default_target $rootfs/etc/systemd/system/default.target
    fi
}

set_systemd_default_target $1 $2


