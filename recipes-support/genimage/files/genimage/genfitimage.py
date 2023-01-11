#!/usr/bin/env python3
#
# Copyright (C) 2022 Wind River Systems, Inc.
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
import argparse
from texttable import Texttable
import signal
import glob
import atexit

from genimage.utils import set_logger
from genimage.utils import show_task_info
from genimage.utils import get_today
from genimage.utils import yaml
from genimage.genXXX import complete_input
from genimage.genXXX import GenXXX
from genimage.image import CreateOstreeRepo
from genimage.image import CreateOstreeOTA
from genimage.image import CreateWicImage
from genimage.sysdef import install_files

import genimage.utils as utils

import genimage.fit_constant as fit_constant
import genimage.constant as constant

from genimage.constant import USE_FIT
from genimage.constant import DEFAULT_MACHINE
from genimage.constant import DEFAULT_OSTREE_DATA
from genimage.fit_constant import DEFAULT_GPG_DATA
from genimage.fit_constant import DEFAULT_FIT_IMAGE_NAME
from genimage.fit_constant import DEFAULT_FIT_CONFIG
from genimage.fit_constant import DEFAULT_WIC_CONFIG
from genimage.constant import DEFAULT_WIC_FMU_CONFIG
from genimage.fit_constant import DEFAULT_BOOT_SCR
from genimage.fit_constant import DEFAULT_BOOT_ATF
from genimage.fit_constant import DEFAULT_BOOT_SCR_PRE
from genimage.fit_constant import DEFAULT_FIT_INPUTS
from genimage.fit_constant import DEFAULT_ROOTFS_IMAGES
from genimage.fit_constant import DEFAULT_ENNVIRONMENTS
from genimage.fit_constant import DEFAULT_LX_ROOTFS_SCRIPT
from genimage.fit_constant import DEFAULT_VX_APP_SCRIPT
from genimage.fit_constant import DEFAULT_WIC_POST_SCRIPT


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
            help='Specify directory to save debug messages as log.appsdk regardless of the logging level',
            action='store')

    parser.add_argument('-o', '--outdir',
        default=os.getcwd(),
        help='Specify output directory, default is current working directory',
        action='store')
    parser.add_argument('-w', '--workdir',
        default=os.getcwd(),
        help='Specify work directory, default is current working directory',
        action='store')
    parser.add_argument('-n', '--name',
        help='Specify image name, it overrides \'name\' in Yaml',
        action='store')
    parser.add_argument("--no-clean",
        help = "Do not cleanup previously generated rootfs in workdir", action="store_true", default=False)
    parser.add_argument("--no-validate",
        help = "Do not validate parameters in Input yaml files", action="store_true", default=False)

    parser.add_argument('input',
        help='Input yaml files that the tool can be run against a package feed to generate an image',
        action='store',
        nargs='*').completer = complete_input

    return parser


def set_parser_genfitimage(parser=None):
    return set_parser(parser, None)


