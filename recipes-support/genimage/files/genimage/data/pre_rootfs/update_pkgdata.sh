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

set -x
set -e

install_pkgdata() {
    pkgdatadir=$1
    if [ ! -d $pkgdatadir ]; then
        mkdir -p $pkgdatadir
        tar xf pkgdata.tar.bz2 -C $pkgdatadir
    fi
}

update_pkgdata() {
    pkgdatadir=$OECORE_NATIVE_SYSROOT/../pkgdata

    if [ ! -d "$OECORE_NATIVE_SYSROOT/usr/share/pkgdata" ]; then
        # It is in a build rather than SDK
        if [ ! -e $REMOTE_PKGDATADIR ]; then
            echo "The $REMOTE_PKGDATADIR not found"
            exit 1
        fi
        exit 0
    fi


    cd "$OECORE_NATIVE_SYSROOT/usr/share/pkgdata"

    wget $REMOTE_PKGDATADIR/.pkgdata.tar.bz2.sha256sum -O .pkgdata.tar.bz2.sha256sum
    if [ $? -ne 0 ]; then
        echo "Download pkgdata.tar.bz2.sha256sum failed, use default pkgdata"
        install_pkgdata $pkgdatadir
        exit 0
    fi

    set +e
    cat .pkgdata.tar.bz2.sha256sum | sha256sum -c
    if [ $? -eq 0 ]; then
        set -e
        rm .pkgdata.tar.bz2.sha256sum
        install_pkgdata $pkgdatadir
        exit 0
    fi
    set -e

    echo "The pkgdata is obsoleted, update it from rpm repo"
    wget $REMOTE_PKGDATADIR/.pkgdata.tar.bz2 -O .pkgdata.tar.bz2
    if [ $? -ne 0 ]; then
        echo "Update pkgdata from rpm repo failed, use default"
        rm -f .pkgdata.tar.bz2*
        install_pkgdata $pkgdatadir
        exit 0
    fi

    mv .pkgdata.tar.bz2.sha256sum pkgdata.tar.bz2.sha256sum
    mv .pkgdata.tar.bz2 pkgdata.tar.bz2

    rm $pkgdatadir -rf
    install_pkgdata $pkgdatadir

}

update_pkgdata $1

# cleanup
ret=$?
exit $ret
