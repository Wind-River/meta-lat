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
force=0
sysdefdir="/etc/sysdef"
res=0

usage()
{
    cat >&2 <<EOF
usage: sysdef.sh [-f] [-v] |run-once|run-on-upgrade|run-always [script1] [script2] [...]
       sysdef.sh [-f] [-v] run-all
       sysdef.sh [-v] list
           -f: ignore stamp, force to run
           -v: verbose
EOF
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

while [ $# -gt 0 ]; do
    case $1 in
        list|run-all|run-once|run-on-upgrade|run-always)
            action=$1
            shift
            continue
            ;;
        -v) set -x
            shift
            continue
            ;;
        -f) force=1
            shift
            continue
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ ! -d ${sysdefdir} ]; then
    echo "Dirctory ${sysdefdir} not found"
    exit 1
fi

get_bundle_dir() {
    local type="$1"
    local bundle_dir=""

    if [ $type = "run-once" ]; then
        bundle_dir="$sysdefdir/run_once.d"
    elif [ $type = "run-on-upgrade" ]; then
        local latest=`ls $sysdefdir/run_on_upgrade.d/ -1 -v -r | head -n 1`
        bundle_dir="$sysdefdir/run_on_upgrade.d/$latest"
    elif [ $type = "run-always" ]; then
        bundle_dir="$sysdefdir/run_always.d"
    fi
    echo "$bundle_dir"
}

run_single() {
    local type="$1"
    local cmd="$2"
    local bundle_dir=`get_bundle_dir $type`
    local cmd_path="$bundle_dir/$cmd"

    if [ -e "${cmd_path}.dat" ]; then
        return
    fi

    if [ -e "${cmd_path}.stamp" ] && [ $force -eq 0 ]; then
        return
    fi

    if [ $type = "run-on-upgrade" ]; then
        type="$type(${bundle_dir##*/})"
    fi

    echo "Start $type $cmd"
    /bin/sh "$cmd_path"
    if [ $? -eq 0 ]; then
        [ $type != "run-always" ] && touch "${cmd_path}.stamp"
        echo "Run $type $cmd success"
    else
        res=1
        echo "Run $type $cmd failed"
    fi
}

run_bundle() {
    local type="$1"
    local bundle_dir=`get_bundle_dir $type`
    local cmd=""

    for cmd in `ls -1 -v ${bundle_dir}/`; do
        [ "${cmd}" != "${cmd%%.dat}" ] && continue
        [ "${cmd}" != "${cmd%%.stamp}" ] && continue
        run_single $type $cmd
    done
}

run_all() {
    local type=""

    for type in run-once run-on-upgrade run-always; do
        run_bundle $type
    done
}

list_bundle() {
    local type="$1"
    local bundle_dir=`get_bundle_dir $type`
    local cmd=""

    if [ $type = "run-on-upgrade" ]; then
        type="$type(${bundle_dir##*/})"
    fi
    echo "$type"
    for cmd in `ls -1 -v ${bundle_dir}/`; do
        echo "    $cmd"
    done
}

list_all() {
    local type=""

    for type in run-once run-on-upgrade run-always; do
        list_bundle $type
    done
}

case $action in
    run-once|run-on-upgrade|run-always)
        type=$action
        if [ $# -eq 0 ]; then
            run_bundle $type
        else
            cmds=$@
            for cmd in $cmds; do
                run_single $type $cmd
            done
        fi
        ;;

    run-all)
        run_all
        ;;

    list)
        list_all
        ;;

    *)
        usage
        exit 1
        ;;
esac

exit $res