class GenFitImage(GenXXX):
    """
    Generate FIT Image
    """
    def __init__(self, args):
        self.args = args
        self.today = get_today()
        self.data = dict()

        self._parse_default()
        self._parse_inputyamls()
        self._parse_options()
        self._parse_amend()

        self.image_name = self.data['name']
        self.machine = self.data['machine']
        self.image_type = self.data['image_type']

        self.outdir = os.path.realpath(self.args.outdir)
        self.deploydir = os.path.join(self.outdir, 'deploy')
        self.output_yaml = os.path.join(self.deploydir, '%s-%s.yaml' % (self.image_name, self.machine))
        utils.mkdirhier(self.deploydir)
        self.workdir = os.path.realpath(os.path.join(self.args.workdir, 'workdir'))

        self.target_lxrootfs = None
        self.native_sysroot = os.environ['OECORE_NATIVE_SYSROOT']
        self.data_dir = os.path.join(self.native_sysroot, "usr/share/genimage/data")

        self.fit_config = None
        self.boot_scr = None
        self.boot_atf = None
        self.wic_config = None
        self.lx_rootfs_script = None
        self.vx_app_script = None
        self.wic_post_script = None
        self.fit_inputs = {}
        self.rootfs_images = {}
        for key in ['lx-kernel', 'lx-initrd', 'lx-fdtb', 'vx-kernel', 'hvp', 'hvp-b']:
            self.fit_inputs[key] = None

        for key in ['lx-rootfs', 'vx-app']:
            self.rootfs_images[key] = None


        logger.info("Machine: %s" % self.machine)
        logger.info("Image Name: %s" % self.image_name)
        logger.info("Image Type: %s" % ' '.join(self.image_type))
        logger.debug("Deploy Directory: %s" % self.outdir)
        logger.debug("Work Directory: %s" % self.workdir)

        signal.signal(signal.SIGTERM, utils.signal_exit_handler)
        signal.signal(signal.SIGINT, utils.signal_exit_handler)

    def _parse_default(self):
        self.data['name'] = DEFAULT_FIT_IMAGE_NAME
        self.data['machine'] = DEFAULT_MACHINE
        self.data['image_type'] = ['fit']
        self.data['boot-scr'] = DEFAULT_BOOT_SCR
        self.data['boot-atf'] = DEFAULT_BOOT_ATF
        self.data['boot-scr-pre'] = DEFAULT_BOOT_SCR_PRE
        self.data['fit-config'] = DEFAULT_FIT_CONFIG
        self.data['fit-input-files'] = DEFAULT_FIT_INPUTS
        self.data['rootfs-images'] = DEFAULT_ROOTFS_IMAGES
        self.data["ostree"] = DEFAULT_OSTREE_DATA
        self.data["ostree"]['ostree_branchname'] = constant.DEFAULT_IMAGE
        self.data["gpg"] = DEFAULT_GPG_DATA
        self.data['ota-manager'] = 'fmu'  if constant.IS_FMU_ENABLED == 'true' else ''
        self.data['wic-config'] = DEFAULT_WIC_FMU_CONFIG if constant.IS_FMU_ENABLED == 'true' else DEFAULT_WIC_CONFIG
        self.data['lx-rootfs-script'] = DEFAULT_LX_ROOTFS_SCRIPT
        self.data['vx-app-script'] = DEFAULT_VX_APP_SCRIPT
        self.data['wic-post-script'] = DEFAULT_WIC_POST_SCRIPT
        self.data['environments'] = DEFAULT_ENNVIRONMENTS

    def _parse_inputyamls(self):
        if not self.args.input:
            logger.info("No Input YAML File, use default setting")
            return

        pykwalify_dir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/share/genimage/data/pykwalify')
        self.pykwalify_schemas = [os.path.join(pykwalify_dir, 'partial-schemas.yaml')]
        self.pykwalify_schemas.append(os.path.join(pykwalify_dir, 'genfitimage-schema.yaml'))

        yaml_files = []
        for input_glob in self.args.input:
            if not glob.glob(input_glob):
                logger.warning("Input yaml file '%s' does not exist" % input_glob)
                continue
            yaml_files.extend(glob.glob(input_glob))
        data = utils.parse_yamls(yaml_files, self.args.no_validate, self.pykwalify_schemas)

        logger.debug("Input Yaml File Content: %s" % data)
        for key in data:
            self.data[key] = data[key]


    def _parse_options(self):
        if self.args.name:
            self.data['name'] = self.args.name

    def _parse_amend(self):
        if self.data['machine'] != DEFAULT_MACHINE:
            logger.error("MACHINE %s is invalid, SDK is working for %s only" % (self.data['machine'], DEFAULT_MACHINE))
            sys.exit(1)

        # Use default to fill missing params of "ostree" section
        for ostree_param in DEFAULT_OSTREE_DATA:
            if ostree_param not in self.data["ostree"]:
                self.data["ostree"][ostree_param] = DEFAULT_OSTREE_DATA[ostree_param]

        # Sort and remove duplicated list with exceptions
        for k,v in self.data.items():
            if isinstance(v, list) and k not in ['lx-rootfs-script',
                                                 'vx-app-script',
                                                 'wic-post-script',
                                                 'environments']:
                self.data[k] = list(sorted(set(v)))

        if self.data['ota-manager'] != 'fmu' and self.data['wic-config'].find(' --label apps ') > 0:
            logger.error("The ota-manager is not `fmu', `apps' partition is not required in wic-config, remove it")
            sys.exit(1)

    def _save_output_yaml(self):
        # The output yaml does not require to include default packages
        try:
            with open(self.output_yaml, "w") as f:
                yaml.dump(self.data, f)
                logger.debug("Save Yaml File to : %s" % (self.output_yaml))
        except Exception as e:
            logger.error("Save Yaml File to %s failed\n%s" % (self.output_yaml, e))
            raise

    @show_task_info("Fetch files")
    def do_fetch(self):
        for key, dst in {'boot-scr': 'boot.scr',
                         'boot-atf': 'atf-%s.s32' % self.data['machine'],
                         'fit-config': '%s-%s.its' % (self.data['name'], self.data['machine']),
                         'lx-rootfs-script': '%s-lxrootfs.sh' % (self.data['name']),
                         'vx-app-script': '%s-vxapp.sh' % (self.data['name']),
                         'wic-post-script': '%s-wic-post.sh' % (self.data['name']),
                         'wic-config': '%s-%s.wks.in' % (self.data['name'], self.data['machine'])}.items():
            src = self.data.get(key, False)
            if not src:
                continue
            # src is url or path, fetch it
            src = os.path.expandvars(src)
            if src.startswith("http") or os.path.exists(src) or src.startswith("mc cp"):
                dst = os.path.join(self.deploydir, 'downloads', os.path.basename(src))
                fetch_node = {'src': src, 'dst': dst}
                install_files([fetch_node], self.deploydir)
            else:
                # src is text content, save it to a file
                dst = os.path.join(self.deploydir, 'downloads', dst)
                try:
                    with open(dst, 'w') as f:
                        f.write(src)
                except Exception as e:
                   logger.error("Save %s failed\n%s" % (dst, e))
                   raise

            if key == 'boot-scr':
                self.boot_scr = dst
            elif key == 'boot-atf':
                self.boot_atf = dst
            elif key == 'fit-config':
                self.fit_config = dst
            elif key == 'wic-config':
                self.wic_config = dst
            elif key == 'lx-rootfs-script':
                self.lx_rootfs_script = dst
            elif key == 'vx-app-script':
                self.vx_app_script = dst
            elif key == 'wic-post-script':
                self.wic_post_script = dst

        for key in self.data['fit-input-files']:
            src = self.data['fit-input-files'].get(key, False)
            if not src:
                continue
            src = os.path.expandvars(src)
            # src is url or path, fetch it
            if src.startswith("http") or os.path.exists(src) or src.startswith("mc cp"):
                dst = os.path.join(self.deploydir, 'downloads', os.path.basename(src))
                fetch_node = {'src': src, 'dst': dst}
                install_files([fetch_node], self.deploydir)
                self.fit_inputs[key] = dst

        for key in self.data['rootfs-images']:
            src = self.data['rootfs-images'].get(key, False)
            if not src:
                continue
            src = os.path.expandvars(src)
            # src is url or path, fetch it
            if src.startswith("http") or os.path.exists(src) or src.startswith("mc cp"):
                dst = os.path.join(self.deploydir, 'downloads', os.path.basename(src))
                fetch_node = {'src': src, 'dst': dst}
                install_files([fetch_node], self.deploydir)
                self.rootfs_images[key] = dst

        for key in self.data.get('secure-boot-map', []):
            src = self.data['secure-boot-map'].get(key, False)
            if not src:
                continue
            src = os.path.expandvars(src)
            # src is url or path, fetch it
            if src.startswith("http") or os.path.exists(src) or src.startswith("mc cp"):
                dst = os.path.join(self.deploydir, 'downloads', os.path.basename(src))
                fetch_node = {'src': src, 'dst': dst}
                install_files([fetch_node], self.deploydir)


    def do_prepare(self):
        super(GenFitImage, self).do_prepare()
        self.workdir = os.path.realpath(os.path.join(self.args.workdir, "workdir", self.image_name))
        self.target_lxrootfs = os.path.join(self.workdir, 'rootfs')

        gpg_data = self.data["gpg"]
        utils.check_gpg_keys(gpg_data)

        # Cleanup all generated available rootfs, pseudo, rootfs_ota dir by default
        if not self.args.no_clean:
            atexit.register(utils.cleanup, self.workdir, self.data['ostree']['ostree_osname'])

    def do_patch(self):
        self._modify_boot_scr()

    def _modify_boot_scr(self):
        if not os.path.exists(self.boot_scr):
            logger.error("boot script %s does not exist", self.boot_scr)
            sys.exit(1)

        boot_scr_content = self.data['boot-scr-pre']
        try:
            with open(self.boot_scr, 'r') as f:
                f.seek(73)
                boot_scr_content += f.read()
        except Exception as e:
            logger.error("Read %s failed\n%s" % (self.boot_scr, e))
            raise

        self.boot_scr = os.path.join(self.deploydir, os.path.basename(self.boot_scr))
        boot_scr_raw = self.boot_scr + ".raw"
        try:
            with open(boot_scr_raw, 'w') as f:
                f.write(boot_scr_content)
        except Exception as e:
            logger.error("Write %s failed\n%s" % (self.boot_scr_raw, e))
            raise

        cmd = "mkimage -A arm -T script -O linux -d %s %s" % (boot_scr_raw, self.boot_scr)
        res, output = utils.run_cmd(cmd, shell=True, cwd=self.deploydir)
        if res != 0:
            logger.error(output)
            sys.exit(1)

    @show_task_info("Create FIT kernel")
    def do_fit_kernel(self):
        if not os.path.exists(self.fit_config):
            logger.error("Fit configuration %s does not exist", self.fit_config)
            sys.exit(1)

        try:
            with open(self.fit_config, 'r') as f:
                fit_config_content = f.read()
        except Exception as e:
            logger.error("Read %s failed\n%s" % (self.fit_config, e))
            raise

        for k in self.data['fit-input-files']:
            rep_str = '@%s@' % k
            if not self.fit_inputs[k]:
                continue
            fit_config_content = fit_config_content.replace(rep_str, self.fit_inputs[k])

        fit_config = os.path.join(self.deploydir, os.path.basename(self.fit_config))
        try:
            with open(fit_config, 'w') as f:
                f.write(fit_config_content)
        except Exception as e:
            logger.error("Write %s failed\n%s" % (fit_config, e))
            raise

        cmd = "mkimage -f %s fitimage " % fit_config
        res, output = utils.run_cmd(cmd, shell=True, cwd=self.deploydir)
        if res != 0:
            logger.error(output)
            sys.exit(1)

    @show_task_info("Create Linux rootfs")
    def do_lx_rootfs(self):
        if not self.lx_rootfs_script:
            logger.error("Linux rootfs script %s does not exist", self.lx_rootfs_script)
            sys.exit(1)

        lx_rootfs = self.rootfs_images.get('lx-rootfs', None)
        if not lx_rootfs:
            logger.error("Linux rootfs ext block or tarball does not exist")
            sys.exit(1)

        try:
            with open(self.lx_rootfs_script, 'r') as f:
                script_content = f.read()
        except Exception as e:
            logger.error("Read %s failed\n%s" % (self.lx_rootfs_script, e))
            raise

        for k in self.data['rootfs-images']:
            rep_str = '@%s@' % k
            if not self.rootfs_images.get(k):
                continue
            script_content = script_content.replace(rep_str, self.rootfs_images[k])

        for k in self.data['fit-input-files']:
            rep_str = '@%s@' % k
            if not self.fit_inputs.get(k):
                continue
            script_content = script_content.replace(rep_str, self.fit_inputs[k])

        for k in self.data:
            rep_str = '@%s@' % k
            if not isinstance(self.data[k], str):
                continue
            script_content = script_content.replace(rep_str, self.data[k])

        lx_rootfs_script = os.path.join(self.workdir, os.path.basename(self.lx_rootfs_script))
        try:
            with open(lx_rootfs_script, 'w') as f:
                f.write(script_content)
        except Exception as e:
            logger.error("Write %s failed\n%s" % (lx_rootfs_script, e))
            raise

        os.chmod(lx_rootfs_script, 0o777)

        logger.debug("Executing lx-rootfs-script...")
        env = os.environ.copy()
        env['DEPLOY_DIR_IMAGE'] = self.deploydir
        env['WORKDIR'] = self.workdir
        env['IMAGE_ROOTFS'] = os.path.join(self.workdir, 'rootfs')
        env['IMAGE_NAME'] = self.image_name
        env['MACHINE'] = self.machine
        res, output = utils.run_cmd(lx_rootfs_script, shell=True, env=env)
        if res:
            raise Exception("Executing lx-rootfs-script failed\nExit code %d. Output:\n%s"
                               % (res, output))

    @show_task_info("Create VX works APP")
    def do_vx_app(self):
        if not self.vx_app_script:
            logger.error("VX app script %s does not exist", self.vx_app_script)
            sys.exit(1)

        vx_app = self.rootfs_images.get('vx-app', None)
        if not vx_app:
            utils.mkdirhier(os.path.join(self.workdir, "vxapp"))
            logger.warn("VX APP ext block or tarball does not exist, skip")
            return

        try:
            with open(self.vx_app_script, 'r') as f:
                script_content = f.read()
        except Exception as e:
            logger.error("Read %s failed\n%s" % (self.vx_app_script, e))
            raise

        for k in self.data['rootfs-images']:
            rep_str = '@%s@' % k
            if not self.rootfs_images[k]:
                continue
            script_content = script_content.replace(rep_str, self.rootfs_images[k])

        for k in self.data['fit-input-files']:
            rep_str = '@%s@' % k
            if not self.fit_inputs[k]:
                continue
            script_content = script_content.replace(rep_str, self.fit_inputs[k])

        vx_app_script = os.path.join(self.workdir, os.path.basename(self.vx_app_script))
        try:
            with open(vx_app_script, 'w') as f:
                f.write(script_content)
        except Exception as e:
            logger.error("Write %s failed\n%s" % (vx_app_script, e))
            raise

        os.chmod(vx_app_script, 0o777)

        logger.debug("Executing vx-app-script...")
        env = os.environ.copy()
        env['DEPLOY_DIR_IMAGE'] = self.deploydir
        env['WORKDIR'] = self.workdir
        env['IMAGE_ROOTFS'] = os.path.join(self.workdir, 'vxapp')
        env['IMAGE_NAME'] = self.image_name
        env['MACHINE'] = self.machine
        res, output = utils.run_cmd(vx_app_script, shell=True, env=env)
        if res:
            raise Exception("Executing vx-app-script failed\nExit code %d. Output:\n%s"
                               % (res, output))

    def do_post(self):
        self._save_output_yaml()

    def do_report(self):
        table = Texttable()
        table.set_cols_align(["l", "l"])
        table.set_cols_valign(["t", "t"])

        image_name = "%s-%s" % (self.image_name, self.machine)
        cmd_format = "ls -gh --time-style=+%%Y %s | awk '{$1=$2=$3=$4=$5=\"\"; print $0}'"

        cmd_wic = cmd_format % "{0}.wic".format(image_name)
        output = subprocess.check_output(cmd_wic, shell=True, cwd=self.deploydir)
        table.add_row(["WIC Image", output.strip()])

        cmd_wic = cmd_format % "{0}.wic.README.md".format(image_name)
        output = subprocess.check_output(cmd_wic, shell=True, cwd=self.deploydir)
        table.add_row(["WIC Image Doc", output.strip()])

        logger.info("Deploy Directory: %s\n%s", self.deploydir, table.draw())

    @show_task_info("Create OSTree Repo")
    def do_ostree_repo(self):
        ostree_repo = CreateOstreeRepo(
                        image_name=self.image_name,
                        image_manifest=self.data['rootfs-images'].get('lx-manifest', None),
                        ostree_branchname=self.data['ostree'].get('ostree_branchname', None),
                        workdir=self.workdir,
                        machine=self.machine,
                        target_rootfs=self.target_lxrootfs,
                        deploydir=self.deploydir,
                        gpg_path=self.data['gpg']['gpg_path'],
                        gpgid=self.data['gpg']['ostree']['gpgid'],
                        gpg_password=self.data['gpg']['ostree']['gpg_password'])

        ostree_repo.set_fit(ostree_kernel='fitimage', use_fit='1')
        ostree_repo.create()

    @show_task_info("Create OSTree OTA")
    def do_ostree_ota(self):
        ostree_ota = CreateOstreeOTA(
                        image_name=self.image_name,
                        ostree_branchname=self.data['ostree'].get('ostree_branchname', None),
                        workdir=self.workdir,
                        machine=self.machine,
                        deploydir=self.deploydir,
                        ostree_use_ab=self.data["ostree"]['ostree_use_ab'],
                        ostree_osname=self.data["ostree"]['ostree_osname'],
                        ostree_skip_boot_diff=self.data["ostree"]['ostree_skip_boot_diff'],
                        ostree_remote_url=self.data["ostree"]['ostree_remote_url'],
                        gpgid=self.data["gpg"]['ostree']['gpgid'])

        ostree_ota.set_fit(boot_files=fit_constant.IMAGE_BOOT_FILES, use_fit='1')
        ostree_ota.create()

    @show_task_info("Create Wic Image")
    def do_image_wic(self):
        if self.wic_post_script and os.path.exists(self.wic_post_script):
            os.chmod(self.wic_post_script, 0o777)
        ostree_use_ab = self.data["ostree"].get("ostree_use_ab", '1')
        wks_file = self.wic_config
        logger.debug("WKS %s", wks_file)
        image_wic = CreateWicImage(
                        image_name = self.image_name,
                        workdir = self.workdir,
                        machine = self.machine,
                        pkg_type = 'rpm',
                        target_rootfs = self.target_lxrootfs,
                        deploydir = self.deploydir,
                        post_script = self.wic_post_script,
                        wks_file = wks_file)

        env = {'LAT_WORKDIR': self.workdir}
        image_wic.set_wks_in_environ(**env)

        image_wic.create()

def _main_run_internal(args):
    create = GenFitImage(args)
    create.do_prepare()
    create.do_fetch()
    create.do_patch()
    create.do_fit_kernel()
    create.do_lx_rootfs()
    create.do_vx_app()
    create.do_ostree_repo()
    create.do_ostree_ota()
    create.do_image_wic()
    create.do_post()
    create.do_report()

def _main_run(args):
    if USE_FIT != "1":
        logger.error("Do not support to generate FIT image")
        sys.exit(1)
    try:
        ret = _main_run_internal(args)
    except Exception as e:
            logger.error(e)
            raise

def main_genfitimage():
    parser = set_parser_genfitimage()
    parser.set_defaults(func=_main_run)
    argcomplete.autocomplete(parser)
    args = parser.parse_args()
    set_logger(logger, level=args.loglevel, log_path=args.logdir)
    args.func(args)

def set_subparser_genfitimage(subparsers=None):
    if subparsers is None:
        sys.exit(1)
    parser_genimage = subparsers.add_parser('genfitimage', help='Generate FIT Image from package feeds for specified machines')
    parser_genimage = set_parser_genfitimage(parser_genimage)
    parser_genimage.set_defaults(func=_main_run)

if __name__ == "__main__":
    main()
