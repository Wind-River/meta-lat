#!/bin/sh
# Update containers listed in /etc/sysdef/run_on_upgrade.d/XXXX/containers.dat
# Each line in containers.dat records how to pull and run a container
# The format of line is:
# <container-name> [load=<docker-image-tarball>|import=<fs-tarball>] [image=<container-image-name>] [run-opt=<docker-run-opt>] [run-cmd=<docker-run-cmd>]
# The `<container-name>' is mandatory, it is the name of container (docker run --name <container-name> XXX);
# If `load=<docker-image-tarball>' is set, use `docker load' to add image tarball;
# If `import=<fs-tarball>' is set, use `docker import' to add fs tarball;
# If no `load=<docker-image-tarball>' and no `import=<fs-tarball>', use `docker pull' to add image;
# The `image=<container-image-name>' is optional, if not set, use `<container-name>' by default;
# The `run-opt=<docker-run-opt>' is optional, if not set, use `-itd' by default (docker run -itd XXX);
# The `run-cmd=<docker-run-cmd>' is optional, if not set, default is empty
# If an old container has already existed, rename it
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
KEYS="load import image run-opt run-cmd"
get_val() {
    local key=$1
    value=`echo ${line} | sed -n "s/.*$key=\([^=]*\).*/\1/p"`
    for k in ${KEYS}; do
        [ $k = "$key" ] && continue
        value=${value% $k}
    done

    # Remove first and last quote from value
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    echo $value
}

res=0
dirname=`dirname ${BASH_SOURCE[0]}`
dat="${dirname}/containers.dat"
while read -r line; do
    [ "${line}" != "${line#\#}" ] && continue

    container_name=${line%% *}
    [ -z "${container_name}" ] && continue

    container_image=`get_val image`
    if [ -z "${container_image}" ]; then
        # If no `image:<container-image-name>', the image is the same with `<container-name>'
        container_image=${container_name}
    fi

    load_image=`get_val load`
    import_fs=`get_val import`
    if [ -n "${load_image}" ]; then
        if [ ! -e "${load_image}.done" ]; then
            echo "docker load -i ${load_image}"
            docker load -i ${load_image}
            if [ $? -eq 0 ]; then
                touch "${load_image}.done"
            else
                echo "docker load failed"
                continue
            fi
        fi
    elif [ -n "${import_fs}" ]; then
        if [ ! -e "${import_fs}.done" ]; then
            echo "docker import ${import_fs} ${container_image}"
            docker import ${import_fs} ${container_image}
            if [ $? -eq 0 ]; then
                touch "${import_fs}.done"
            else
                echo "docker import failed"
                continue
            fi
        fi
    else
        echo "docker pull ${container_image}"
        docker pull ${container_image}
        if [ $? -ne 0 ]; then
            echo "docker pull failed"
            # Return failure inorder to rerun
            res=1
            continue
        fi
    fi


    # Rename and stop old if it is available
    container_id=`docker ps -a --filter=name=^${container_name}$ --format {{.ID}}`
    if [ -n "$container_id" ]; then
        curtime=`date +%Y%m%d%H%M`
        echo "docker rename ${container_name} ${container_name}_$curtime"
        docker rename ${container_name} ${container_name}_$curtime
        if [ $? -ne 0 ]; then
            echo "docker rename failed"
            continue
        fi
        echo "docker stop -t 60 ${container_name}_$curtime"
        docker stop -t 60 ${container_name}_$curtime
        if [ $? -ne 0 ]; then
            echo "docker stop failed"
            continue
        fi
    fi

    # If no `run-opt: <docker-run-opt>', the docker run option is `-itd'
    run_opt=`get_val run-opt`
    if [ -z "${run_opt}" ]; then
        run_opt="-itd"
    else
        # Assure run the container in the background
        run_opt="$run_opt -d"
    fi

    run_cmd=`get_val run-cmd`

    echo "docker run ${run_opt} --name ${container_name} ${container_image} ${run_cmd}"
    docker run ${run_opt} --name ${container_name} ${container_image} ${run_cmd}
    if [ $? -ne 0 ]; then
        echo "docker run failed"
    fi
done < ${dat}

exit $res
