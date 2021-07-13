#!/bin/sh
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
set -e
dest=$1
if [ -z "$dest" -o ! -d "$dest" ]; then
    dest=${PWD}/workdir
fi
rm -rf ${dest}
mkdir -p ${dest}
cd $dest
git clone --branch debian/master --single-branch https://salsa.debian.org/debian/ostree.git .
git checkout debian/2019.1-1 -b debian/2019.1-1
apt build-dep -y ostree
