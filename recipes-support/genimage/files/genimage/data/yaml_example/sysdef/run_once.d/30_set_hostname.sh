#!/bin/sh
# Set hostname based on MAC address or current time
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
if [ -e /etc/hostname ]; then
  old=`cat /etc/hostname`
fi
interface=`ls /sys/class/net/e*/address | head -1`
if [ -n $interface ] && [ -e $interface ]; then
    mac=`cat $interface`
    new=`echo $mac | sed s/:/-/g`
else
    new=`date +%s`
fi
hostnamectl set-hostname $new
if [ -n "$old" ]; then
    sed -i "s/ $old$/ $new/g" /etc/hosts
fi
