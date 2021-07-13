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
# Enable dhcpcd service if NetworkManager is not installed.
set -e
set -x

sbindir="/usr/sbin"
sysconfdir="/etc"
systemd_unitdir="/lib/systemd"
enable_dhcpcd_service() {
    if [ ! -e ${IMAGE_ROOTFS}${sbindir}/NetworkManager \
        -a -f ${IMAGE_ROOTFS}${systemd_unitdir}/system/dhcpcd.service ]; then
        mkdir -p ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/multi-user.target.wants
        ln -sf ${systemd_unitdir}/system/dhcpcd.service \
            ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/multi-user.target.wants/dhcpcd.service
    fi
}

enable_dhcpcd_service
