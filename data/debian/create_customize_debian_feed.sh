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
export OSTREE_OSNAME="lat_os"

usage() { echo "Usage: $0 [-n <ostree_osname>]" 1>&2; exit 1; }

while getopts "n:h" opt; do
    case ${opt} in
        n)
            OSTREE_OSNAME="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

echo "OSTREE_OSNAME: $OSTREE_OSNAME"

echo "deb-src http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list
apt update
apt-get install -y build-essential devscripts apt-utils

topdir="`dirname ${BASH_SOURCE[0]}`/../.."
builddir="${topdir}/workdir/build"
deploydir="${topdir}/customize_debian/debian"
rm -rf  "${topdir}/workdir ${topdir}/customize_debian"
mkdir -p ${builddir} ${deploydir}
subdirs="${topdir}/data/debian"
for sub in `ls ${subdirs} -1`; do
    [ ! -d "${subdirs}/$sub" ] && continue
    [ $sub = "common" ] && continue

    echo "Build $sub"
    for script in `ls ${subdirs}/${sub}/build_scripts/*.sh`; do
        bash $script "${builddir}" || exit 1
    done
done

mv ${topdir}/workdir/*.deb ${deploydir}
rm -rf "${topdir}/workdir"
cd ${deploydir}
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
