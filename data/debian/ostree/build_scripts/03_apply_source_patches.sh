#!/bin/bash
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
source_dir=$1
if [ -z "$source_dir" -o ! -d "$source_dir" ]; then
    source_dir=${PWD}
fi
cd $source_dir

source_patch_dir="`dirname ${BASH_SOURCE[0]}`"
source_patch_dir="`realpath ${source_patch_dir}/../source_patches`"
mkdir ${source_dir}/debian/patches/lat
cp -f ${source_patch_dir}/*.patch ${source_dir}/debian/patches/lat/

