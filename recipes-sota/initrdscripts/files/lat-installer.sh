#!/bin/bash
#/*
#* 
#* Copyright (c) 2021 Wind River Systems, Inc.
#* 
#* This program is free software; you can redistribute it and/or modify
#* it under the terms of the GNU General Public License version 2 as
#* published by the Free Software Foundation.
#* 
#* This program is distributed in the hope that it will be useful,
#* but WITHOUT ANY WARRANTY; without even the implied warranty of
#* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#* See the GNU General Public License for more details.
#* 
#* You should have received a copy of the GNU General Public License
#* along with this program; if not, write to the Free Software
#* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#* 
#*/
source /lat-installer.hook

lat_tmp="/tmp/lat"
lat_cmdline="${lat_tmp}/cmdline"
lat_network_systemd_dir="${lat_tmp}/lat_network_systemd"
lat_network_ifupdown="${lat_tmp}/lat_network_interface"
lat_network_active="${lat_tmp}/lat_network_active"
lat_pre_script="${lat_tmp}/lat_pre_script"
lat_post_script="${lat_tmp}/lat_post_script"
lat_post_nochroot_script="${lat_tmp}/lat_post_nochroot_script"
lat_hostname="${lat_tmp}/lat_hostname"
lat_resolve="${lat_tmp}/lat_resolv_conf"
target_rootfs=""

ks_file="${lat_tmp}/lat-installer.ks"

INSTFLUX="1"
INSTOS="lat-os"

fatal() {
  echo "$@"
  exit 1
}

usage()
{
    cat >&2 <<EOF
usage: lat-installer.sh [-v] parse-ks --kickstart=<kick-file> --instflux=0|1 | pre-install | set-network --root=<root-dir> | post-install --root=<root-dir>
           -v: verbose
EOF
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

convert_mask() {
  local netmask=$1

  awk -F. '{
    split($0, octets)
    for (i in octets) {
        mask += 8 - log(2**8 - octets[i])/log(2);
    }
    print "/" mask
  }' <<< ${netmask}
}

ks_network_systemd () {
  local bootproto=""
  local device=""
  local ip=""
  local netmask=""
  local gateway==""
  local nameserver=""
  local ipv6=""
  local ipv6gateway=""
  local hostname=""
  local activate="0"
  local onboot="on"
  local noipv4="0"
  local output=""

  while [ $# -gt 0 ]; do
    val=`expr "x$1" : 'x[^=]*=\(.*\)'`
    case $1 in
      --bootproto=*)
        bootproto="$val"
        shift
        continue
        ;;
      --device=*)
        device="$val"
        shift
        continue
        ;;
      --activate)
        activate="1"
        shift
        continue
        ;;
      --onboot=*)
        onboot="$val"
        shift
        continue
        ;;
      --ip=*)
        ip="$val"
        shift
        continue
        ;;
      --netmask=*)
        netmask="$val"
        shift
        continue
        ;;
      --gateway=*)
        gateway="$val"
        shift
        continue
        ;;
      --nameserver=*)
        nameserver="$val"
        shift
        continue
        ;;
      --ipv6=*)
        ipv6="$val"
        shift
        continue
        ;;
      --ipv6gateway=*)
        ipv6gateway="$val"
        shift
        continue
        ;;
      --hostname=*)
        hostname="$val"
        shift
        continue
        ;;
      --noipv4)
        noipv4="1"
        shift
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  if [ -z "${device}" ]; then
    return
  fi

  if [ -n "${device}" ]; then
      output="${output}\n[Match]\nName=${device}\n"
    if [ "${onboot}" = "off" ]; then
      output="${output}\n[Link]\nActivationPolicy=down\n"
    elif [ "${onboot}" = "on" ]; then
      output="${output}\n[Link]\nActivationPolicy=up\n"
    fi
  fi

  if [ "${bootproto}" = "static" ]; then
    output="${output}\n[Network]"
    if [ "${noipv4}" != "1" ]; then
      if [ -z "${ip}"  ]; then
        echo "No IPv4 found for ${bootproto} ${device}"
        exit 1
      fi
      output="${output}\nAddress=${ip}"
      if [ -n "${netmask}"  ]; then
        output="${output}`convert_mask ${netmask}`"
      fi
      if [ -n "${gateway}"  ]; then
        output="${output}\nGateway=${gateway}"
      fi
      if [ -n "${nameserver}" ]; then
        output="${output}\nDNS=${nameserver}"
      fi
    fi
  elif [ "${bootproto}" = "dhcp" ]; then
    output="${output}\n[Network]"
    output="${output}\nDHCP=yes\n"
  fi

  if [ -n "${ipv6}" ]; then
    if [ "${ipv6}" != "auto" ]; then
      output="${output}\nAddress=${ipv6}"
      output="${output}\nGateway=${ipv6gateway}"
    fi
  fi

  if [ -n "${output}" ]; then
    printf "${output}\n" > ${lat_network_systemd_dir}/lat_${device}.network
  fi
}



