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
import logging
import glob
from abc import ABCMeta, abstractmethod
import argparse
import atexit
import signal
from pykwalify.core import Core

from genimage.utils import get_today
from genimage.utils import show_task_info
from genimage.utils import yaml

import genimage.constant as constant
from genimage.constant import DEFAULT_MACHINE
from genimage.constant import DEFAULT_LOCAL_PACKAGE_FEED
from genimage.constant import DEFAULT_IMAGE_PKGTYPE
from genimage.constant import SUPPORTED_PKGTYPES
from genimage.rootfs import Rootfs

import genimage.utils as utils

logger = logging.getLogger('appsdk')

def set_parser(parser=None, supported_types=None):
    if parser is None:
        parser = argparse.ArgumentParser(
            description='Generate images from package feeds for specified machines',
            epilog='Use %(prog)s --help to get help')
        parser.add_argument('-d', '--debug',
            help = "Enable debug output",
            action='store_const', const=logging.DEBUG, dest='loglevel', default=logging.INFO)
        parser.add_argument('-q', '--quiet',
            help = 'Hide all output except error messages',
            action='store_const', const=logging.ERROR, dest='loglevel')

        parser.add_argument('--log-dir',
            default=None,
            dest='logdir',
            help='Specify dir to save debug messages as log.appsdk regardless of the logging level',
            action='store')

    if supported_types:
        parser.add_argument('-t', '--type',
            choices=supported_types,
            help='Specify image type, it overrides \'image_type\' in Yaml',
            action='append')

    parser.add_argument('-o', '--outdir',
        default=os.getcwd(),
        help='Specify output dir, default is current working directory',
        action='store')
    parser.add_argument('-w', '--workdir',
        default=os.getcwd(),
        help='Specify work dir, default is current working directory',
        action='store')
    parser.add_argument('-n', '--name',
        help='Specify image name, it overrides \'name\' in Yaml',
        action='store')
    parser.add_argument('-u', '--url',
        help='Specify extra urls of rpm package feeds',
        action='append')
    parser.add_argument('--pkg-type',
        choices=SUPPORTED_PKGTYPES,
        help='Specify package type, it overrides \'package_type\' in Yaml',
        action='store')
    parser.add_argument('-p', '--pkg',
        help='Specify extra package to be installed',
        action='append')
    parser.add_argument('--pkg-external',
        help='Specify extra external package to be installed',
        action='append')
    parser.add_argument('--rootfs-post-script',
        help='Specify extra script to run after do_rootfs',
        action='append')
    parser.add_argument('--rootfs-pre-script',
        help='Specify extra script to run before do_rootfs',
        action='append')
    parser.add_argument('--env',
        help='Specify extra environment to export before do_rootfs: --env NAME=VALUE',
        action='append').completer = complete_env
    parser.add_argument("--no-clean",
        help = "Do not cleanup previously generated rootfs in workdir", action="store_true", default=False)
    parser.add_argument("--no-validate",
        help = "Do not validate parameters in Input yaml files", action="store_true", default=False)

    parser.add_argument('input',
        help='Input yaml files that the tool can be run against a package feed to generate an image',
        action='store',
        nargs='*').completer = complete_input

    return parser

def complete_env(**kwargs):
    return ['NAME=VALUE']

def complete_input(parsed_args, **kwargs):
    yamls = list()
    for subdir in [".", "exampleyamls", "exampleyamls/feature", "exampleyamls/sysdef", "deploy"]:
        if not os.path.exists(os.path.join(parsed_args.outdir, subdir)):
            continue

        glob_yaml = os.path.join(parsed_args.outdir, subdir, "*.yaml")
        yamls.extend(glob.glob(glob_yaml))

    return [os.path.relpath(y) for y in yamls] or ["path_to_input_yamls"]


