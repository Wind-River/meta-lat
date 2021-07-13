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

add_sysdef_support() {
    rootfs=$1
    sysdefdir="${OECORE_NATIVE_SYSROOT}/usr/share/genimage/data/sysdef"
    install -d  ${rootfs}/usr/bin/
    install -m 0755 ${sysdefdir}/sysdef.sh ${rootfs}/usr/bin/

    install -d ${rootfs}/usr/lib/systemd/system/
    install -m 0664 ${sysdefdir}/sysdef.service ${rootfs}/usr/lib/systemd/system/

    systemctl --root ${rootfs}  enable sysdef.service

    mkdir -p ${rootfs}/usr/lib/systemd/system-preset/
    echo "enable sysdef.service" > ${rootfs}/usr/lib/systemd/system-preset/98-sysdef.preset
}

add_sysdef_support $1