ks_network_ifupdown () {
  local bootproto=""
  local device=""
  local ip=""
  local netmask=""
  local gateway==""
  local nameserver=""
  local ipv6=""
  local ipv6gateway=""
  local hostname=""
  local activate="0"
  local onboot="on"
  local noipv4="0"
  local output=""

  while [ $# -gt 0 ]; do
    val=`expr "x$1" : 'x[^=]*=\(.*\)'`
    case $1 in
      --bootproto=*)
        bootproto="$val"
        shift
        continue
        ;;
      --device=*)
        device="$val"
        shift
        continue
        ;;
      --activate)
        activate="1"
        shift
        continue
        ;;
      --onboot=*)
        onboot="$val"
        shift
        continue
        ;;
      --ip=*)
        ip="$val"
        shift
        continue
        ;;
      --netmask=*)
        netmask="$val"
        shift
        continue
        ;;
      --gateway=*)
        gateway="$val"
        shift
        continue
        ;;
      --nameserver=*)
        nameserver="$val"
        shift
        continue
        ;;
      --ipv6=*)
        ipv6="$val"
        shift
        continue
        ;;
      --ipv6gateway=*)
        ipv6gateway="$val"
        shift
        continue
        ;;
      --hostname=*)
        hostname="$val"
        shift
        continue
        ;;
      --noipv4)
        noipv4="1"
        shift
        continue
        ;;
      *)
        break
        ;;
    esac
  done
  echo "Set network: $bootproto, $device, $activate, $onboot, $ip, $netmask, $gateway, $nameserver, $ipv6, $ipv6gateway, $hostname, $noipv4"

  if [ -z "${device}" -a -n "${bootproto}" ]; then
    "No interface found for ${bootproto}"
    exit 1
  fi

  if [ -n "${device}" ]; then
    if [ "${onboot}" = "off" ]; then
      output="${output}\n#auto ${device}"
    elif [ "${onboot}" = "on" -a "${bootproto}" != "static" ]; then
      output="${output}\nauto ${device}"
    fi
  fi

  if [ "${bootproto}" = "static" ]; then
    if [ "${noipv4}" != "1" ]; then
      if [ -z "${ip}"  ]; then
        echo "No IPv4 found for ${bootproto} ${device}"
        exit 1
      fi
      output="${output}\nallow-hotplug ${device}"
      output="${output}\niface ${device} inet static"
      output="${output}\n     address ${ip}"
      if [ -n "${netmask}"  ]; then
        output="${output}\n     netmask ${netmask}"
      fi
      if [ -n "${gateway}"  ]; then
        output="${output}\n     gateway ${gateway}"
      fi
    fi
  elif [ "${bootproto}" = "dhcp" ]; then
    output="${output}\niface ${device} inet dhcp"
  fi

  if [ -n "${ipv6}" ]; then
    if [ "${bootproto}" = "static" ]; then
      output="${output}\nauto ${device}"
    fi
    if [ "${ipv6}" = "auto" ]; then
      output="${output}\niface ${device} inet6 auto"
    else
      output="${output}\niface ${device} inet6 static"
      output="${output}\n     address ${ipv6}"
      if [ -n "${ipv6gateway}"  ]; then
        output="${output}\n     gateway ${ipv6gateway}"
      fi

    fi
  fi

  if [ "${activate}" = "1" ]; then
    printf "${output}\n" >> ${lat_network_active}
  fi
  printf "${output}\n" >> ${lat_network_ifupdown}

  if [ -n "${hostname}" ];then
    echo "${hostname}" >> ${lat_hostname}
  fi

  if [ -n "${nameserver}" ]; then
    echo "nameserver ${nameserver}" >> ${lat_resolve}
  fi
}

