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

USE_ECHO="echo"

usage() {
	cat<<EOF
usage: $0 [args]

  This command will reset the /etc directory based on the contents of
  /usr/etc.  The default is to leave the fstab and machine-id the same.

  -f    Restore /etc to its original state (skipping fstab and machine-id)
  -v    verbose
  -n    dry run
  -F    Reset everything, including fstab and machine-id

EOF
	exit 0
}

if [ $# -lt 1 ] ; then
	usage
fi
verbose=""
EXCLUDE_PIPE='|grep -v -E "^.....(fstab|machine-id)"'
while getopts "Ffnv" opt; do
	case ${opt} in
		v)
			verbose=-v
			;;
		n)
		        echo "##Run commands to restore /etc##"
			;;
		f)
			USE_ECHO=""
			;;
		F)
			USE_ECHO=""
			EXCLUDE_PIPE=''
			;;
		\?) usage
			;;
	esac
done
#EXCLUDE_PIPE=''
set -e
eval "ostree admin config-diff|sort -r $EXCLUDE_PIPE"|
while IFS= read -r line ; do
	op=${line:0:1}
	line=${line:5}
	if [ "$op" = "A" ] ; then
		if [ -L "/etc/$line" ] ; then
			$USE_ECHO rm $verbose -f "/etc/$line"
		elif [ -d "/etc/$line" ] ; then
			$USE_ECHO rm $verbose -rf "/etc/$line"
		else
			$USE_ECHO rm $verbose -f "/etc/$line"
		fi
	elif [ "$op" = "D" ] ; then
		$USE_ECHO cp $verbose -a "/usr/etc/$line" "/etc/$line"
	elif [ "$op" = "M" ] ; then
		if [ -d "/etc/$line" ] ; then
			if [ -n "$USE_ECHO" ] ; then
				echo "(cd /usr/etc ; tar --xattrs --xattrs-include=security.ima --no-recursion -cf - \"$line\" )| tar -C /etc --xattrs --xattrs-include=security.ima $verbose -xf -"
			else
				(cd /usr/etc ; tar --xattrs --xattrs-include=security.ima --no-recursion -cf - "$line" )| tar -C /etc --xattrs --xattrs-include=security.ima $verbose -xf -
			fi
		else
			$USE_ECHO rm $verbose -f "/etc/$line"
			$USE_ECHO cp $verbose -a "/usr/etc/$line" "/etc/$line"
		fi
	fi
done

# Final check to see if FLUXDATA support is turned on
check=`ostree config get upgrade.noflux 2>/dev/null`
if [ "$check" = 1 ] ; then
	$USE_ECHO sed -i -e  's/^LABEL=fluxdata.*//' /etc/fstab
	if [ "$USE_ECHO" = "" -a "$verbose" != "" ] ; then
		echo "sed -i -e  's/^LABEL=fluxdata.*//' /etc/fstab"
	fi
fi