class GenXXX(object, metaclass=ABCMeta):
    """
    This is an abstract class. Do not instantiate this directly.
    """
    def __init__(self, args):
        self.args = args
        self.today = get_today()
        self.data = dict()

        self.pkg_type = self._get_pkg_type(args)

        self._parse_default()
        self._parse_inputyamls()
        self._parse_options()
        self._parse_amend()

        self.image_name = self.data['name']
        self.machine = self.data['machine']
        self.image_type = self.data['image_type']
        self.packages = self.data['packages']
        self.external_packages = self.data['external-packages']
        self.exclude_packages = []
        self.pkg_feeds = self.data['package_feeds']
        self.remote_pkgdatadir = self.data.get('remote_pkgdatadir', "")
        self.features = self.data.get('features', "")

        self.rootfs_post_scripts = self.data['rootfs-post-scripts']
        self.rootfs_pre_scripts = self.data['rootfs-pre-scripts']
        self.environments = self.data['environments']

        self.outdir = os.path.realpath(self.args.outdir)
        self.deploydir = os.path.join(self.outdir, "deploy")
        self.output_yaml = os.path.join(self.deploydir, "%s-%s.yaml" % (self.image_name, self.machine))
        utils.mkdirhier(self.deploydir)
        self.workdir = os.path.realpath(os.path.join(self.args.workdir, "workdir"))

        self.target_rootfs = None
        self.native_sysroot = os.environ['OECORE_NATIVE_SYSROOT']
        self.data_dir = os.path.join(self.native_sysroot, "usr/share/genimage/data")

        logger.info("Machine: %s" % self.machine)
        logger.info("Image Name: %s" % self.image_name)
        logger.info("Image Type: %s" % ' '.join(self.image_type))
        logger.info("Packages Number: %d" % len(self.packages))
        logger.debug("Packages: %s" % self.packages)
        logger.info("External Packages Number: %d" % len(self.external_packages))
        logger.debug("External Packages: %s" % self.external_packages)
        if utils.is_build():
            logger.info("Local Package Feeds To Generate Image:\n%s\n" % '\n'.join(DEFAULT_LOCAL_PACKAGE_FEED[self.pkg_type]))
            if self.pkg_feeds:
                logger.info("Remote Package Feeds as Target Yum Repo:\n%s\n" % '\n'.join(self.pkg_feeds))
        elif utils.is_sdk():
            logger.info("Package Feeds:\n%s\n" % '\n'.join(self.pkg_feeds))
        logger.info("enviroments: %s", self.environments)
        logger.debug("Deploy Directory: %s" % self.outdir)
        logger.debug("Work Directory: %s" % self.workdir)

        signal.signal(signal.SIGTERM, utils.signal_exit_handler)
        signal.signal(signal.SIGINT, utils.signal_exit_handler)

    @staticmethod
    def _get_pkg_type(args):
        pkg_type = DEFAULT_IMAGE_PKGTYPE

        # Collect package_type from input yamls
        if args.input:
            for input_glob in args.input:
                if not glob.glob(input_glob):
                    continue
                for yaml_file in glob.glob(input_glob):
                    with open(yaml_file) as f:
                        d = yaml.load(f) or dict()
                        if 'package_type' in d:
                            pkg_type = d['package_type']

        # Use option --pkg-type to override
        if args.pkg_type:
            pkg_type = args.pkg_type

        return pkg_type

    @abstractmethod
    def _parse_default(self):
        pass

    def _validate_inputyamls(self, yaml_file):
        if self.args.no_validate:
            logger.info("Do not validate parameters in %s", yaml_file)
            return

        try:
            pykwalify_dir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/share/genimage/data/pykwalify')
            extensions = [os.path.join(pykwalify_dir, 'ext.py')]
            c = Core(source_file=yaml_file, schema_files=self.pykwalify_schemas, extensions=extensions)
            c.validate(raise_exception=True)
        except Exception as e:
            logger.error("Load %s failed\n%s", yaml_file, e)
            sys.exit(1)

    def _parse_inputyamls(self):
        if not self.args.input:
            logger.info("No Input YAML File, use default setting")
            return

        data = dict()
        yaml_files = []
        for input_glob in self.args.input:
            if not glob.glob(input_glob):
                logger.warning("Input yaml file '%s' does not exist" % input_glob)
                continue
            yaml_files.extend(glob.glob(input_glob))

        for yaml_file in yaml_files:
            logger.info("Input YAML File: %s" % yaml_file)
            self._validate_inputyamls(yaml_file)

            with open(yaml_file) as f:
                d = yaml.load(f) or dict()

            for key in d:
                if key == 'machine':
                    if d[key] != DEFAULT_MACHINE:
                        logger.error("Load %s failed\nThe machine: %s is not supported", yaml_file, d[key])
                        sys.exit(1)
                    continue

                if key not in data:
                    data[key] = d[key]
                    continue

                # Collect them from all Yaml file as many as possible
                if key in ['packages',
                           'external-packages',
                           'image_type',
                           'environments',
                           'system',
                           'rootfs-pre-scripts',
                           'rootfs-post-scripts']:
                    data[key].extend(d[key])

                # Except packages, the duplicated param is not allowed
                elif key in data:
                    logger.error("There is duplicated '%s' in Yaml File %s", key, yaml_file)
                    sys.exit(1)

        include_default_package = self.data['include-default-packages']
        if 'include-default-packages' in data:
            include_default_package = data['include-default-packages']
        logger.info("Include Default Packages: %s" % include_default_package)

        logger.debug("Input Yaml File Content: %s" % data)
        for key in data:
            if include_default_package != "0" and 'packages' == key:
                self.data[key] += data[key]
                continue
            self.data[key] = data[key]

    def _parse_options(self):
        if self.args.name:
            self.data['name'] = self.args.name

        if self.args.url:
            self.data['package_feeds'].extend(self.args.url)

        if self.args.pkg:
            self.data['packages'].extend(self.args.pkg)

        if self.args.pkg_external:
            self.data['external-packages'].extend(self.args.pkg_external)

        if self.args.rootfs_post_script:
            self.data['rootfs-post-scripts'].extend(self.args.rootfs_post_script)

        if self.args.rootfs_pre_script:
            self.data['rootfs-pre-scripts'].extend(self.args.rootfs_pre_script)

        if self.args.env:
            self.data['environments'].extend(self.args.env)

    def _parse_amend(self):
        if self.data['machine'] != DEFAULT_MACHINE:
            logger.error("MACHINE %s is invalid, SDK is working for %s only" % (self.data['machine'], DEFAULT_MACHINE))
            sys.exit(1)

        # Sort and remove duplicated list except the section of environments,
        # rootfs-pre-scripts and rootfs-post-scripts
        for k,v in self.data.items():
            if isinstance(v, list) and k not in ['environments', 'rootfs-pre-scripts', 'rootfs-post-scripts', 'system']:
                self.data[k] = list(sorted(set(v)))

    def _save_output_yaml(self):
        # The output yaml does not require to include default packages
        self.data['include-default-packages'] = "0"
        with open(self.output_yaml, "w") as f:
            yaml.dump(self.data, f)
            logger.debug("Save Yaml FIle to : %s" % (self.output_yaml))

    def do_prepare(self):
        image_workdir = os.path.join(self.workdir, self.image_name)
        utils.mkdirhier(image_workdir)
        utils.fake_root(workdir=image_workdir)
        os.environ['PSEUDO_IGNORE_PATHS'] = self.deploydir
        # Cleanup previously generated rootfs dir by default
        if not self.args.no_clean:
            cmd = "rm -rf ./rootfs ./pseudo"
            utils.run_cmd_oneshot(cmd, cwd=image_workdir)

    def do_post(self):
        pass

    def _do_rootfs_pre(self, rootfs=None):
        if rootfs is None:
            return

        for script_cmd in self.rootfs_post_scripts:
            logger.debug("Add rootfs post script: %s", script_cmd)
            rootfs.add_rootfs_post_scripts(script_cmd)

        for script_cmd in self.rootfs_pre_scripts:
            logger.debug("Add rootfs pre script: %s", script_cmd)
            rootfs.add_rootfs_pre_scripts(script_cmd)

        for env in self.environments:
            k,v = env.split('=', 1)
            v = v.strip('"\'')
            logger.debug("Environment %s=%s", k, v)
            os.environ[k] = v

    def _do_rootfs_post(self, rootfs=None):
        if rootfs is None:
            return

        installed_dict = rootfs.image_list_installed_packages()

        self._save_output_yaml()

        # Generate image manifest
        manifest_name = "{0}/{1}-{2}.manifest".format(self.deploydir, self.image_name, self.machine)
        with open(manifest_name, 'w+') as image_manifest:
            image_manifest.write(utils.format_pkg_list(installed_dict, "ver"))

        self.target_rootfs = rootfs.target_rootfs

    @show_task_info("Create Rootfs")
    def do_rootfs(self):
        workdir = os.path.join(self.workdir, self.image_name)
        pkg_globs = self.features.get("pkg_globs", None)
        if pkg_globs is not None:
            # '*-dbg, *-dev' --> '*-dbg *-dev'
            pkg_globs = pkg_globs.replace(' ', '')
            pkg_globs = pkg_globs.replace(',', ' ')
        image_linguas = self.features.get("image_linguas", None)

        rootfs = Rootfs(workdir,
                        self.data_dir,
                        self.machine,
                        self.pkg_feeds,
                        self.packages,
                        external_packages=self.external_packages,
                        exclude_packages=self.exclude_packages,
                        remote_pkgdatadir=self.remote_pkgdatadir,
                        image_linguas=image_linguas,
                        pkgtype=self.pkg_type,
                        pkg_globs=pkg_globs)

        self._do_rootfs_pre(rootfs)

        rootfs.create()

        self._do_rootfs_post(rootfs)


