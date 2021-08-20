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
include appsdk.inc

SRC_URI += " \
    file://0001-do-not-support-subcommand-gensdk.patch \
"
DEPENDS = " \
    genimage-native \
    python3-argcomplete-native \
"

inherit native

do_install:append() {
	install -d ${D}${base_bindir}
	install -m 0755 ${D}${bindir}/appsdk ${D}${base_bindir}/appsdk
	create_wrapper ${D}${bindir}/appsdk PATH='$(dirname `readlink -fn $0`):$PATH'
}

do_install[nostamp] = "1"

# Workaround manifest missing failure
python do_prepare_recipe_sysroot:prepend () {
    machine = d.getVar('MACHINE')
    if machine in (d.getVar('OSTREE_SUPPORTED_ARM64_MACHINES') or '').split():
        d.setVar('TARGET_ARCH', 'aarch64')
    elif machine in (d.getVar('OSTREE_SUPPORTED_ARM32_MACHINES') or '').split():
        d.setVar('TARGET_ARCH', 'arm')
}
