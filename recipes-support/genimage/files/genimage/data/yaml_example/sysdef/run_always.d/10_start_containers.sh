#!/bin/sh
# Start containers listed in /etc/sysdef/run_on_upgrade.d/XXXX/containers.dat
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
latest=`ls /etc/sysdef/run_on_upgrade.d/ -1 -v -r | head -n 1`
dirname="/etc/sysdef/run_on_upgrade.d/${latest}"
dat="${dirname}/containers.dat"
while read -r line; do
    [ "${line}" != "${line#\#}" ] && continue
    container_name=${line%% *}
    [ -z "${container_name}" ] && continue
    echo "systemctl start start-container@${container_name}.service"
    systemctl start start-container@${container_name}.service
done < ${dat}
