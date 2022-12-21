#!/usr/bin/env python3
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
import argcomplete
from texttable import Texttable
import atexit

from genimage.utils import set_logger
from genimage.utils import show_task_info
from genimage.constant import DEFAULT_CONTAINER_NAME
from genimage.constant import DEFAULT_CONTAINER_PACKAGES
from genimage.constant import DEFAULT_OCI_CONTAINER_DATA
from genimage.constant import DEFAULT_MACHINE
from genimage.constant import DEFAULT_PACKAGE_FEED
from genimage.constant import DEFAULT_IMAGE_PKGTYPE
from genimage.constant import DEFAULT_REMOTE_PKGDATADIR
from genimage.constant import DEFAULT_IMAGE_FEATURES
from genimage.constant import SUPPORTED_ARM64_MACHINES
from genimage.constant import SUPPORTED_ARM32_MACHINES
from genimage.container import CreateContainer
from genimage.genXXX import set_parser
from genimage.genXXX import GenXXX
from genimage.rootfs import ExtDebRootfs
import genimage.debian_constant as deb_constant

import genimage.utils as utils

logger = logging.getLogger('appsdk')

def set_parser_gencontainer(parser=None):
    return set_parser(parser, None)


class GenContainer(GenXXX):
    """
    Generate Container Image
    """

    def __init__(self, args):
        super(GenContainer, self).__init__(args)
        if not self.data['container_upload_cmd'] or self.data['container_upload_cmd'].startswith('#'):
            skopeo_opt = "--dest-tls-verify=false --insecure-policy"
            src_image = "docker-archive:{0}/{1}-{2}.docker-image.tar.bz2".format(os.path.relpath(self.deploydir), self.image_name, self.machine)
            dest_image = "docker://<PRIVATE-DOCKER-REGISTRY-SITE>:<PORT>/{0}-{1}".format(self.image_name, self.machine)
            self.data['container_upload_cmd'] = "#skopeo copy {0} {1} {2}".format(skopeo_opt, src_image, dest_image)

    def _parse_default(self):
        self.data['name'] = DEFAULT_CONTAINER_NAME
        self.data['machine'] = DEFAULT_MACHINE
        self.data['image_type'] = ['container']
        self.data['package_feeds'] = DEFAULT_PACKAGE_FEED[self.pkg_type] if utils.is_sdk() or self.pkg_type == "external-debian" else []
        self.data['package_type'] = self.pkg_type
        self.data['packages'] = DEFAULT_CONTAINER_PACKAGES
        self.data['external-packages'] = []
        self.data['include-default-packages'] = "1"
        self.data['rootfs-pre-scripts'] = ['echo "run script before do_rootfs in $IMAGE_ROOTFS"']
        self.data['rootfs-post-scripts'] = ['echo "run script after do_rootfs in $IMAGE_ROOTFS"']
        self.data['environments'] = ['NO_RECOMMENDATIONS="1"']
        self.data['container_oci'] = DEFAULT_OCI_CONTAINER_DATA
        self.data['container_upload_cmd'] = ""

    def _parse_inputyamls(self):
        pykwalify_dir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/share/genimage/data/pykwalify')
        self.pykwalify_schemas = [os.path.join(pykwalify_dir, 'partial-schemas.yaml')]
        self.pykwalify_schemas.append(os.path.join(pykwalify_dir, 'gencontainer-schema.yaml'))

        super(GenContainer, self)._parse_inputyamls()

    @show_task_info("Create Docker Container")
    def do_image_container(self):
        workdir = os.path.join(self.workdir, self.image_name)
        container = CreateContainer(
                        image_name=self.image_name,
                        workdir=workdir,
                        machine=self.machine,
                        target_rootfs=self.target_rootfs,
                        deploydir=self.deploydir,
                        pkg_type = self.pkg_type,
                        container_oci=self.data['container_oci'])
        container.create()

    def do_upload(self):
        if self.data['container_upload_cmd'] and not self.data['container_upload_cmd'].startswith('#'):
            cmd = self.data['container_upload_cmd']
            logger.info("Run the following command to upload container image:\n   %s", cmd)
            output = subprocess.check_output(cmd, shell=True)
            logger.info("Result: %s", output.decode())
        else:
            logger.info("You could run the following command to upload container image manually:\n   %s", self.data['container_upload_cmd'].replace("#", ""))


    def do_report(self):
        table = Texttable()
        table.set_cols_align(["l", "l"])
        table.set_cols_valign(["t", "t"])

        image_name = "%s-%s" % (self.image_name, self.machine)
        cmd_format = "ls -gh --time-style=+%%Y %s | awk '{$1=$2=$3=$4=$5=\"\"; print $0}'"

        cmd = cmd_format % "{0}.docker-image.tar.bz2".format(image_name)
        output = subprocess.check_output(cmd, shell=True, cwd=self.deploydir)
        table.add_row(["Docker Image", output.strip()])

        cmd = "ls -d {0}.rootfs-oci".format(image_name)
        output = subprocess.check_output(cmd, shell=True, cwd=self.deploydir)
        table.add_row(["OCI Image Rootfs", output.strip()])

        cmd = cmd_format % "{0}.container.README.md".format(image_name)
        output = subprocess.check_output(cmd, shell=True, cwd=self.deploydir)
        table.add_row(["Container Image Doc", output.strip()])

        cmd = cmd_format % "{0}.startup-container.yaml".format(image_name)
        output = subprocess.check_output(cmd, shell=True, cwd=self.deploydir)
        table.add_row(["Yaml file for genimage\nto load and run", output.strip()])

        logger.info("Deploy Directory: %s\n%s", self.deploydir, table.draw())