ks_lat_disk () {
  boot_params=""
  while [ $# -gt 0 ]; do
    val=`expr "x$1" : 'x[^=]*=\(.*\)'`
    case $1 in
      --install-device=*)
        boot_params="$boot_params instdev=$val"
        shift
        continue
        ;;
      --fat-size=*)
        boot_params="$boot_params FSZ=$val"
        shift
        continue
        ;;
      --boot-size=*)
        boot_params="$boot_params BSZ=$val"
        shift
        continue
        ;;
      --root-size=*)
        boot_params="$boot_params RSZ=$val"
        shift
        continue
        ;;
      --var-size=*)
        boot_params="$boot_params VSZ=$val"
        shift
        continue
        ;;
      --inst-flux=*)
        boot_params="$boot_params instflux=$val"
        shift
        continue
        ;;
      --timeout=*)
        boot_params="$boot_params instw=$val"
        shift
        continue
        ;;
      *)
        break
        ;;
    esac
  done
  echo "Set install device: $boot_params"
  echo "$boot_params" > ${lat_cmdline}
}

ks_pre_script() {
  local script=""
  local i=0

  mkdir -p ${lat_pre_script}
  sed -e '/^%pre-part/,/^%end$/d' "${ks_file}" | sed -e '/^%pre/,/^%end$/!d' | while read -r line
  do
    [ "${line::1}" = "#" -o "${line::1}" = "" -o "${line::1}" = " " ] && continue

    if [ "${line::4}" = "%pre" ]; then
      script="${lat_pre_script}/${i}_script"
      local shebang=`expr "$line" : '.*--interpreter=\(.*\)[ $]'`
      if [ -z "$shebang" ]; then
        shebang="/bin/sh"
      fi
      echo "#!${shebang}" > ${script}
    elif [ "${line::4}" = "%end" ]; then
      chmod a+x ${script}
      i=$((i+1))
    elif [ "${line::4}" != "%end" ]; then
      echo "$line" >> ${script}
    fi
  done
}

ks_post_script() {
  local script=""
  local i=0

  mkdir -p ${lat_post_script} ${lat_post_nochroot_script}
  sed -e '/^%post/,/^%end$/!d' "${ks_file}" | while read -r line
  do
    [ "${line::1}" = "#" -o "${line::1}" = "" ] && continue

    if [ "${line::5}" = "%post" ]; then
      local nochroot=`expr "$line" : '.* --\(nochroot\)'`
      if [ "$nochroot" = "nochroot" ]; then
        script="${lat_post_nochroot_script}/${i}_script"
      else
        script="${lat_post_script}/${i}_script"
      fi

      local shebang=`expr "$line" : '.*--interpreter=\(.*\)[ $]'`
      if [ -z "$shebang" ]; then
        shebang="/bin/sh"
      fi
      echo "#!${shebang}" > ${script}
    elif [ "${line::4}" = "%end" ]; then
      chmod a+x ${script}
      i=$((i+1))
    elif [ "${line::4}" != "%end" ]; then
      echo "$line" >> ${script}
    fi
  done
}

parse_ks() {
  if [ ! -f ${ks_file} ]; then
    fatal "Kicksart file \"${ks_file}\" not found"
  fi

  while read -r line
  do
    [ "${line::1}" = "#" -o "${line::1}" = "" ] && continue

    if [ "${line::8}" = "network " ]; then
      echo "network: $line"
      ks_network_ifupdown ${line:8}
      ks_network_systemd ${line:8}
    elif [ "${line::9}" = "lat-disk " ]; then
      ks_lat_disk ${line:9}
    fi
  done <"${ks_file}"

  # Reactive network
  if [ -e "${lat_network_active}" ]; then
    if [ -f /sbin/udhcpc ]; then
      killall -12 udhcpc
      killall -9 udhcpc
    elif [ -f /usr/sbin/udhcpd ]; then
      killall -12 udhcpd
      killall -9 udhcpd
    fi
    cp -f ${lat_network_active} /etc/network/interfaces
    /etc/init.d/networking restart
    if [ $? -ne 0 ]; then
      fatal "Reactive network failed"
    fi
  fi

  ks_parse_hook "%ks-early" "${lat_ks_early}"

  ks_parse_hook "%pre-part" "${lat_pre_part}"

  ks_parse_hook "%part" "${lat_create_part}"

  ks_parse_hook "%mkfs" "${lat_make_fs}"

  ks_pre_script

  ks_post_script
}

