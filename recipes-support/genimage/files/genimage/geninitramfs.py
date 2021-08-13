#!/usr/bin/env python3
# PYTHON_ARGCOMPLETE_OK
#
# Copyright (C) 2020 Wind River Systems, Inc.
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

import os
import sys
import subprocess
import logging
from texttable import Texttable
import argcomplete

from genimage.utils import set_logger
from genimage.utils import show_task_info
import genimage.constant as constant
from genimage.constant import DEFAULT_MACHINE
from genimage.constant import DEFAULT_INITRD_NAME
from genimage.constant import OSTREE_INITRD_PACKAGES
from genimage.constant import DEFAULT_PACKAGE_FEED
from genimage.constant import DEFAULT_IMAGE_PKGTYPE
from genimage.constant import DEFAULT_REMOTE_PKGDATADIR
from genimage.constant import DEFAULT_IMAGE_FEATURES
from genimage.image import CreateInitramfs
from genimage.genXXX import set_parser
from genimage.genXXX import GenXXX
from genimage.rootfs import ExtDebRootfs
import genimage.debian_constant as deb_constant

import genimage.utils as utils

logger = logging.getLogger('appsdk')

def set_parser_geninitramfs(parser=None):
    parser = set_parser(parser, None)
    parser.add_argument('-g', '--gpgpath',
        default=None,
        help='Specify gpg homedir, it overrides \'gpg_path\' in Yaml, default is /tmp/.lat_gnupg',
        action='store')
    return parser

class GenInitramfs(GenXXX):
    """
    Generate Initramfs
    """

    def __init__(self, args):
        super(GenInitramfs, self).__init__(args)
        logger.debug("GPG Path: %s" % self.data["gpg"]["gpg_path"])

    def _parse_default(self):
        self.data['name'] = DEFAULT_INITRD_NAME
        self.data['machine'] = DEFAULT_MACHINE
        self.data['image_type'] = ['initramfs']
        self.data['package_feeds'] = DEFAULT_PACKAGE_FEED[self.pkg_type] if utils.is_sdk() or self.pkg_type == "external-debian" else []
        self.data['package_type'] = self.pkg_type
        self.data["gpg"] = constant.DEFAULT_GPG_DATA
        self.data['packages'] = OSTREE_INITRD_PACKAGES
        self.data['external-packages'] = []
        self.data['include-default-packages'] = "1"
        self.data['rootfs-pre-scripts'] = ['echo "run script before do_rootfs in $IMAGE_ROOTFS"']
        self.data['rootfs-post-scripts'] = ['echo "run script after do_rootfs in $IMAGE_ROOTFS"']
        self.data['environments'] = ['NO_RECOMMENDATIONS="1"']

    def _parse_inputyamls(self):
        pykwalify_dir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/share/genimage/data/pykwalify')
        self.pykwalify_schemas = [os.path.join(pykwalify_dir, 'partial-schemas.yaml')]
        self.pykwalify_schemas.append(os.path.join(pykwalify_dir, 'geninitramfs-schema.yaml'))

        super(GenInitramfs, self)._parse_inputyamls()

    def _parse_options(self):
        super(GenInitramfs, self)._parse_options()
        if self.args.gpgpath:
            self.data["gpg"]["gpg_path"] = os.path.realpath(self.args.gpgpath)

    def _do_rootfs_pre(self, rootfs=None):
        if rootfs is None:
            return

        super(GenInitramfs, self)._do_rootfs_pre(rootfs)

        script_cmd = os.path.join(self.data_dir, 'post_rootfs', 'add_gpg_key.sh')
        script_cmd = "{0} {1} {2}".format(script_cmd, rootfs.target_rootfs, self.data['gpg']['gpg_path'])
        rootfs.add_rootfs_post_scripts(script_cmd)

    def do_prepare(self):
        super(GenInitramfs, self).do_prepare()
        gpg_data = self.data["gpg"]
        utils.check_gpg_keys(gpg_data)

    @show_task_info("Create Initramfs")
    def do_ostree_initramfs(self):
        if self.image_name == DEFAULT_INITRD_NAME:
            logger.info("Replace eixsted %s as initrd for appsdk genimage", DEFAULT_INITRD_NAME)

        # If the Initramfs exists, reuse it
        image_name = "{0}-{1}.cpio.gz".format(self.image_name, self.machine)
        if self.machine == "bcm-2xxx-rpi4":
            image_name += ".u-boot"


        workdir = os.path.join(self.workdir, self.image_name)

        initrd = CreateInitramfs(
                        image_name = self.image_name,
                        workdir = workdir,
                        machine = self.machine,
                        target_rootfs = self.target_rootfs,
                        pkg_type = self.pkg_type,
                        deploydir = self.deploydir)
        initrd.create()

    def do_report(self):
        table = Texttable()
        table.set_cols_align(["l", "l"])
        table.set_cols_valign(["t", "t"])

        image_name = "%s-%s" % (self.image_name, self.machine)
        cmd_format = "ls -gh --time-style=+%%Y %s | awk '{$1=$2=$3=$4=$5=\"\"; print $0}'"
        if self.machine == "bcm-2xxx-rpi4":
            cmd = cmd_format % "{0}.cpio.gz.u-boot".format(image_name)
        else:
            cmd = cmd_format % "{0}.cpio.gz".format(image_name)
        output = subprocess.check_output(cmd, shell=True, cwd=self.deploydir)
        table.add_row(["Image", output.strip()])

        logger.info("Deploy Directory: %s\n%s", self.deploydir, table.draw())