class GenYoctoContainer(GenContainer):
    """
    Generate Yocto Container Image
    """
    def _parse_default(self):
        super(GenYoctoContainer, self)._parse_default()
        self.data['remote_pkgdatadir'] = DEFAULT_REMOTE_PKGDATADIR[self.pkg_type] if utils.is_sdk() else ""
        self.data['features'] =  DEFAULT_IMAGE_FEATURES
        if DEFAULT_MACHINE == 'intel-x86-64' or DEFAULT_MACHINE == 'amd-snowyowl-64':
            self.data['container_oci']['OCI_IMAGE_ARCH'] = 'x86-64'
        elif DEFAULT_MACHINE in SUPPORTED_ARM64_MACHINES:
            self.data['container_oci']['OCI_IMAGE_ARCH'] = 'aarch64'
        elif DEFAULT_MACHINE in SUPPORTED_ARM32_MACHINES:
            self.data['container_oci']['OCI_IMAGE_ARCH'] = 'arm'


class GenExtDebContainer(GenContainer):
    def __init__(self, args):
        super(GenExtDebContainer, self).__init__(args)
        self.debian_mirror, self.debian_distro, self.debian_components = utils.get_debootstrap_input(self.data['package_feeds'],
                                                                             deb_constant.DEFAULT_DEBIAN_DISTROS)
        self.apt_sources = "\n".join(self.data['package_feeds'])
        self.apt_preference = deb_constant.DEFAULT_APT_PREFERENCE
        self.debian_mirror = self.data['debootstrap-mirror']
        self.debootstrap_key = self.data['debootstrap-key']
        self.apt_keys = self.data['apt-keys']

    def _parse_default(self):
        super(GenExtDebContainer, self)._parse_default()
        self.data['name'] = deb_constant.DEFAULT_CONTAINER_NAME
        self.data['packages'] = deb_constant.DEFAULT_CONTAINER_PACKAGES
        self.data['include-default-packages'] = "1"
        self.data['rootfs-post-scripts'] = [deb_constant.SCRIPT_DEBIAN_SSH_ROOT_LOGIN]
        self.data['environments'] = ['NO_RECOMMENDATIONS="1"', 'DEBIAN_FRONTEND=noninteractive']
        self.data['container_oci']['OCI_IMAGE_ARCH'] = 'x86-64'
        self.data['debootstrap-mirror'] = deb_constant.DEFAULT_DEBIAN_MIRROR
        self.data['debootstrap-key'] = ""
        self.data['apt-keys'] = []

    def do_prepare(self):
        target_rootfs = os.path.join(self.workdir, self.image_name, "rootfs")
        utils.umount(target_rootfs)
        atexit.register(utils.umount, target_rootfs)
        super(GenExtDebContainer, self).do_prepare()

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
                        debootstrap_key=self.debootstrap_key,
                        apt_keys=self.apt_keys,
                        external_packages=self.external_packages,
                        exclude_packages=self.exclude_packages)

        self._do_rootfs_pre(rootfs)

        rootfs.create()

        self._do_rootfs_post(rootfs)

def _main_run_internal(args):
    pkg_type = GenContainer._get_pkg_type(args)
    if pkg_type == "external-debian":
        if os.getuid() != 0:
            logger.info("The external debian image generation requires root privilege")
            sys.exit(1)
        create = GenExtDebContainer(args)
    else:
        create = GenYoctoContainer(args)
    create.do_prepare()
    create.do_rootfs()
    if create.target_rootfs is None:
        logger.error("Create Target Rootfs Failed")
        sys.exit(1)
    else:
        logger.debug("Create Target Rootfs: %s" % create.target_rootfs)

    create.do_image_container()
    create.do_upload()
    create.do_post()
    create.do_report()

def _main_run(args):
    try:
        ret = _main_run_internal(args)
    except Exception as e:
            logger.error(e)
            raise

def main_gencontainer():
    parser = set_parser_gencontainer()
    parser.set_defaults(func=_main_run)
    argcomplete.autocomplete(parser)
    args = parser.parse_args()
    set_logger(logger, level=args.loglevel, log_path=args.logdir)
    args.func(args)

def set_subparser_gencontainer(subparsers=None):
    if subparsers is None:
        sys.exit(1)
    parser_genimage = subparsers.add_parser('gencontainer', help='Generate Container Image from package feeds for specified machines')
    parser_genimage = set_parser_gencontainer(parser_genimage)
    parser_genimage.set_defaults(func=_main_run)

if __name__ == "__main__":
    main()