pre_install() {
  local script=""
  for script in `find ${lat_pre_script} -type f`; do
    echo "Run pre install script ${script}"
    ${script}
    if [ $? -ne 0 ]; then
      fatal "Run pre install script ${script} failed"
    fi
  done
}

post_install() {
  local script=""
  set -e
  mount --bind /sysroot/boot ${target_rootfs}/boot
  mount --bind /sysroot/boot/efi ${target_rootfs}/boot/efi
  if [ "${INSTFLUX}" = 1 ] ; then
    mount LABEL=fluxdata ${target_rootfs}/var
  else
    mount --bind /sysroot/ostree/deploy/${INSTOS}/var ${target_rootfs}/var
  fi
  mount --bind /proc ${target_rootfs}/proc
  mount --bind /sys ${target_rootfs}/sys
  mount --bind /dev ${target_rootfs}/dev
  mount --bind /dev/pts ${target_rootfs}/dev/pts
  mount --bind /tmp ${target_rootfs}/tmp
  mount --bind /run ${target_rootfs}/run

  mkdir -p ${target_rootfs}/var/home ${target_rootfs}/var/rootdirs/{opt,mnt,media,srv,root}

  for script in `find ${lat_post_script} -type f`; do
    echo "Run post install script ${script} in ${target_rootfs}"
    chroot ${target_rootfs} ${script}
    if [ $? -ne 0 ]; then
      fatal "Run post install script ${script} in ${target_rootfs} failed"
    fi
  done

  for script in `find ${lat_post_nochroot_script} -type f`; do
    echo "Run post install nochroot script ${script}"
    IMAGE_ROOTFS=${target_rootfs} ${script}
    if [ $? -ne 0 ]; then
      fatal "Run post install nochroot script ${script} failed"
    fi
  done

  umount ${target_rootfs}/boot/efi
  umount ${target_rootfs}/boot
  umount ${target_rootfs}/var
  umount ${target_rootfs}/proc
  umount ${target_rootfs}/sys
  umount ${target_rootfs}/dev/pts
  umount ${target_rootfs}/dev
  umount ${target_rootfs}/tmp
  umount ${target_rootfs}/run
  set +e
}

set_network() {
  # Ifupdown
  if [ -d /etc/network/interfaces.d ]; then
    if [ -f ${lat_network_ifupdown} ]; then
      lat_interface="${target_rootfs}/etc/network/interfaces.d"
      mkdir -p ${lat_interface}
      cp ${lat_network_ifupdown} ${lat_interface}/lat_nework
      echo "Deploy ${lat_interface}"
    fi

    if [ -f ${lat_resolve} ]; then
      cat ${lat_resolve} >> ${target_rootfs}/etc/resolv.conf
    fi
  # Systemd-networkd
  else
    lat_networkd="${target_rootfs}/etc/systemd/network/"
    mkdir -p ${lat_networkd}
    for conf in `find ${lat_network_systemd_dir} -type f`; do
      cp $conf ${lat_networkd}
      echo "Deploy ${lat_networkd}${conf##*/}"
    done
  fi

  if [ -f ${lat_hostname} ]; then
    cat ${lat_hostname} > ${target_rootfs}/etc/hostname
  fi


}

while [ $# -gt 0 ]; do
  val=`expr "x$1" : 'x[^=]*=\(.*\)'`
  case $1 in
    parse-ks|set-network|pre-install|post-install)
      action=$1
      shift
      continue
      ;;
    -v)
      set -x
      shift
      continue
      ;;
    --kickstart=*)
      rm -rf ${lat_tmp}
      mkdir -p ${lat_tmp}
      mkdir -p ${lat_network_systemd_dir}
      curl $val -s --output $ks_file
      if [ $? -ne 0 ]; then
        fatal "Download kickstart file $val failed"
      fi
      shift
      continue
      ;;
    --root=*)
      target_rootfs=$val
      if [ -z "${target_rootfs}" -o ! -d "${target_rootfs}" ]; then
        fatal "Root dir ${target_rootfs} not found"
      fi
      shift
      continue
      ;;
    --instflux=*)
      INSTFLUX=$val
      shift
      continue
      ;;
    --instos=*)
      INSTOS=$val
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

if [ "$action" = "parse-ks" ]; then
  parse_ks
elif [ "$action" = "pre-install" ]; then
  pre_install
elif [ "$action" = "post-install" ]; then
  post_install
elif [ "$action" = "set-network" ]; then
  set_network
fi