class GenYoctoInitramfs(GenInitramfs):
    def __init__(self, args):
        super(GenYoctoInitramfs, self).__init__(args)
        self.exclude_packages = ['busybox-syslog']

    def _parse_default(self):
        super(GenYoctoInitramfs, self)._parse_default()
        self.data['remote_pkgdatadir'] = DEFAULT_REMOTE_PKGDATADIR[self.pkg_type] if utils.is_sdk() else ""
        self.data['features'] =  DEFAULT_IMAGE_FEATURES
        self.data['environments'] = ['NO_RECOMMENDATIONS="1"']


class GenExtDebInitramfs(GenInitramfs):
    def __init__(self, args):
        super(GenExtDebInitramfs, self).__init__(args)
        self.debian_mirror, self.debian_distro, self.debian_components = utils.get_debootstrap_input(self.data['package_feeds'],
                                                                             deb_constant.DEFAULT_DEBIAN_DISTROS)
        self.apt_sources = "\n".join(self.data['package_feeds'])
        self.apt_preference = deb_constant.DEFAULT_APT_PREFERENCE

    def _parse_default(self):
        super(GenExtDebInitramfs, self)._parse_default()
        self.data['name'] = deb_constant.DEFAULT_INITRD_NAME
        self.data['packages'] = deb_constant.OSTREE_INITRD_PACKAGES
        self.data['include-default-packages'] = "1"
        self.data['rootfs-post-scripts'] = [deb_constant.SCRIPT_DEBIAN_INITRD_REDUCE_SIZE,
                                            deb_constant.SCRIPT_DEBIAN_SET_BASH]
        self.data['environments'] = ['NO_RECOMMENDATIONS="1"', 'DEBIAN_FRONTEND=noninteractive']

    @show_task_info("Create External Debian Rootfs")
    def do_rootfs(self):
        workdir = os.path.join(self.workdir, self.image_name)

        rootfs = ExtDebRootfs(workdir,
                        self.data_dir,
                        self.machine,
                        self.debian_mirror,
                        self.debian_distro,
                        self.debian_components,
                        self.apt_sources,
                        self.apt_preference,
                        self.packages,
                        self.image_type,
                        external_packages=self.external_packages,
                        exclude_packages=self.exclude_packages)

        self._do_rootfs_pre(rootfs)

        rootfs.create()

        self._do_rootfs_post(rootfs)

def _main_run_internal(args):
    pkg_type = GenInitramfs._get_pkg_type(args)
    if pkg_type == "external-debian":
        if os.getuid() != 0:
            logger.info("The external debian image generation requires root privilege")
            sys.exit(1)
        create = GenExtDebInitramfs(args)
    else:
        create = GenYoctoInitramfs(args)
    create.do_prepare()
    create.do_rootfs()
    if create.target_rootfs is None:
        logger.error("Create Target Rootfs Failed")
        sys.exit(1)
    else:
        logger.debug("Create Target Rootfs: %s" % create.target_rootfs)

    create.do_ostree_initramfs()

    create.do_post()
    create.do_report()

def _main_run(args):
    try:
        ret = _main_run_internal(args)
    except Exception as e:
            logger.error(e)
            raise

def main_geninitramfs():
    parser = set_parser_geninitramfs()
    parser.set_defaults(func=_main_run)
    argcomplete.autocomplete(parser)
    args = parser.parse_args()
    set_logger(logger, level=args.loglevel, log_path=args.logdir)
    args.func(args)

def set_subparser_geninitramfs(subparsers=None):
    if subparsers is None:
        sys.exit(1)
    parser_genimage = subparsers.add_parser('geninitramfs', help='Generate Initramfs from package feeds for specified machines')
    parser_genimage = set_parser_geninitramfs(parser_genimage)
    parser_genimage.set_defaults(func=_main_run)

if __name__ == "__main__":
    main()
