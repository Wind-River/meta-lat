#!/bin/sh
#
# Copyright (c) 2019 Wind River Systems, Inc.
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
# This is a reference implementation for initramfs install
# The kernel arguments to use an install are as follows:
#

helptxt() {
	cat <<EOF
Usage: This script is intended to run from the initramfs and use the ostree
binaries in the initramfs to install a file system onto a disk device.

The arguments to this script are passed through the kernel boot arguments.

REQUIRED:
 rdinit=/install		- Activates the installer
 fromdev=/dev/YOUR_DEVCICE	- The device of installer image, PUUID=x, UUID=y, LABEL=x
 instdev=/dev/YOUR_DEVCICE	- One or more devices separated by a comma
	  where the first valid device found is used as the install device,
          OR use "ask" to ask for device, OR use LABEL=x, PUUID=x, UUID=x
 instname=OSTREE_REMOTE_NAME	- Remote name like @OSTREE_OSNAME@
 instbr=OSTREE_BRANCH_NAME	- Branch for OSTree to use
 insturl=OSTREE_URL		- URL to OSTree repository

OPTIONAL:
 bl=booloader			- grub, ufsd(u-boot fdisk sd)
 instw=#			- Number of seconds to wait before erasing disk
 instab=0			- Do not use the AB layout, only use A
 instnet=0			- Do not invoke udhcpc or dhcpcd
    				- instnet=dhcp, use dhcp ipv4
    				- instnet=dhcp6, use dhcp ipv6
   If the above is 0, use the kernel arg:
    ip=<client-ip>::<gw-ip>:<netmask>:<hostname>:<device>:off:<dns0-ip>:<dns1-ip>
   Example:
    ip=10.0.2.15::10.0.2.1:255.255.255.0:tgt:eth0:off:10.0.2.3:8.8.8.8
 LUKS=0				- Do not create encrypted volumes
 LUKS=1				- Encrypt var volume (requires TPM)
 LUKS=2				- Encrypt var and root volumes (requires TPM)
 LUKS=3				- Encrypt var, boot and root volumes (requires TPM)
 instflux=0			- Do not create/use the fluxdata partition for /var
 instl=DIR			- Local override ostree repo to install from
 instsh=1			- Start a debug shell
 instsh=2			- Use verbose logging
 instsh=3			- Use verbose logging and start shell
 instsh=4			- Display the help text and start a shell
 instpost=halt			- Halt at the end of install vs reboot
 instpost=exit			- exit at the end of install vs reboot
 instpost=shell		- shell at the end of install vs reboot
 instos=OSTREE_OS_NAME		- Use alternate OS name vs @OSTREE_OSNAME@
 instsbd=1			- Turn on the skip-boot-diff configuration
 instsf=1			- Skip fat partition format
 instfmt=1			- Set to 0 to skip partition formatting
 instpt=1			- Set to 0 to skip disk partitioning
 instgpg=0			- Turn off OSTree GnuPG signing checks
 instdate=datespec	        - Argument to "date -u -s" like @1577836800
 dhcpargs=DHCP_ARGS		- Args to "udhcpc -i" or "dhcpcd" like wlan0
				  ask = Ask which interface to use
 BOOTIF=BOOT_IF_MAC	- MAC address of the net interface, its interface is used by dhcp client
                      	  MAC format, such as BOOTIF=52:54:00:12:34:56 or BOOTIF=01-52-54-00-12-34-56
 wifi=ssid=YOUR_SSID;psk=your_key - Setup via wpa_cli for authentication
 wifi=ssid=YOUR_SSID;psk=ask    - Ask for password at run time
 wifi=scan                      - Dynamically Construct wifi wpa_supplicant
 ecurl=URL_TO_SCRIPT		- Download+execute script before disk prep
 ecurlarg=ARGS_TO_ECURL_SCRIPT	- Arguments to pass to ecurl script
 lcurl=URL_TO_SCRIPT		- Download+execute script after install
 lcurlarg=ARGS_TO_ECURL_SCRIPT	- Arugments to pass to lcurl script
 ks=ARGS_TO_KICKSTART		- Download+apply kickstart setting
 instiso=ISO_LABEL		- The label of installer ISO image
 Disk sizing
 biosplusefi=1	 		- Create one GPT disk to support booting from both of BIOS and EFI
 defaultkernel=<kernel>	- Choose which kernel to boot, support filename wildcard
		                  defaultkernel=vmlinuz-*[!t]-amd64 means standard kernel
		                  defaultkernel=vmlinuz-*-rt-amd64 means real time kernel
 kernelparams=a=b,c=d	- Set kernel params to installed OS, use `,' to split multiple params

 efibootfirst=1		- Set EFI boot from disk entry as first order
 devmd=0			- Set to 0 to skip the call of 'mdadm --assemble --scan'
 BLM=#				- Blocks of boot magic area to skip
				  ARM BSPs with SD cards usually need this
 FSZ=#				- MB size of fat partition
 BSZ=#				- MB size of boot partition
 RSZ=#				- MB size of root partition
 VSZ=#				- MB size of var partition (0 for auto expand)

EOF
}

log_info() { echo "$0[$$]: $*" >&2; }
log_error() { echo "$0[$$]: ERROR $*" >&2; }

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib/ostree:/usr/lib64/ostree

source /lat-installer.hook

lreboot() {
	echo b > /proc/sysrq-trigger
	while [ 1 ] ; do
		sleep 60
	done
}

conflict_label() {
	local op=$1
	local 'label' 'd' 'devs' 'conflict' 'i' 'fstype'
	conflict=1
	for label in otaefi boot otaboot otaboot_b otaroot otaroot_b fluxdata; do
		devs=$(blkid -t LABEL=$label -o device |grep -v $INSTDEV)
		if [ "$devs" != "" ] ; then
			i=0
			for d in $devs; do
				i=$(($i+1))
				if [ "$op" = "print" ] ; then
					echo Change $label to ${label}_${i} on $d
				else
					echo Changing $label to ${label}_${i} on $d
					fstype=$(lsblk $d -n -o FSTYPE)
					if [ "$fstype" = vfat ] ; then
						dosfslabel $d ${label}_${i}
					elif [ "$fstype" != ${fstype#ext} ] ; then
						e2label $d ${label}_${i}
					else
						fatal "Could not handle FSTYPE $fstype"
					fi
				fi
			done
			conflict=0
		fi
	done
	return $conflict
}

ask_fix_label() {
	local reply
	while [ 1 ] ; do
		conflict_label print
		if [ $? -eq 0 ];then
			echo "Partition labels above need to altered for proper install."
			echo "B - Reboot"
			IFS='' read -p "FIX: (y/n/B)" -r reply
			[ "$reply" = "B" ] && echo b > /proc/sysrq-trigger;
			if [ "$reply" = "y" ] ; then
				conflict_label fix
			elif [ "$reply" = "n" ] ; then
				break
			fi
		else
			break
		fi
	done
}

# The valid dev should be not ISO disk
check_valid_dev() {
	local heading
	instdev=$1
	blkid --match-token LABEL=${ISO_INSTLABEL} -o device $instdev
	if [ $? -eq 0 ];then
		echo "$instdev is ISO disk"
		return 1
	fi
	return 0
}

ask_dev() {
	local 'heading' 'inp' 'i' 'reply' 'reply2' 'out' 'choices'
	fix_part_labels=0
	heading="    `lsblk -o NAME,VENDOR,SIZE,MODEL,TYPE,LABEL |head -n 1`"
	arch=$(uname -m)
	while [ 1 ] ; do
		# Filter out <=100MB (104857600 byte) disk
		allow_disks=`lsblk -n  -o PATH,SIZE,TYPE -b -x SIZE |grep disk | awk '{ if ($2 > 104857600) { print $1} }'`
		choices=()
		while IFS="" read -r inp; do
			choices+=("$inp")
		done<<< $(lsblk -n -o NAME,VENDOR,SIZE,MODEL,TYPE,LABEL -x SIZE $allow_disks |grep disk|grep -v " ${ISO_INSTLABEL}$")
		echo "$heading"
		for i in ${!choices[@]}; do
			[ "${choices[$i]}" = "" ] && continue
			echo "$i - ${choices[$i]}"
			if [ "$arch" != "x86_64" -a -n "$fname" ]; then
				echo "${choices[$i]}" | awk '{ print $1}' | grep "$fname" -q
				if [ $? -eq 0 ]; then
					prompt_index=$i
				fi
			fi
		done

		if [ "$arch" = "x86_64" -o -z "$fname" ]; then
			prompt_index=$i
		fi

		echo "B - Reboot"
		echo "R - Refresh"
		echo ""
		IFS='' read -p "Press Enter to install on $(echo ${choices[$prompt_index]}|awk '{print $1}') or Esc to select a different device?" -r -s -n1 reply
		echo ""
		out=0
		re='^[0-9]+$'
		[ "$reply" = "B" ] && echo b > /proc/sysrq-trigger;
		[ "$reply" = "R" ] && continue;
		if [ "$reply" = $'\e' ]; then
			IFS='' read -p "Select disk to format and install: " -r reply
			while ! [[ $reply =~ $re ]] || [ "$reply" -lt 0 ] || [ "$reply" -gt $i ]; do
				index_scope="0"
				if [ ${#choices[@]} -gt 1 ]; then
					index_scope="$index_scope ~ $i"
				fi
				IFS='' read -p "The number $index_scope is required: "  -r reply
			done
			out=1
		elif [ "$reply" = "" ] ; then
			reply=$prompt_index
			out=1
			des="${choices[$prompt_index]}"
			echo "Choose to install on disk: $prompt_index (${des% })"
		fi
		if [ $out = 1 ] ; then
			echo ""
			i=$(echo ${choices[$reply]}|awk '{print $1}')
			if [ "$arch" != "x86_64" -a "$reply" != "$prompt_index" ]; then
				echo "WARNING: You choose to install on *$i* which is not the suggested disk *$(echo ${choices[$prompt_index]}|awk '{print $1}')*"
				echo "WARNING: It may fail to install and re-install repeatedly, or failed to boot after installed."
			fi
			blkid -p /dev/${i}* | grep ' TYPE=' | grep -v "LABEL=\"${ISO_INSTLABEL}\"" -q
			if [ $? -eq 0 ]; then
				IFS='' read -p "The disk /dev/$i is not empty, ERASE /dev/$i (y/n) " -r reply2
				if [ "$reply2" != "y" ] ; then
					continue
				fi

				IFS='' read -p "Are you sure to ERASE /dev/$i (y/n) " -r reply2
				if [ "$reply2" = "y" ] ; then
					INSTDEV=/dev/$i
					check_valid_dev $INSTDEV || fatal "Could not install to disk of installer ISO image"
					break
				fi
			else
				IFS='' read -p "ERASE /dev/$i (y/n) " -r reply2
				if [ "$reply2" = "y" ] ; then
					INSTDEV=/dev/$i
					check_valid_dev $INSTDEV || fatal "Could not install to disk of installer ISO image"
					break
				fi
			fi
		fi
	done
	ask_fix_label
}

ask() {
	local 'char' 'charcount' 'prompt' 'reply'
	prompt="$1"
	charcount='0'
	reply=''
	while IFS='' read -n '1' -p "${prompt}" -r -s 'char'; do
            case "${char}" in
		# Handles NULL
		( $'\000' )
		break
		;;
		# Handle Control-U
		($'\025' )
		    prompt=''
		    while [ $charcount -gt 0 ] ; do
			prompt=$prompt$'\b \b'
			(( charcount-- ))
		    done
		    charcount=0
		    reply=''
		    ;;
		# Handles BACKSPACE and DELETE
		( $'\010' | $'\177' )
		if (( charcount > 0 )); then
		    prompt=$'\b \b'
		    reply="${reply%?}"
		    (( charcount-- ))
		else
		    prompt=''
		fi
		;;
		( * )
		prompt='*'
		reply+="${char}"
		(( charcount++ ))
		;;
            esac
	done
	printf "\n"
	askpw="$reply"
}

ask_psk() {
	local netnum=$2
	local var=$3
	while [ 1 ] ; do
		ask "$1"
		if [ "$askpw" != "" ] ; then
			val="$askpw"
			wpa_cli set_network $netnum $var \"$val\"|grep -q ^OK
			if [ $? == 0 ] ; then
				break
			else
				echo "Invalid characters or length of password"
			fi
		fi
	done
}

wifi_scan() {
	local i before after
	while [ 1 ] ; do
		bss=()
		freq=()
		sigl=()
		flags=()
		ssid=()
		wpa_cli scan > /dev/null
		sleep 2
		while IFS="" read -r inp; do
			[ "$inp" != "${inp#Selected}" ] && continue
			[ "$inp" != "${inp#bssid}" ] && continue
			before=${inp%%$'\t'*}
			after=${inp#*$'\t'}
			bss+=("$before")
			before=${after%%$'\t'*}
			after=${after#*$'\t'}
			freq+=("$before")
			before=${after%%$'\t'*}
			after=${after#*$'\t'}
			sigl+=("$before")
			before=${after%%$'\t'*}
			after=${after#*$'\t'}
			flags+=("${before//\[ESS\]/}")
			ssid+=("$after")
		done <<< $(wpa_cli scan_results)
		echo "SSID/BSSID/Frequency/Signal Level/Flags/"
		for i in ${!bss[@]}; do
			[ "${ssid[$i]}" = "" ] && continue
			echo "$i - ${ssid[$i]}/${bss[$i]}/${freq[$i]}/${sigl[$i]}/${flags[$i]}"
		done
		echo "R - Rescan"
		echo "B - Reboot"
		while [ 1 ] ; do
			IFS='' read -p "Selection: " -r reply
			[ "$reply" = "r" ] && reply=R
			[ "$reply" = "R" ] && break;
			[ "$reply" = "B" ] && echo b > /proc/sysrq-trigger;
			[ "$reply" -ge 0 -a "$reply" -lt ${#bss[@]} ] 2> /dev/null && break
		done
		[ $reply != "R" ] && break
	done
	# Setup WiFi Parameters
	SSID="${ssid[$reply]}"
	FWIFI="${flags[$reply]}"
}

do_wifi() {
	retry=0
	while [ $retry -lt 100 ] ; do
		ifconfig ${DHCPARGS% *} > /dev/null 2>&1 && break
		retry=$(($retry+1))
		sleep 0.1
	done
	if [ $retry -ge 100 ] ;then
		fatal "Error could not find interface ${DHCPARGS% *}"
	fi
	wpa_supplicant -i ${DHCPARGS} -c /etc/wpa_supplicant.conf -B
	if [ "${WIFI}" != "" ] ; then
		while [ 1 ] ; do
			wpa_cli remove_network 0 > /dev/null
			netnum=`wpa_cli add_network |tail -1`
			# Assume psk= is last in case there is a ; in the psk
			WIFI_S=""
			if [ "$WIFI" = "scan" ] ; then
				wifi_scan
				wpa_cli set_network $netnum ssid "\"$SSID\"" > /dev/null
				if [ "$FWIFI" != "${FWIFI/EAP/}" ] ; then
					IFS='' read -p "EAP User ID: " -r reply
					wpa_cli set_network $netnum key_mgmt WPA-EAP > /dev/null
					wpa_cli set_network $netnum identity "\"$reply\"" > /dev/null
					ask_psk "EAP Password: " $netnum password
				else
					ask_psk "WiFi Password: " $netnum psk > /dev/null
				fi
			else
				psk=${WIFI##*;psk=}
				WIFI_S="${WIFI%;psk=*}"
				WIFI_S="${WIFI_S//;/ }"
				if [ "$psk" != "" ] ; then
					WIFI_S="$WIFI_S psk=$psk"
				fi
			fi
			for k in $WIFI_S; do
				var=${k%%=*}
				val=${k#*=}
				if [ "$var" = "psk" -a "$val" = "ask" ] ; then
					ask_psk "WiFi Password: " $netnum psk
				fi
				# Try with quotes first
				wpa_cli set_network $netnum $var \"$val\"|grep -q ^OK
				if [ $? != 0 ] ; then
					wpa_cli set_network $netnum $var $val|grep -q ^OK || \
						echo "Error: with wpa_cli set_network $netnum $var $val"
				fi
			done
			wpa_cli enable_network $netnum
			# Allow up to 20 seconds for network to come ready
			retry=0
			timeout=$((4*20))
			while [ $retry -lt $timeout ] ; do
				state=`wpa_cli status |grep wpa_state=`
				if [ "$state" != "${state/COMPLETED/}" ] ; then
					break
				fi
				sleep .250
				retry=$(($retry+1))
			done
			if [ "$state" != "${state/COMPLETED/}" -o "$state" != "${state/CONNECTED/}" ] ; then
				echo "WiFi Acitvated"
				break
			fi
			if [ "$psk" = "ask" -o "WIFI" = "scan" ] ; then
				echo "Error: Failed to connect to WiFi"
				wpa_cli disable_network $netnum > /dev/null
				wpa_cli flush $netnum > /dev/null
				continue
			fi
			fatal "Error: Failed to establish WiFi link."
		done
	fi
}

do_dhcp() {
	if [ "$dhcp_done" = 1 ] ; then
		return
	fi

	# If no network needed do not conifgure it
	if [ "${ECURL}" = "" -o "${ECURL}" = "none" ] && [ "${LCURL}" = "" -o "${LCURL}" = "none" ] && [ "$INSTL" != "" ] && [ "${KS}" = "" -o "${KS::7}" = "file://" ] ; then
		return
	fi

        max_retries=10
        retries=0
        while [ "$(ls /sys/class/net |grep -v ^lo\$ |grep -v ^sit0 | grep -v can)" == "" ];
        do
             if [ $retries -ge $max_retries ]; then
                 fatal "Retried $max_retries times,  but no valid interaface"
             fi
             retries=$((retries+1))
             sleep 1
        done

	if [ "${DHCPARGS}" = "ask" ] ; then
		while [ 1 ] ; do
			echo "Select an interface to use"
			iface=()
			while IFS="" read -r inp; do
				iface+=($inp)
			done <<< $(ls /sys/class/net |grep -v ^lo\$ |grep -v ^sit0)
			for i in ${!iface[@]}; do
				echo "$i - ${iface[$i]}"
			done
			echo "B - Reboot"
			IFS='' read -p "Selection: " -r reply
			[ "$reply" = "B" ] && echo b > /proc/sysrq-trigger;
			[[ "$reply" =~ ^[0-9]+$ ]] && [ "$reply" -ge 0 -a "$reply" -lt ${#iface[@]} ] && break
		done
		DHCPARGS="${iface[$reply]}"
	elif [ -z "${DHCPARGS}" -a -n "${BOOTIF}" ] ; then
		cd /sys/class/net/
		for addr in $(ls */address); do
			mac=$(cat $addr)
			if [ ${BOOTIF} = $mac ]; then
				DHCPARGS="${addr%%/address}"
				break
			fi
		done
		if [ -z "${DHCPARGS}" ]; then
			fatal "No interface (mac ${BOOTIF}) found"
		fi
		cd -
	fi
	dhcp_done=1
	if [ -f /sbin/wpa_supplicant -a "${DHCPARGS}" != "${DHCPARGS#w}" ] ; then
		# Activate wifi
		do_wifi
	fi
	if [ "$INSTNET" = dhcp ] ; then
		if [ -f /sbin/udhcpc ] ; then
			# Assume first arg is ethernet inteface
			if [ "${DHCPARGS}" != "" ] ; then
				/sbin/udhcpc -i ${DHCPARGS}
			else
				while read nic; do
					/sbin/udhcpc -i $nic -n
				done <<< $(ls /sys/class/net |grep -v ^lo\$ |grep -v ^sit0 | grep -v can)
			fi
		else
			dhcpcd ${DHCPARGS}
		fi
	elif [ "$INSTNET" = dhcp6 ] ; then
		if [ -f /usr/sbin/dhclient ] ; then
			# Assume first arg is ethernet inteface
			if [ "${DHCPARGS}" != "" ] ; then
				/usr/sbin/dhclient -6 -i ${DHCPARGS}
			else
				/usr/sbin/dhclient -6
			fi
		else
			dhcpcd -6 ${DHCPARGS}
		fi

	fi
}


do_mount_fs() {
	echo "mounting FS: $*"
	[[ -e /proc/filesystems ]] && { grep -q "$1" /proc/filesystems || { log_error "Unknown filesystem"; return 1; } }
	[[ -d "$2" ]] || mkdir -p "$2"
	[[ -e /proc/mounts ]] && { grep -q -e "^$1 $2 $1" /proc/mounts && { log_info "$2 ($1) already mounted"; return 0; } }
	mount -t "$1" "$1" "$2" || fatal "Error mounting $2"
}

early_setup() {
	do_mount_fs proc /proc
	read_args
	do_mount_fs sysfs /sys
	mount -t devtmpfs none /dev
	mkdir -p /dev/pts
	mount -t devpts none /dev/pts
	do_mount_fs tmpfs /tmp
	do_mount_fs tmpfs /run

	$_UDEV_DAEMON --daemon
	udevadm trigger --action=add

	if [ -x /sbin/mdadm -a "$DEVMD" = "1" ]; then
		/sbin/mdadm -v --assemble --scan --auto=md
	fi

	if [ -e "/sys/fs/selinux" ];then
		do_mount_fs selinuxfs /sys/fs/selinux
		echo 1 > /sys/fs/selinux/disable
	fi
}

udev_daemon() {
	OPTIONS="/sbin/udev/udevd /sbin/udevd /lib/udev/udevd /lib/systemd/systemd-udevd"

	for o in $OPTIONS; do
		if [ -x "$o" ]; then
			echo $o
			return 0
		fi
	done

	return 1
}

fatal() {
    echo $1
    echo
    if [ -e /install.log -a -e /tmp/lat/report_error_log.sh ]; then
        /bin/bash /tmp/lat/report_error_log.sh
    elif [ -e /install.log ]; then
        datetime=$(date +%y%m%d-%H%M%S)
        for label in otaefi boot instboot; do
            local _dev=$(blkid --label $label -o device)
            if [ "$_dev" != "" ] ; then
                faillog=install-fail-$datetime.log
                echo "Save $faillog to partition $_dev"
                if [ -e /proc/mounts ] && grep -q -e "^$_dev" /proc/mounts; then
                    dev_dir=$(cat /proc/mounts  |  grep "^$_dev" | awk '{print $2}')
                    cp /install.log $dev_dir/$faillog
                    chmod 644 $dev_dir/$faillog
                    sync
                else
                    mkdir -p /t
                    mount -o rw,noatime $_dev /t
                    sleep 2
                    cp /install.log /t/$faillog
                    chmod 644 /t/$faillog
                    sync
                    umount /t
                fi
            fi
        done
    fi
    if [ "$INSTPOST" = "exit" ] ; then exit 1 ; fi

    echo "Install failed, starting boot shell.  System will reboot on exit"
    echo "You can execute the install with verbose message:"
    echo "     INSTSH=0 bash -v -x /install"
    shell_start exec
    lreboot
}

detect_tpm_chip() {
    [ ! -e /sys/class/tpm ] && echo "TPM subsystem is not enabled." && return 1

    local tpm_devices=$(ls /sys/class/tpm)
    [ -z "$tpm_devices" ] && echo "No TPM chip detected." && return 1

    local tpm_absent=1
    local name=""
    for name in $tpm_devices; do
        grep -q "TCG version: 1.2" "/sys/class/tpm/$name/device/caps" 2>/dev/null &&
            echo "TPM 1.2 device $name is not supported." && break

        grep -q "TPM 2.0 Device" "/sys/class/tpm/$name/device/description" 2>/dev/null &&
            tpm_absent=0 && break

    grep -q "TPM 2.0 Device" "/sys/class/tpm/$name/device/firmware_node/description" 2>/dev/null &&
            tpm_absent=0 && break
    ls "/sys/class/tpm/$name/device/driver" | grep -q MSFT0101 && tpm_absent=0 && break
    done

    [ $tpm_absent -eq 1 ] && echo "No supported TPM device found." && return 1

    local name_in_dev="$name"
    # /dev/tpm is the alias of /dev/tpm0.
    [ "$name_in_dev" = "tpm0" ] && name_in_dev+=" tpm"

    local _name=""
    for _name in $name_in_dev; do
        [ -c "/dev/$_name" ] && break

        local major=$(cat "/sys/class/tpm/$name/dev" | cut -d ":" -f 1)
        local minor=$(cat "/sys/class/tpm/$name/dev" | cut -d ":" -f 2)
        ! mknod "/dev/$_name" c $major $minor &&
            echo "Unable to create tpm device node $_name." && return 1

        break
    done

    echo "TPM device /dev/$_name detected."

    return 0
}

# Global Variable setup
# default values must match ostree-settings.inc
BLM=2506
FSZ=32
BSZ=200
RSZ=1400
VSZ=0
# end values from ostree-settings.inc
LUKS=0
DEVMD=1
BIOSPLUSEFI=0
DEFAULT_KERNEL=""
EFIBOOT_FIRST=0
_UDEV_DAEMON=`udev_daemon`
INSTDATE=${INSTDATE=""}
INSTSH=${INSTSH=""}
INSTNET=${INSTNET=""}
INSTW=${INSTW=""}
INSTDEV=${INSTDEV=""}
INSTAB=${INSTAB=""}
INSTPOST=${INSTPOST=""}
INSTOS=${INSTOS=""}
INSTNAME=${INSTNAME=""}
BL=${BL=""}
INSTL=${INSTL=""}
INSTPT=${INSTPT=""}
INSTFMT=${INSTFMT=""}
INSTBR=${INSTBR=""}
INSTSBD=${INSTSBD=""}
INSTURL=${INSTURL=""}
INSTGPG=${INSTGPG=""}
INSTSF=${INSTSF=""}
INSTFLUX=${INSTFLUX=""}
BOOTIF=${BOOTIF=""}
DHCPARGS=${DHCPARGS=""}
ISO_INSTLABEL=${ISO_INSTLABEL="instboot-iso"}
WIFI=${WIFI=""}
ECURL=${ECURL=""}
ECURLARG=${ECURLARG=""}
LCURL=${LCURL=""}
LCURLARG=${LCURLARG=""}
CONSOLES=""
OSTREE_CONSOLE=""
KERNEL_PARAMS=""
IP=""
MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE=60
OSTREE_KERNEL_ARGS=${OSTREE_KERNEL_ARGS=%OSTREE_KERNEL_ARGS%}
KS=""

if [ "$OSTREE_KERNEL_ARGS" = "%OSTREE_KERNEL_ARGS%" ] ; then
	OSTREE_KERNEL_ARGS="ro rootwait"
fi

read_args() {
	[ -z "$CMDLINE" ] && CMDLINE=`cat /proc/cmdline`
	for arg in $CMDLINE; do
		optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
		case $arg in
			console=*)
				CONSOLES="$CONSOLES ${optarg%,*}"
				OSTREE_CONSOLE="$OSTREE_CONSOLE $arg"
				;;
			kernelparams=*)
				KERNEL_PARAMS="${optarg//,/ }"
				;;
			ks=*)
				KS="$optarg"
				;;
			bl=*)
				BL=$optarg ;;
			instnet=*)
				INSTNET=$optarg ;;
			instsh=*)
				if [ "$INSTSH" = "" ] ; then
					INSTSH=$optarg
					if [ "$INSTSH" = 2 -o "$INSTSH" = 3 ] ; then
						set -xv
					fi
				fi
				;;
			ip=*)
				IP=$optarg ;;
			instl=*)
				INSTL=$optarg ;;
			fromdev=*)
				FROMDEV=$optarg ;;
			instdev=*)
				INSTDEV=$optarg ;;
			instw=*)
				INSTW=$optarg ;;
			instab=*)
				INSTAB=$optarg ;;
			instpost=*)
				if [ "$INSTPOST" = "" ] ; then INSTPOST=$optarg; fi ;;
			instname=*)
				INSTNAME=$optarg ;;
			instsf=*)
				INSTSF=$optarg ;;
			instbr=*)
				INSTBR=$optarg ;;
			instsbd=*)
				INSTSBD=$optarg ;;
			instpt=*)
				INSTPT=$optarg ;;
			instfmt=*)
				INSTFMT=$optarg ;;
			insturl=*)
				INSTURL=$optarg ;;
			instgpg=*)
				INSTGPG=$optarg ;;
			instdate=*)
				INSTDATE=$optarg ;;
			instflux=*)
				INSTFLUX=$optarg ;;
			dhcpargs=*)
				DHCPARGS=$optarg ;;
			instiso=*)
				ISO_INSTLABEL=$optarg ;;
			BOOTIF=*)
				# 01-52-54-00-12-34-56 -> 52-54-00-12-34-56
				BOOTIF=${optarg#*-}
				# 52-54-00-12-34-56 -> 52:54:00:12:34:56
				BOOTIF=${BOOTIF//-/:}
				;;
			wifi=*)
				WIFI=$optarg ;;
			ecurl=*)
				if [ "$ECURL" = "" ] ; then ECURL=$optarg; fi ;;
			ecurlarg=*)
				ECURLARG=$optarg ;;
			lcurl=*)
				if [ "$LCURL" = "" ] ; then LCURL=$optarg; fi ;;
			lcurlarg=*)
				LCURLARG=$optarg ;;
			devmd=*)
				DEVMD=$optarg ;;
			biosplusefi=*)
				BIOSPLUSEFI=$optarg ;;
			defaultkernel=*)
				DEFAULT_KERNEL=$optarg ;;
			efibootfirst=*)
				EFIBOOT_FIRST=$optarg ;;
			LUKS=*)
				LUKS=$optarg ;;
			BLM=*)
				BLM=$optarg ;;
			FSZ=*)
				FSZ=$optarg ;;
			BSZ=*)
				BSZ=$optarg ;;
			RSZ=*)
				RSZ=$optarg ;;
			VSZ=*)
				VSZ=$optarg ;;
		esac
	done
	# defaults if not set
	if [ "$BL" = "" ] ; then BL=grub ; fi
	if [ "$INSTSF" = "" ] ; then INSTSF=0 ; fi
	if [ "$INSTSH" = "" ] ; then INSTSH=0 ; fi
	if [ "$INSTAB" = "" ] ; then INSTAB=1 ; fi
	if [ "$INSTOS" = "" ] ; then INSTOS=@OSTREE_OSNAME@ ; fi
	if [ "$INSTNET" = "" ] ; then INSTNET=dhcp ; fi
	if [ "$INSTGPG" = "" ] ; then INSTGPG=1 ; fi
	if [ "$INSTFLUX" = "" ] ; then INSTFLUX=1 ; fi
	if [ "$INSTSBD" = "" ] ; then INSTSBD=2 ; fi
}

shell_start() {
	a=`cat /proc/cmdline`
	for e in $a; do
		case $e in
			console=*)
				c=${e%,*}
				c=${c#console=*}
				;;
		esac
	done

	if [ "$c" = "" ] ; then
		c=tty0
	fi
	args=""
	tty > /dev/null
	if [ $? != 0 ] ; then
		args="</dev/$c >/dev/$c 2>&1"
	fi
	if [ "$1" = "exec" ] ; then
		echo "function lreboot { echo b > /proc/sysrq-trigger; while [ 1 ] ; do sleep 60; done };trap lreboot EXIT" > /debugrc
		exec setsid sh -c "exec /bin/bash --rcfile /debugrc $args"
	else
		setsid sh -c "exec /bin/bash $args"
	fi
}

grub_pt_update() {
	first=$(($end+1))
	p=$((p+1))
	if [ $first -gt $last ] ; then
		a=$(echo "$a" | sed "s/\(.*:EF00\) .*/\1/g")
		sgdisk $a -p ${dev}
		mkfs.vfat -n otaefi ${fs_dev}${p1}
		sync
		fatal "ERROR: Disk is not big enough for requested layout"
	fi
}

grub_partition() {
	local a
	local p
	local first
	local last
	local end
	lsz=`lsblk -n ${dev} -o LOG-SEC -d`
	lsz=${lsz// /}
	# EFI Partition
	if [ ! -e ${fs_dev}${p1} ] ; then
		sgdisk -i ${p1} ${dev} |grep -q ^"Partition name"
		if [ $? != 0 ] ; then
			echo "WARNING WARNING - ${fs_dev}${p1} does not exist, creating"
			INSTSF=0
		fi
	fi
	if [ $INSTSF = 1 ] ; then
		for e in `sgdisk -p ${dev} 2> /dev/null |grep -A 1024 ^Number |grep -v ^Number |awk '{print $1}' |grep -v ^1\$`; do
			a="$a -d $e"
		done
		if [ "$BIOSPLUSEFI" = "1"  ] ; then
			a="$a -c 1:bios -t 1:EF02"
		fi
		a="$a -c ${p1}:otaefi -t ${p1}:EF00"
		sgdisk -e $a ${dev}
		a=""
		first=`sgdisk -F ${dev}|grep -v Creating`
	else
		sgdisk -Z ${dev}
		first=`sgdisk -F ${dev}|grep -v Creating`
		if [ "$BIOSPLUSEFI" = "1"  ] ; then
			# 1MB size for BIOS boot partition
			end=$(($first+(1*1024*1024/$lsz)-1))
			a="$a -n 1:$first:$end -c 1:bios -t 1:EF02"
			first=$(($end+1))
		fi
		end=$(($first+($FSZ*1024*1024/$lsz)-1))
		a="$a -n ${p1}:$first:$end -c ${p1}:otaefi -t ${p1}:EF00"
		first=$(($end+1))
	fi
	last=$(sgdisk -E ${dev} 2>/dev/null |grep -v Creating)
	p=$((p1+1))
	# Boot Partition A
	end=$(($first+($BSZ*1024*1024/$lsz)-1))
	a="$a -n $p:$first:$end -c $p:otaboot"
	grub_pt_update
	# Root Partition A
	if [ "$INSTAB" = 0 -a "${INSTFLUX}" = 0 ] ; then
		if [ "$VSZ" = 0 ] ; then
			end=$last
		else
			end=$(($first+($RSZ*1024*1024/$lsz)-1))
		fi
		a="$a -n $p:$first:$end -c $p:otaroot"
	else
		end=$(($first+($RSZ*1024*1024/$lsz)-1))
		a="$a -n $p:$first:$end -c $p:otaroot"
	fi
	if [ "$INSTAB" = 1 ] ; then
		# Boot Partition B
		grub_pt_update
		end=$(($first+($BSZ*1024*1024/$lsz)-1))
		a="$a -n $p:$first:$end -c $p:otaboot_b"
		grub_pt_update
		# Root Partition B
		end=$(($first+($RSZ*1024*1024/$lsz)-1))
		a="$a -n $p:$first:$end -c $p:otaroot_b"
	fi
	# Flux Partition
	if [ "${INSTFLUX}" = 1 ] ; then
		grub_pt_update
		if [ "$VSZ" = 0 ] ; then
			end=$last
		else
			end=$(($first+($VSZ*1024*1024/$lsz)-1))
		fi
		a="$a -n $p:$first:$end -c $p:fluxdata"
	fi

	# Create new partitions (optional), grub
	if [ "${VSZ}" != 0  -a -n "${KS}" ]; then
		exec_hook "%part" ${lat_create_part}
		if [ $? -ne 0 ]; then
			fatal "Run Kickstart Create Part Script failed"
		fi
	fi

	sgdisk $a -p ${dev}
}

ufdisk_partition() {
	if [ ! -e ${fs_dev}${p1} ] ; then
		sfdisk -l ${dev} | grep -q ${fs_dev}${p1}
		if [ $? != 0 ] ; then
			echo "WARNING WARNING - ${fs_dev}${p1} does not exist, creating"
			INSTSF=0
		fi
	fi
	if [ $INSTSF = 1 ] ; then
		pts=`mktemp`
		fdisk -l -o device ${dev} |grep ^${fs_dev} > $pts || fatal "fdisk probe failed"
		# Start by deleting all the other partitions
		fpt=$(cat $pts |sed -e "s#${fs_dev}##" | head -n 1)
		for p in `cat $pts |sed -e "s#${fs_dev}##" |sort -rn`; do
			if [ $p != 1 ] ; then
				sfdisk --no-reread --no-tell-kernel -w never --delete ${dev} $p
			fi
		done
	else
		sgdisk -Z ${dev} > /dev/null 2> /dev/null
		echo 'label: mbr' | sfdisk --no-reread --no-tell-kernel -W never -w never ${dev}
		# Partition for storage of u-boot variables and backup kernel
		echo "${BLM},${FSZ}M,0xc" | sfdisk --no-reread --no-tell-kernel -W never -w never ${dev}
		sfdisk --no-reread --no-tell-kernel -W never -w never -A ${dev} 1
	fi
	# Create extended partition for remainder of disk
	echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'), +,0x5" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
	if [ "${INSTFLUX}" = 1 ] ; then
		# Create Boot and Root A partition
		echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${BSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
		[ $? -eq 0 ] || fatal "Create partition failed"
		echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${RSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
		[ $? -eq 0 ] || fatal "Create partition failed"
		if [ "$INSTAB" = "1" ] ; then
			# Create Boot and Root B partition
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${BSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${RSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
		fi

		# flux data partition
		if [ "$VSZ" = 0 ] ; then
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'), +" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
		else
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${VSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
		fi
	else
		if [ "$INSTAB" = "1" ] ; then
			# Create Boot and Root A partition
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${BSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${RSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
			# Create Boot and Root B partition
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${BSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${RSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
		else
			# Create Boot and Root A partition for whole disk
			echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${BSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
			[ $? -eq 0 ] || fatal "Create partition failed"
			if [ "$VSZ" = 0 ] ; then
				echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'), +" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
				[ $? -eq 0 ] || fatal "Create partition failed"
			else
				echo "$(sfdisk -F ${dev} |tail -1 |awk '{print $1}'),${RSZ}M" | sfdisk --no-reread --no-tell-kernel -a -W never -w never ${dev}
				[ $? -eq 0 ] || fatal "Create partition failed"
			fi
		fi
	fi

	# Create new partitions (optional), udisk
	if [ "${VSZ}" != 0 -a -n "${KS}" ]; then
		exec_hook "%part" ${lat_create_part}
		if [ $? -ne 0 ]; then
			fatal "Run Kickstart Create Part Script failed"
		fi
	fi
}

##################

if [ "$1" = "-h" -o "$1" = "-?" ] ; then
	helptxt
	exit 0
fi

if [ "$RE_EXEC" != "1" ] ; then
	early_setup
	if [ -e /bin/mttyexec -a "$CONSOLES" != "" ] ; then
		export RE_EXEC=1
		cmd="/bin/mttyexec -s -f /install.log"
		for e in $CONSOLES; do
			echo > /dev/$e 2> /dev/null
			if [ $? = 0 ] ; then
				cmd="$cmd -d /dev/$e"
			fi
		done
		exec $cmd $0 $@
	fi
else
	read_args
fi

[ -z "$INIT" ] && INIT="/sbin/init"

if [ "$INSTSH" = 1 -o "$INSTSH" = 3 -o "$INSTSH" = 4 ] ; then
	if [ "$INSTSH" = 4 ] ; then
		helptxt
	fi
	echo "Starting boot shell.  System will reboot on exit"
	echo "You can execute the install with:"
	echo "     INSTPOST=exit INSTSH=0 bash -v -x /install"
	shell_start exec
	lreboot
fi

udevadm settle --timeout=3

if [ "$INSTNAME" = "" ] ; then
	fatal "Error no remote archive name, need kernel argument: instname=..."
fi
if [ "$INSTBR" = "" ] ; then
	fatal "Error no branch name for OSTree, need kernel argument: instbr=..."
fi
if [ "$INSTURL" = "" ] ; then
	fatal "Error no URL for OSTree, need kernel argument: insturl=..."
fi

if [ "$INSTDATE" != "" ] ; then
	if [ "$INSTDATE" = "BUILD_DATE" ] ; then
		echo "WARNING date falling back to 1/1/2020"
		date -u -s @1577836800
	else
		date -u -s $INSTDATE
	fi
fi

# Customize here for network
if [ "$IP" != "" ] ; then
	if [ "$IP" = "dhcp" ] ; then
		dns=$(dmesg |grep nameserver.= |sed 's/nameserver.=//g; s/,//g')
	else
		dns=$(echo "$IP"|awk -F: '{print $8" "$9}')
	fi
	for e in $dns; do
		echo nameserver $e >> /etc/resolv.conf
	done
fi

if [ "$INSTNET" = dhcp -o "$INSTNET" = dhcp6 ] ; then
	do_dhcp
fi

# If local kickstart is not available
if [ "${KS::7}" = "file://" -a ! -e "${KS:7}" ]; then
  # Try to find local kickstart from instboot partition
  cnt=10
  while [ "$cnt" -gt 0 ] ; do
    bdev=$(blkid --label instboot || blkid --label ${ISO_INSTLABEL})
    if [ $? = 0 ]; then
      break
    fi
    sleep 1
    cnt=$(($cnt - 1))
  done

  if [ -n "$bdev" ]; then
    LOCAL_KS="/local-ks.cfg"
    mkdir /t
    mount -r $bdev /t
    if [ -e "/t/${KS:7}" ]; then
      cp "/t/${KS:7}" ${LOCAL_KS}
      KS="file://${LOCAL_KS}"
    fi
    umount /t
    rm -rf /t
  fi
fi

if [ -n "${KS}" ]; then
	./lat-installer.sh parse-ks --kickstart=${KS}
	if [ $? -ne 0 ]; then
		fatal "Parse Kickstart ${KS} failed"
	fi
	if [ -e /tmp/lat/cmdline ]; then
		CMDLINE=`cat /tmp/lat/cmdline` read_args
	fi
fi

if [ -n "${KS}" ]; then
	exec_hook "%ks-early" ${lat_ks_early}
	if [ $? -ne 0 ]; then
		fatal "Run Kickstart Early Script failed"
	fi
fi

# Early curl exec

if [ "${ECURL}" != "" -a "${ECURL}" != "none" ] ; then
	curl ${ECURL} --output /ecurl
	# Prevent recursion if script debugging
	export ECURL="none"
	chmod 755 /ecurl
	/ecurl ${ECURLARG}
fi

# Customize here for disk detection

if [ "$INSTDEV" = "" ] ; then
	fatal "Error no kernel argument instdev=..."
fi

fix_part_labels=1
# Device setup
retry=0
fail=1
while [ $retry -lt $MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE ] ; do
	for i in ${FROMDEV//,/ }; do
		if [ "${i#PUUID=}" != "$i" ] ; then
			fdev=$(blkid -o device -l -t PARTUUID=${i#PUUID=})
			if [ "$fdev" != "" ] ; then
				fail=0
				break
			fi
		elif [ "${i#UUID=}" != "$i" ] ; then
			fdev=$(blkid --uuid ${i#UUID=})
			if [ "$fdev" != "" ] ; then
				fail=0
				break
			fi
		elif [ "${i#LABEL=}" != "$i" ] ; then
			fdev=$(blkid --label ${i#LABEL=})
			if [ "$fdev" != "" ] ; then
				fail=0
				break
			fi
		elif [ -e $i ]; then
			fdev=$(realpath $i)
			if [ "$fdev" != "" ] ; then
				fail=0
				break
			fi
		fi
	done
	[ $fail = 0 ] && break
	retry=$(($retry+1))
	sleep 0.1
done

if [ -n "$fdev" ]; then
	fname=$(lsblk $fdev -n -o pkname)
fi

if [ "$INSTDEV" = "ask" ] ; then
	INSTW=0
	# Wait to avoid interference of kernel message
	sleep 1
	ask_dev
fi

retry=0
fail=1
while [ $retry -lt $MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE ] ; do
	for i in ${INSTDEV//,/ }; do
		if [ "${i#PUUID=}" != "$i" ] ; then
			idev=$(blkid -o device -l -t PARTUUID=${i#PUUID=})
			if [ "$idev" != "" ] ; then
				check_valid_dev $idev || continue
				INSTDEV=/dev/$(lsblk $idev -n -o pkname)
				fail=0
				break
			fi
		elif [ "${i#UUID=}" != "$i" ] ; then
			idev=$(blkid --uuid ${i#UUID=})
			if [ "$idev" != "" ] ; then
				check_valid_dev $idev || continue
				INSTDEV=/dev/$(lsblk $idev -n -o pkname)
				fail=0
				break
			fi
		elif [ "${i#LABEL=}" != "$i" ] ; then
			idev=$(blkid --label ${i#LABEL=})
			if [ "$idev" != "" ] ; then
				check_valid_dev $idev || continue
				INSTDEV=/dev/$(lsblk $idev -n -o pkname)
				fail=0
				break
			fi
		elif [ -e $i ] ; then
			i=$(realpath $i)
			check_valid_dev $i || continue
			INSTDEV=$i
			echo "Installing to: $i"
			fail=0
			break
		fi
	done
	[ $fail = 0 ] && break
	retry=$(($retry+1))
	sleep 0.1
done

if [ $fail = 1 ] ; then
	INSTW=0
	ask_dev
fi

if [ -n "${KS}" ]; then
	exec_hook "%pre-part" ${lat_pre_part}
	if [ $? -ne 0 ]; then
		fatal "Run Kickstart Per Partitioin Script failed"
	fi
fi

cnt=0
if [ "$INSTW" != "" ] && [ "$INSTW" -gt 0 ] ; then
	cnt=$INSTW
fi

# Start a wait loop below for user input and timeout to install if instw > 0
if [ "$cnt" -gt 0 ] ; then
	conflict_label print
fi
while [ "$cnt" -gt 0 ] ; do
	[ $(($cnt % 10)) -eq 0 ] && lsblk -o NAME,VENDOR,SIZE,MODEL,TYPE,LABEL $INSTDEV
	read -r -s -n 1 -t 1 -p "## Erasing $INSTDEV in $cnt sec ## 'y' = start ## Any key to abort ##" key
	ret=$?
	echo
	if [ $ret = 0 ] ; then
		if [ "$key" != y ] ; then
			ask_dev
		fi
		break
	fi
	cnt=$(($cnt - 1))
done
if [ "$fix_part_labels" = "1" ] ; then
	conflict_label fix
fi

fs_dev=${INSTDEV}
# The index of first file system partition on install disk
p1="1"
if [ "$BIOSPLUSEFI" = "1"  ] ; then
	# Use one GPT disk to support both of BIOS and EFI
	# it should create a mebibyte partition (+1M) on the
	# disk with no file system and with partition type GUID
	# 21686148-6449-6E6F-744E-656564454649, so the index of
	# first file system partition is 2
	p1="2"
fi

if [ "${fs_dev#/dev/mmcblk}" != ${fs_dev} ] ; then
       fs_dev="${INSTDEV}p"
elif [ "${fs_dev#/dev/nbd}" != ${fs_dev} ] ; then
       fs_dev="${INSTDEV}p"
elif [ "${fs_dev#/dev/nvme}" != ${fs_dev} ] ; then
       fs_dev="${INSTDEV}p"
elif [ "${fs_dev#/dev/loop}" != ${fs_dev} ] ; then
       fs_dev="${INSTDEV}p"
fi

# Customize here for disk partitioning

dev=${INSTDEV}

# Special case check if install media is different than boot media
if [ $INSTSF = 1 ] ; then
	if [ "${fdev}" != "" -a "${fs_dev}${p1}" != "${fdev}" ] ; then
		echo "Install disk is different than boot disk setting instsf=0"
		INSTSF=0
	fi
fi

if [ "$INSTPT" != "0" ] ; then
	if [ "$BL" = "grub" ] ; then
		grub_partition
	elif [ "$BL" = "ufsd" ] ; then
		ufdisk_partition
	else
		fatal "Error: bl=$BL is not supported"
	fi
fi

udevadm settle --timeout=3

cnt=50
while [ "$cnt" -gt 0 ] ; do
	blockdev --rereadpt ${dev} 2> /dev/null > /dev/null && break
	sleep 0.1
	cnt=$(($cnt - 1))
done
sync

# Customize here for disk formatting

if [ "$INSTPT" != "0" ] ; then
	INSTFMT=1
fi

# Do not create encrypted volumes if TPM is not detected
if [ $LUKS -gt 0 ] ; then
	detect_tpm_chip
	if [ $? -ne 0 ]; then
		LUKS=0
	fi
fi

if [ "$BL" = "grub" -a "$INSTFMT" != "0" ] ; then
	if [ $INSTSF = 1 ] ; then
		dosfslabel ${fs_dev}${p1} otaefi
	else
		mkfs.vfat -n otaefi ${fs_dev}${p1}
	fi

	pi=$((p1+1))
	dashe="-e"
	if [ $LUKS -eq 3 ] ; then
		echo Y | luks-setup.sh -f $dashe -d ${fs_dev}${pi} -n luksotaboot -k /usr/share/grub/boot.key || \
			fatal "Cannot create LUKS volume luksotaboot"
		dashe=""
		mkfs.ext4 -F -L otaboot /dev/mapper/luksotaboot
	else
		mkfs.ext4 -F -L otaboot ${fs_dev}${pi}
	fi

	pi=$((pi+1))
	if [ $LUKS -gt 1 ] ; then
		echo Y | luks-setup.sh -f $dashe -d ${fs_dev}${pi} -n luksotaroot || \
			fatal "Cannot create LUKS volume luksotaroot"
		dashe=""
		mkfs.ext4 -F -L otaroot /dev/mapper/luksotaroot
	else
		mkfs.ext4 -F -L otaroot ${fs_dev}${pi}
	fi

	if [ "$INSTAB" = "1" ] ; then
		pi=$((pi+1))
		if [ $LUKS -eq 3 ] ; then
			echo Y | luks-setup.sh -f $dashe -d ${fs_dev}${pi} -n luksotaboot_b -k /usr/share/grub/boot.key || \
				fatal "Cannot create LUKS volume luksotaboot_b"
			dashe=""
			mkfs.ext4 -F -L otaboot_b /dev/mapper/luksotaboot_b
		else
			mkfs.ext4 -F -L otaboot_b ${fs_dev}${pi}
		fi

		pi=$((pi+1))
		if [ $LUKS -gt 1 ] ; then
			echo Y | luks-setup.sh -f -d ${fs_dev}${pi} -n luksotaroot_b || \
				fatal "Cannot create LUKS volume luksotaroot_b"
			mkfs.ext4 -F -L otaroot_b /dev/mapper/luksotaroot_b
		else
			mkfs.ext4 -F -L otaroot_b ${fs_dev}${pi}
		fi
	fi

	if [ "${INSTFLUX}" = 1 ] ; then
		pi=$((pi+1))
		FLUXPART=${pi}
		if [ $LUKS -gt 0 ] ; then
			echo Y | luks-setup.sh -f $dashe -d ${fs_dev}${FLUXPART} -n luksfluxdata || \
				fatal "Cannot create LUKS volume luksfluxdata"
			dashe=""
			mkfs.ext4 -F -L fluxdata /dev/mapper/luksfluxdata
		else
			mkfs.ext4 -F -L fluxdata ${fs_dev}${FLUXPART}
		fi
	fi
elif [ "$INSTFMT" != 0 ] ; then
	if [ $INSTSF = 1 ] ; then
		dosfslabel ${fs_dev}${p1} boot
	else
		mkfs.vfat -n boot ${fs_dev}${p1}
	fi
	pi=5
	mkfs.ext4 -F -L otaboot ${fs_dev}${pi}
	pi=$((pi+1))
	mkfs.ext4 -F -L otaroot ${fs_dev}${pi}
	if [ "$INSTAB" = "1" ] ; then
		pi=$((pi+1))
		mkfs.ext4 -F -L otaboot_b ${fs_dev}${pi}
		pi=$((pi+1))
		mkfs.ext4 -F -L otaroot_b ${fs_dev}${pi}
	fi

	if [ "${INSTFLUX}" = 1 ] ; then
		pi=$((pi+1))
		FLUXPART=${pi}
		mkfs.ext4 -F -L fluxdata ${fs_dev}${FLUXPART}
	fi
fi

# Create filesystem on new partitions (optional), grub and udisk
if [ "${VSZ}" != 0 -a -n "${KS}" ]; then
	exec_hook "%mkfs" ${lat_make_fs}
	if [ $? -ne 0 ]; then
		fatal "Run Kickstart Make FS Script failed"
	fi
fi

retries=1
while [ "${retries}" -le 5 ]; do
	sleep 0.1
	if partprobe "${INSTDEV}"; then
		break
	fi
	retries=$((retries + 1))
done

if [ -n "${KS}" ]; then
	./lat-installer.sh pre-install
	if [ $? -ne 0 ]; then
		fatal "Run Kickstart Pre Install Script failed"
	fi
fi

# OSTree deploy

PHYS_SYSROOT="/sysroot"
OSTREE_BOOT_DEVICE="LABEL=otaboot"
OSTREE_ROOT_DEVICE="LABEL=otaroot"
mount_flags="rw,noatime"
if [ -x /init.ima ] ; then
	mount --help 2>&1 |grep -q BusyBox
	if [ $? = 0 ] ; then
		mount_flags="rw,noatime,i_version"
	else
		mount_flags="rw,noatime,iversion"
	fi
fi
for arg in ${OSTREE_KERNEL_ARGS}; do
        kargs_list="${kargs_list} --karg-append=$arg"
done

mkdir -p ${PHYS_SYSROOT}
mount -o $mount_flags "${OSTREE_ROOT_DEVICE}" "${PHYS_SYSROOT}" || fatal "Error mouting ${OSTREE_ROOT_DEVICE}"

ostree admin --sysroot=${PHYS_SYSROOT} init-fs ${PHYS_SYSROOT}
ostree admin --sysroot=${PHYS_SYSROOT} os-init ${INSTOS}
ostree config --repo=${PHYS_SYSROOT}/ostree/repo set core.add-remotes-config-dir false
ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.branch ${INSTBR}
ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.remote ${INSTNAME}
ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.os ${INSTOS}
if [ "$INSTFLUX" != "1" ] ; then
	ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.noflux 1
fi
if [ "$INSTAB" != "1" ] ; then
	ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.no-ab 1
fi

ostree config --repo=${PHYS_SYSROOT}/ostree/repo set upgrade.skip-boot-diff $INSTSBD

if [ ! -d "${PHYS_SYSROOT}/boot" ] ; then
   mkdir -p ${PHYS_SYSROOT}/boot
fi

mount "${OSTREE_BOOT_DEVICE}" "${PHYS_SYSROOT}/boot"  || fatal "Error mouting ${OSTREE_BOOT_DEVICE}"

mkdir /instboot
bdev=$(blkid --label instboot || blkid --label ${ISO_INSTLABEL})
if [ $? = 0 ] ; then
	mount -w $bdev /instboot || mount -r $bdev /instboot
# Special case check if instboot is not available and
# install media is different than boot media
elif [ -n "$fdev" ] && [ -e "$fdev" ] && [ "$fdev" != "${fs_dev}${p1}"  ] ; then
	mount -w $fdev /instboot
fi

mkdir -p ${PHYS_SYSROOT}/boot/efi
mount ${fs_dev}${p1} ${PHYS_SYSROOT}/boot/efi || fatal "Error mouting ${fs_dev}${p1}"

# Prep for Install
mkdir -p ${PHYS_SYSROOT}/boot/loader.0
ln -s loader.0 ${PHYS_SYSROOT}/boot/loader

if [ "$BL" = "grub" ] ; then
	mkdir -p ${PHYS_SYSROOT}/boot/grub2
	touch ${PHYS_SYSROOT}/boot/grub2/grub.cfg
else
	touch  ${PHYS_SYSROOT}/boot/loader/uEnv.txt
fi

do_gpg=""
if [ "$INSTGPG" != "1" ] ; then
	do_gpg=--no-gpg-verify
fi
ostree remote --repo=${PHYS_SYSROOT}/ostree/repo add ${do_gpg} ${INSTNAME} ${INSTURL}

touch /etc/ssl/certs/ca-certificates.crt
mkdir -p /var/volatile/tmp /var/volatile/run

lpull=""
if [ "$INSTL" != "" ] ; then
	if [ -e /instboot${INSTL#/sysroot/boot/efi} ] ; then
		lpull="--url file:///instboot${INSTL#/sysroot/boot/efi}"
	elif [ -e $INSTL ] ; then
		lpull="--url file://$INSTL"
	else
		echo "WARNING WARNING - Local install missing, falling back to network"
		lpull=""
		INSTL=""
		do_dhcp
	fi
fi

cmd="ostree pull $lpull --repo=${PHYS_SYSROOT}/ostree/repo ${INSTNAME} ${INSTBR}"
echo running: $cmd
$cmd || fatal "Error: ostree pull failed"
export OSTREE_BOOT_PARTITION="/boot"
ostree admin deploy ${kargs_list} --sysroot=${PHYS_SYSROOT} --os=${INSTOS} ${INSTNAME}:${INSTBR} || fatal "Error: ostree deploy failed"

if [ "$INSTAB" != 1 ] ; then
	# Deploy a second time so a roll back is available from the start
	ostree admin deploy --sysroot=${PHYS_SYSROOT} --os=${INSTOS} ${INSTNAME}:${INSTBR} || fatal "Error: ostree deploy failed"
fi

# Initialize "B" partion if used


if [ "$INSTAB" = "1" ] ; then
	mkdir -p ${PHYS_SYSROOT}_b
	mount -o $mount_flags "${OSTREE_ROOT_DEVICE}_b" "${PHYS_SYSROOT}_b"  || fatal "Error mouting ${OSTREE_ROOT_DEVICE}_b"

	ostree admin --sysroot=${PHYS_SYSROOT}_b init-fs ${PHYS_SYSROOT}_b
	ostree admin --sysroot=${PHYS_SYSROOT}_b os-init ${INSTOS}
	cp ${PHYS_SYSROOT}/ostree/repo/config ${PHYS_SYSROOT}_b/ostree/repo

	if [ ! -d "${PHYS_SYSROOT}_b/boot" ] ; then
		mkdir -p ${PHYS_SYSROOT}_b/boot
	fi

	mount "${OSTREE_BOOT_DEVICE}_b" "${PHYS_SYSROOT}_b/boot" || fatal "Error mouting ${OSTREE_BOOT_DEVICE}_b"


	mkdir -p ${PHYS_SYSROOT}_b/boot/efi
	mount ${fs_dev}${p1} ${PHYS_SYSROOT}_b/boot/efi

	mkdir -p ${PHYS_SYSROOT}_b/boot/loader.0
	ln -s loader.0 ${PHYS_SYSROOT}_b/boot/loader

	# Prep for Install
	if [ "$BL" = "grub" ] ; then
		mkdir -p ${PHYS_SYSROOT}_b/boot/grub2
		touch ${PHYS_SYSROOT}_b/boot/grub2/grub.cfg
	else
		touch  ${PHYS_SYSROOT}_b/boot/loader/uEnv.txt
	fi

	if [ ${INSTURL#http} = ${INSTURL} ]; then
		localcache="--localcache-repo=${PHYS_SYSROOT}/ostree/repo"
	fi
	ostree pull $lpull --repo=${PHYS_SYSROOT}_b/ostree/repo ${localcache} ${INSTNAME}:${INSTBR} || fatal "ostree pull failed"
	ostree admin deploy ${kargs_list} --sysroot=${PHYS_SYSROOT}_b --os=${INSTOS} ${INSTBR} || fatal "ostree deploy failed"
fi

# Replace/install boot loader
if [ -e ${PHYS_SYSROOT}/boot/1/efi/EFI ] ; then
	cp -r  ${PHYS_SYSROOT}/boot/1/efi/EFI ${PHYS_SYSROOT}/boot/efi/
	echo "# GRUB Environment Block" > ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	if [ "$INSTAB" != "1" ] ; then
	    printf "ab=0\n" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	else
	    echo -n "#####" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	fi
	printf "boot_tried_count=0\n" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	printf "ostree_console=$OSTREE_CONSOLE\n" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	if [ -n "$KERNEL_PARAMS" ]; then
		printf "kernel_params=$KERNEL_PARAMS\n" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
	fi

	if [ $LUKS -eq 3 ] ; then
		blkid ${fs_dev}* | grep 'TYPE="crypto_LUKS"' | grep 'PARTLABEL="otaboot"' | awk '{print $2}' | sed -e 's/UUID=/crypt_boot_uuid=/' -e 's/-//g' >>  ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
		blkid ${fs_dev}* | grep 'TYPE="crypto_LUKS"' | grep 'PARTLABEL="otaboot_b"' | awk '{print $2}' | sed -e 's/UUID=/crypt_boot_b_uuid=/' -e 's/-//g' >>  ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
		cp -f /usr/share/grub/boot.key* ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/
	fi

	echo -n "###############################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################" >> ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/boot.env
fi
if [ -e ${PHYS_SYSROOT}/boot/loader/uEnv.txt ] ; then
	bootdir=$(grep ^bootdir= ${PHYS_SYSROOT}/boot/loader/uEnv.txt)
	bootdir=${bootdir#bootdir=}
	if [ "$bootdir" != "" ] && [ -e "${PHYS_SYSROOT}/boot$bootdir" ] ; then
		# Backup boot.scr/boot.itb (modified by bootfs.sh) to avoid be overridden by the one in bootdir
		[ -e ${PHYS_SYSROOT}/boot/efi/boot.scr ] && mv ${PHYS_SYSROOT}/boot/efi/boot.scr ${PHYS_SYSROOT}/boot/efi/boot.scr-back
		[ -e ${PHYS_SYSROOT}/boot/efi/boot.itb ] && mv ${PHYS_SYSROOT}/boot/efi/boot.itb ${PHYS_SYSROOT}/boot/efi/boot.itb-back
		cp -r ${PHYS_SYSROOT}/boot$bootdir/* ${PHYS_SYSROOT}/boot/efi
		[ -e ${PHYS_SYSROOT}/boot/efi/boot.scr-back ] && mv ${PHYS_SYSROOT}/boot/efi/boot.scr-back ${PHYS_SYSROOT}/boot/efi/boot.scr
		[ -e ${PHYS_SYSROOT}/boot/efi/boot.itb-back ] && mv ${PHYS_SYSROOT}/boot/efi/boot.itb-back ${PHYS_SYSROOT}/boot/efi/boot.itb
	fi
	printf "123A" > ${PHYS_SYSROOT}/boot/efi/boot_ab_flag
	# The first 0 is the boot count, the second zero is the boot entry default
	printf '00WR' > ${PHYS_SYSROOT}/boot/efi/boot_cnt
	if [ "$INSTAB" != "1" ] ; then
		printf '1' > ${PHYS_SYSROOT}/boot/efi/no_ab
	else
		rm -f  ${PHYS_SYSROOT}/boot/efi/no_ab
	fi

fi

# Update kernel.env
if [ "$BL" = "grub" ]; then
	if [ -e ${PHYS_SYSROOT}/boot/1/kernel.env ]; then
		if [ -n "${DEFAULT_KERNEL}" ]; then
			DEFAULT_KERNEL=$(ls -1 ${PHYS_SYSROOT}/boot/1/${DEFAULT_KERNEL} 2>/dev/null)
			DEFAULT_KERNEL=${DEFAULT_KERNEL##*/}
			[ -n "${DEFAULT_KERNEL}" ] && \
			sed -i -e "s/^kernel=.*/kernel=${DEFAULT_KERNEL}/g" \
			    -e "s/^kernel_rollback=.*/kernel_rollback=${DEFAULT_KERNEL}/g" \
			  ${PHYS_SYSROOT}/boot/1/kernel.env
		fi
	fi
	if [ "$INSTAB" = "1" -a -e ${PHYS_SYSROOT}_b/boot/1/kernel.env ] ; then
		if [ -n "${DEFAULT_KERNEL}" ]; then
			DEFAULT_KERNEL=$(ls -1 ${PHYS_SYSROOT}/boot/1/${DEFAULT_KERNEL} 2>/dev/null)
			DEFAULT_KERNEL=${DEFAULT_KERNEL##*/}
			[ -n "${DEFAULT_KERNEL}" ] && \
			sed -i -e "s/^kernel=.*/kernel=${DEFAULT_KERNEL}/g" \
			    -e "s/^kernel_rollback=.*/kernel_rollback=${DEFAULT_KERNEL}/g" \
			  ${PHYS_SYSROOT}_b/boot/1/kernel.env
		fi
	fi
fi

# Late curl exec

if [ "${LCURL}" != "" -a "${LCURL}" != "none" ] ; then
	curl ${LCURL} --output /lcurl
	export LCURL="none"
	chmod 755 /lcurl
	/lcurl ${LCURLARG}
fi

if [ -f ${PHYS_SYSROOT}/ostree/?/etc/selinux/config ]; then
	if [ ! -f ${PHYS_SYSROOT}/ostree/?/etc/.autorelabel ]; then
		relabeldira=$(ls ${PHYS_SYSROOT}/ostree/? -d | sed -n '1,1p')
		echo "# first boot relabelling" > ${relabeldira}/etc/.autorelabel

		if [ "$INSTAB" = 1 ] ; then
			relabeldirb=$(ls ${PHYS_SYSROOT}_b/ostree/? -d | sed -n '1,1p')
			echo "# first boot relabelling" > ${relabeldirb}/etc/.autorelabel
		fi
	fi
fi

# Modify fstab if not using fluxdata
# Caution... If someone resets the /etc/fstab with OSTree this change is lost...
mkdir /var1
if [ "$INSTFLUX" != "1" ] ; then
	if [ "$BL" = "grub" -o "$BL" = "ufsd" ] ; then
		sed -i -e "s#^LABEL=fluxdata.*#${PHYS_SYSROOT}/ostree/deploy/${INSTOS}/var /var none bind 0 0#" ${PHYS_SYSROOT}/ostree/?/etc/fstab
		if [ "$INSTAB" = 1 ] ; then
			sed -i -e "s#^LABEL=fluxdata.*#${PHYS_SYSROOT}/ostree/deploy/${INSTOS}/var /var none bind 0 0#" ${PHYS_SYSROOT}_b/ostree/?/etc/fstab
		fi
	else
		fatal "Error: bl=$BL is not supported"
	fi
	mount --bind ${PHYS_SYSROOT}/ostree/deploy/${INSTOS}/var /var1
else
	mount -o $mount_flags LABEL=fluxdata /var1
fi
if [ -d ${PHYS_SYSROOT}/ostree/1/var ] ; then
	tar -C ${PHYS_SYSROOT}/ostree/1/var/ --xattrs --xattrs-include='*' -cf - . | \
	tar --xattrs --xattrs-include='*' -xf - -C /var1 2> /dev/null
fi
if [ -d ${PHYS_SYSROOT}/ostree/1/usr/homedirs/home ] ; then
	tar -C ${PHYS_SYSROOT}/ostree/1/usr/homedirs/home --xattrs --xattrs-include='*' -cf - . | \
	tar --xattrs --xattrs-include='*' -xf - -C /var1/home 2> /dev/null
fi

if [ -n "${KS}" ]; then
	rootfs=`ls ${PHYS_SYSROOT}/ostree/? -d`
	if [ "$INSTAB" = 1 ] ; then
		rootfs="$rootfs `ls ${PHYS_SYSROOT}_b/ostree/? -d`"
	fi

	for root in ${rootfs}; do
		./lat-installer.sh set-network --root=${root} -v
		if [ $? -ne 0 ]; then
			fatal "Run Kickstart Set network failed in ${root}"
		fi

		./lat-installer.sh post-install --root=${root} -v --instflux=${INSTFLUX} --instos=${INSTOS}
		if [ $? -ne 0 ]; then
			fatal "Run Kickstart Post Install Script failed in ${root}"
		fi
	done
fi

if [ "$BIOSPLUSEFI" = "1"  ] ; then
	mkdir -p /boot
	mount ${fs_dev}${p1} /boot
	if [ -e /sbin/grub-install ] ; then
		/sbin/grub-install --target=i386-pc  ${dev}
		echo "set legacy_bios=1" > /boot/grub/grub.cfg
		echo "set boot_env_path=/efi/boot" >> /boot/grub/grub.cfg
		echo "source /efi/boot/grub.cfg" >> /boot/grub/grub.cfg
	elif [ -e /sbin/grub2-install ] ; then
		/sbin/grub2-install --target=i386-pc  ${dev}
		echo "set legacy_bios=1" > /boot/grub2/grub.cfg
		echo "set boot_env_path=/efi/boot" >> /boot/grub2/grub.cfg
		echo "source /efi/boot/grub.cfg" >> /boot/grub2/grub.cfg
	else
		fatal "Error: No grub2 tools available"
	fi
	umount /boot
fi

if [ -d /sys/firmware/efi/efivars ] ;then
    if which efibootmgr >/dev/null 2>&1; then
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
        for oldboonum in `efibootmgr | grep "^Boot.*\* ${INSTBR}$" |sed "s/Boot\(.*\)\* ${INSTBR}/\1/g"`; do
            efibootmgr -b ${oldboonum} -B
        if [ "$EFIBOOT_FIRST" = "1" ]; then
            efibootmgr -b 0 -B >/dev/null 2>&1 || true
            efibootmgr -o 0 -b 0 -c -w -L "${INSTBR}" -d "${INSTDEV}" -p "${p1}" -l '\EFI\BOOT\bootx64.efi'
        else
            efibootmgr -c -w -L "${INSTBR}" -d "${INSTDEV}" -p "${p1}" -l '\EFI\BOOT\bootx64.efi'
        fi
        done
        efibootmgr -c -w -L "${INSTBR}" -d "${INSTDEV}" -p "${p1}" -l '\EFI\BOOT\bootx64.efi'
        umount /sys/firmware/efi/efivars
    fi
fi

if [ "$INSTPOST" = "shell" ] ; then
	echo " Entering interactive install shell, please exit to continue when done"
	shell_start
fi

# Clean up and finish
if [ "$INSTAB" = 1 ] ; then
	umount ${PHYS_SYSROOT}_b/boot/efi ${PHYS_SYSROOT}_b/boot ${PHYS_SYSROOT}_b
fi
umount ${PHYS_SYSROOT}/boot/efi ${PHYS_SYSROOT}/boot ${PHYS_SYSROOT}

# Save install.log to /var
if [ -e /install.log ]; then
    datetime=$(date +%y%m%d-%H%M%S)
    oklog="install-$datetime.log"
    echo "Save $oklog to installed /var"
    sleep 2
    cp /install.log /var1/$oklog
    chmod 644 /var1/$oklog
fi

umount /var1

for e in otaboot otaboot_b otaroot otaroot_b fluxdata; do
	if [ -e /dev/mapper/luks${e} ] ; then
		cryptsetup luksClose luks${e}
	fi
done

udevadm control -e

sync
sync
sync
echo 3 > /proc/sys/vm/drop_caches

# Eject installer ISO image if available
isodev=$(blkid --label ${ISO_INSTLABEL} -o device)
if [ $? -eq 0 ]; then
	eject $isodev
fi

if [ "$INSTPOST" = "halt" ] ; then
	echo o > /proc/sysrq-trigger
	while [ 1 ] ; do sleep 60; done
elif [ "$INSTPOST" = "shell" ] ; then
	echo " Entering post-install debug shell, exit to reboot."
	shell_start
elif [ "$INSTPOST" = "exit" ] ; then
	exit 0
fi
lreboot
exit 0
