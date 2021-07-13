#!/bin/sh
# Add a new user and create user's home directory
# Add the user to sudo group
# Username: admin
# Password: 123456
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
useradd admin -G sudo --password '$6$YcX9PtwnWDeeZfLG$NO64/Frq0xXcMVLKFXqdKxdwBBF42I5TpEiaWfnuj6u6V5GMb0XCASZE7bG4Iiof8QtttCAN4F6xpdNhldIJl/'
