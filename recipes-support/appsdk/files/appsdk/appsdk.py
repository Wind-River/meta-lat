#!/usr/bin/env python3
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

import os
import sys
import stat
import shutil
import subprocess
import re
import glob
import logging
import yaml
import tempfile
import atexit

from genimage.utils import set_logger
from genimage.utils import run_cmd
from genimage.constant import DEFAULT_PACKAGE_FEED
from genimage.constant import DEFAULT_REMOTE_PKGDATADIR
from genimage.constant import DEFAULT_IMAGE_PKGTYPE
from genimage.constant import DEFAULT_PACKAGES
from genimage.constant import DEFAULT_MACHINE
from genimage.constant import DEFAULT_IMAGE
from genimage.constant import DEFAULT_IMAGE_FEATURES
from genimage.constant import OSTREE_INITRD_PACKAGES
from genimage.rootfs import Rootfs
import genimage.utils as utils

logger = logging.getLogger('appsdk')

class AppSDK(object):
    """
    AppSDK
    """
    def __init__(self, sdk_output=None, sdkpath=None, deploy_dir=None, sdk_name=None, distro_name="windriver"):
        self.distro_name = distro_name
        if sdk_output != None:
            self.sdk_output = sdk_output
        else:
            # default to "./workdir-sdk"
            self.sdk_output = os.path.join(os.getcwd(), 'workdir-sdk')
        if sdkpath != None:
            self.sdkpath = sdkpath
        else:
            # default to /opt/DISTRO_NAME/appsdk
            self.sdkpath = os.path.join("/opt", self.distro_name, "appsdk")
        logger.debug("sdk_output = {0}, sdkpath={1}".format(self.sdk_output, self.sdkpath))

        if deploy_dir != None:
            self.deploy_dir = deploy_dir
        else:
            # default to "./deploy"
            self.deploy_dir = os.path.join(os.getcwd(), 'deploy')

        if sdk_name != None:
            self.sdk_name = sdk_name
        else:
            # default to "AppSDK"
            self.sdk_name = "AppSDK"

        self.real_multimach_target_sys = utils.get_yocto_var('MULTIMACH_TARGET_SYS')
        # current native sysroot dir
        self.native_sysroot = os.environ['OECORE_NATIVE_SYSROOT']
        # current pkgdata dir
        self.pkgdata = os.path.abspath(os.path.join(self.native_sysroot, "../pkgdata"))
        self.data_dir = os.path.join(self.native_sysroot, "usr/share/genimage/data")
        self.sdk_sys = os.path.basename(self.native_sysroot)
        self.target_sdk_dir = os.path.dirname(os.path.dirname(self.native_sysroot))
        # new sdk's sysroot dirs
        self.native_sysroot_dir = os.path.abspath(self.sdk_output + '/' + self.sdkpath + '/sysroots/' + self.sdk_sys)
        # new sdk's pkgdata dirs
        self.pkgdata_dir = os.path.abspath(self.sdk_output + '/' + self.sdkpath + '/sysroots/pkgdata')

    def generate_sdk(self, target_image_yaml, output_sdk_path = None):
        """
        Generate sdk according to target_image_yaml.
        If output_sdk_path is not specified, use the default one.
        """
        # Check if target_image_yaml exists
        if not os.path.exists(target_image_yaml):
            logger.error("{0} does not exists!".format(target_image_yaml))
            sys.exit(1)
        # Compute self.deploy_dir and self.sdk_name
        if output_sdk_path:
            self.deploy_dir = os.path.dirname(os.path.abspath(output_sdk_path))
            self.sdk_name = os.path.basename(output_sdk_path).split('.sh')[0]
        self.populate_native_sysroot()
        self.populate_pkgdata()
        self.populate_target_sysroot(target_image_yaml)
        self.create_sdk_files()
        self.archive_sdk()
        self.create_shar()
        logger.info("New SDK successfully generated: {0}/{1}.sh".format(self.deploy_dir, self.sdk_name))

    def check_sdk(self):
        """
        Sanity check of SDK
        """
        logger.info("Doing sanity check for SDK")
        # Check if relocation is correct in binaries
        ld_path = os.path.join(self.native_sysroot, 'lib/ld-linux-x86-64.so.2')
        if not os.path.exists(ld_path):
            logger.error("SDK Sanity Error: {0} does not exists!".format(ld_path))
            sys.exit(1)
        bin_globs = "{0}/bin/* {0}/usr/bin/*".format(self.native_sysroot).split()
        known_lists = "{0}/bin/gunzip.gzip {0}/bin/zcat.gzip".format(self.native_sysroot).split()
        binary_file_to_check = None
        for bg in bin_globs:
            for f in glob.glob(bg):
                if not os.path.islink(f) and not os.path.isdir(f) and not f in known_lists:
                    binary_file_to_check = f
                    break
            if binary_file_to_check:
                break
        if not binary_file_to_check:
            logger.error("SDK Sanity Error: {0} does not contain any binaries under /bin and /usr/bin".format(self.native_sysroot))
            sys.exit(1)
        logger.debug("{0} --list {1}".format(ld_path, binary_file_to_check))
        ld_list_cmd = "{0} --list {1}".format(ld_path, binary_file_to_check)
        output = subprocess.check_output(ld_list_cmd, shell=True).decode('utf-8')
        expected_line = "libc.so.6 => {0}/lib/libc.so.6".format(self.native_sysroot)
        if expected_line not in output:
            logger.error("SDK Sanity Error: {0} has relocation problem.".format(binary_file_to_check))
            sys.exit(1)
            
        logger.info("SDK Sanity OK")

    def populate_target_sysroot(self, target_packages_yaml):
        """
        Populate target sysroot sdk_output/sdkpath/sysroots/corei7-64-wrs-linux/
        according to target_packages_yaml
        """
        target_sysroot_dir = os.path.abspath(self.sdk_output + '/' + self.sdkpath + '/sysroots/' + self.real_multimach_target_sys)
        logger.info("Constructing target sysroot '%s'" % target_sysroot_dir)
        if os.path.exists(target_sysroot_dir):
            shutil.rmtree(target_sysroot_dir)
        os.makedirs(target_sysroot_dir)

        # parse yaml file to get the list of packages to be installed
        with open(target_packages_yaml) as f:
            data = yaml.load(f, Loader=yaml.FullLoader)
            if not data:
                logger.warning("Empty input file: %s, using the default settings" % target_packages_yaml)
                data = {}
            self.image_name = data['name'] if 'name' in data else DEFAULT_IMAGE
            self.machine = data['machine'] if 'machine' in data else DEFAULT_MACHINE
            self.packages = DEFAULT_PACKAGES[self.machine]
            if 'packages' in data:
                self.packages += data['packages']
            if 'external-packages' in data:
                self.external_packages = data['external-packages']
            else:
                self.external_packages = []

            self.pkg_feeds = data['package_feeds'] if 'package_feeds' in data else DEFAULT_PACKAGE_FEED[DEFAULT_IMAGE_PKGTYPE]
            self.remote_pkgdatadir = data['remote_pkgdatadir'] if 'remote_pkgdatadir' in data else DEFAULT_REMOTE_PKGDATADIR[DEFAULT_IMAGE_PKGTYPE]
            self.image_features = data['features'] if 'features' in data else DEFAULT_IMAGE_FEATURES

        # qemuwrapper-cross is always needed
        self.packages.append('qemuwrapper-cross')

        # dump default values and show user
        if not data:
            with tempfile.NamedTemporaryFile(prefix='appsdk-gensdk-default-', suffix='.yaml', delete=False, mode='w') as tf:
                yaml.dump({'name': self.image_name,
                           'machine': self.machine,
                           'package_feeds': self.pkg_feeds,
                           'remote_pkgdatadir': self.remote_pkgdatadir,
                           'features': self.image_features,
                           'packages': self.packages,
                           'external-packages': self.external_packages}, tf)
                logger.warning("Please check %s for default settings." % tf.name)
        else:
            with tempfile.NamedTemporaryFile(prefix='appsdk-gensdk-', suffix='.yaml', delete=False, mode='w') as tf:
                yaml.dump({'name': self.image_name,
                           'machine': self.machine,
                           'package_feeds': self.pkg_feeds,
                           'remote_pkgdatadir': self.remote_pkgdatadir,
                           'features': self.image_features,
                           'packages': self.packages,
                           'external-packages': self.external_packages}, tf)
                logger.info("Please check %s for effective settings." % tf.name)
        
        # prepare pseudo environment
        utils.fake_root()
        
        # install packages into target sysroot dir
        rootfs = Rootfs(self.sdk_output,
                        self.data_dir,
                        self.machine,
                        self.pkg_feeds,
                        self.packages,
                        external_packages=self.external_packages,
                        remote_pkgdatadir=self.remote_pkgdatadir,
                        target_rootfs=target_sysroot_dir,
                        pkg_globs="*-src *-dev *-dbg")

        rootfs.create()

        # Turn absolute links into relative ones
        sysroot_relativelinks_py = os.path.join(self.native_sysroot, 'usr/share/poky/scripts/sysroot-relativelinks.py')
        cmd = "%s %s >/dev/null" % (sysroot_relativelinks_py, target_sysroot_dir)
        logger.info("Running %s ..." % cmd)
        subprocess.check_call(cmd, shell=True)
        logger.info("Finished populating target sysroot")

    def populate_pkgdata(self):
        """
        Populate pkgdata.
        """
        logger.info("Constructing pkgdata '%s'" % self.pkgdata_dir)
        if os.path.exists(self.pkgdata_dir):
            shutil.rmtree(self.pkgdata_dir)

        # copy the whole native sysroot
        shutil.copytree(self.pkgdata, self.pkgdata_dir, symlinks=True, ignore_dangling_symlinks=True)

    def populate_native_sysroot(self):
        """
        Populate native sysroot.
        It's basically a copy of OECORE_NATIVE_SYSROOT, with relocations performed.
        """
        
        logger.info("Constructing native sysroot '%s'" % self.native_sysroot_dir)
        if os.path.exists(self.native_sysroot_dir):
            shutil.rmtree(self.native_sysroot_dir)

        # copy the whole native sysroot
        shutil.copytree(self.native_sysroot, self.native_sysroot_dir, symlinks=True, ignore_dangling_symlinks=True)

        # do relocation, self.target_sdk_dir -> self.sdkpath
        # self.target_sdk_dir is the old prefix, self.sdkpath is the newprefix
        relocate_tmpl_path = os.path.join(self.native_sysroot, 'usr/share/poky/scripts/relocate_sdk.py')
        if not os.path.exists(relocate_tmpl_path):
            logger.error("%s does not exist!" % relocate_tmpl_path)
            raise
        relocate_script_path = os.path.join(self.sdk_output, 'relocate_sdk.py')
        shutil.copyfile(relocate_tmpl_path, relocate_script_path)
        cmd = "sed -i -e 's:##DEFAULT_INSTALL_DIR##:{0}:' {1}".format(self.target_sdk_dir, relocate_script_path)
        subprocess.check_call(cmd, shell=True)
        # create relocate_sdk.sh to do the job to avoid arugment list too long error
        relocate_sh_path = os.path.join(self.sdk_output, 'relocate_sdk.sh')
        cmds = ["#!/bin/bash\n"]
        cmds.append("new_prefix={0}\n".format(self.sdkpath))
        cmds.append("new_dl_path={0}/sysroots/{1}/lib/ld-linux-x86-64.so.2\n".format(self.sdkpath, self.sdk_sys))
        cmds.append('executable_files=$(find {0} -type f \( -perm -0100 -o -perm -0010 -o -perm -0001 \) -printf "%h/%f ")\n'.format(self.native_sysroot_dir))
        cmds.append("python3 {0} $new_prefix $new_dl_path $executable_files\n".format(relocate_script_path))
        with open(relocate_sh_path, 'w') as f:
            f.writelines(cmds)
        os.chmod(relocate_sh_path, 0o755)
        subprocess.check_call('%s' % relocate_sh_path, shell=True)

        # remove the relocation script
        os.unlink(relocate_script_path)
        os.unlink(relocate_sh_path)

        # change symlinks point to $target_sdk_dir to point to $SDKPATH
        self._change_symlinks(self.native_sysroot_dir, self.target_sdk_dir, self.sdkpath)

        # change all text files from $target_sdk_dir to $SDKPATH
        logger.debug("Replacing text files from {0} to {1}".format(self.target_sdk_dir, self.sdkpath))
        self.replace_text_files(self.native_sysroot_dir, self.target_sdk_dir, self.sdkpath)
        
        logger.info("Finished populating native sysroot")

    def replace_text_files(self, rootdir, oldprefix, newprefix, extra_args=""):
        replace_sh_path = self._construct_replace_sh(rootdir, oldprefix, newprefix, extra_args)
        subprocess.check_call('%s' % replace_sh_path, shell=True)

    def _construct_replace_sh(self, rootdir, oldprefix, newprefix, extra_args):
        cmds = """
#!/bin/bash

find {0} {1} -type f | xargs -n100 file | grep ":.*\(ASCII\|script\|source\).*text" | \
    awk -F':' '{left}printf "\\"{4}\\"{newline}", $1{right}' | \
    xargs -n100 sed -i \
        -e "s:{2}:{3}:g"
""".format(rootdir, extra_args, oldprefix, newprefix, '%s', left = '{', right = '}', newline = '\\n')

        replace_sh_path = os.path.join(self.sdk_output, 'replace.sh')
        with open(replace_sh_path, 'w') as f:
            f.write(cmds)
        os.chmod(replace_sh_path, 0o755)
        return replace_sh_path
        
    def _change_symlinks(self, rootdir, old, new):
        """
        Change symlinks under rootdir, replacing the old with new
        """
        for dirPath,subDirEntries,fileEntries in os.walk(rootdir, followlinks=False):
            for e in fileEntries:
                ep = os.path.join(dirPath, e)
                if not os.path.islink(ep):
                    continue
                target_path = os.readlink(ep)
                if not os.path.isabs(target_path):
                    continue
                # ep is a symlink and its target path is abs path
                if old in target_path:
                    new_target_path = target_path.replace(old, new)
                    #logger.debug("%s -> %s" % (ep, new_target_path))
                    os.unlink(ep)
                    os.symlink(new_target_path, ep)

    def create_sdk_files(self):
        """
        Create SDK files.
        Mostly it's a copy of the current SDK, with path modifications.
        """
        logger.info("Creating sdk files")
        # copy site-config-*, version-*, environment-setup-*
        # from self.target_sdk_dir to self.sdk_output/self.sdkpath
        file_globs = "{0}/site-config-* {0}/version-* {0}/environment-setup-*".format(self.target_sdk_dir).split()
        for fg in file_globs:
            for file_path in glob.glob(fg):
                file_basename = os.path.basename(file_path)
                file_dst = self.sdk_output + self.sdkpath + '/' + file_basename
                shutil.copyfile(file_path, file_dst)

        # replace paths in environment-setup-*
        # self.target_sdk_dir -> self.sdkpath
        self.replace_text_files(self.sdk_output + self.sdkpath, self.target_sdk_dir, self.sdkpath, extra_args = "-maxdepth 1")

        # create relocate_sdk.py under sdk_output/sdkpath
        relocate_sdk_tmpl = os.path.join(self.native_sysroot, "usr/share/poky/scripts/relocate_sdk.py")
        relocate_sdk_dst = self.sdk_output + self.sdkpath + '/relocate_sdk.py'
        shutil.copyfile(relocate_sdk_tmpl, relocate_sdk_dst)
        cmd = 'sed -i -e "s:##DEFAULT_INSTALL_DIR##:{0}:" {1}'.format(self.sdkpath, relocate_sdk_dst)
        subprocess.check_call(cmd, shell=True)

        # we don't need to create ld.so.conf as the contents are correct already. This is because we copy the original ld.so.conf and replace the paths in it in populate_native_sysroot()
        logger.info("Finished creating sdk files")

    def archive_sdk(self):
        """
        Archive sdk
        """
        if not os.path.exists(self.deploy_dir):
            os.makedirs(self.deploy_dir)
        logger.info("Archiving sdk from {0}{1} to {2}/{3}.tar.gz".format(self.sdk_output, self.sdkpath, self.deploy_dir, self.sdk_name))
        sdk_archive_cmd = 'cd {0}/{1}; tar --owner=root --group=root -cf - . | xz --memlimit=50% --threads=40 -9 > {2}/{3}.tar.gz'.format(self.sdk_output, self.sdkpath, self.deploy_dir, self.sdk_name)
        subprocess.check_call(sdk_archive_cmd, shell=True)
        logger.info("Finished archiving sdk to {0}/{1}.tar.gz".format(self.deploy_dir, self.sdk_name))

    def _get_sdk_var_dict(self):
        var_dict = {}
        var_dict['SDK_ARCH'] = 'x86_64'
        var_dict['SDKPATH'] = self.sdkpath
        var_dict['SDKEXTPATH'] = '~/lat_appsdk'
        var_dict['OLDEST_KERNEL'] = '3.2.0'
        var_dict['REAL_MULTIMACH_TARGET_SYS'] = self.real_multimach_target_sys
        var_dict['SDK_TITLE'] = 'Wind River AppSDK'
        var_dict['SDK_VERSION'] = ''
        var_dict['SDK_GCC_VER'] = ''
        var_dict['SDK_ARCHIVE_TYPE'] = 'tar.gz'
        
        return var_dict
        
    def create_shar(self):
        """
        Create sh installer for SDK
        It's the installation script + sdk archive
        """
        # copy the template shar extractor script to AppSDK.sh
        shar_extract_tmpl = os.path.join(self.native_sysroot, 'usr/share/poky/meta/files/toolchain-shar-extract.sh')
        if not os.path.exists(shar_extract_tmpl):
            logger.error("{0} does not exist".format(shar_extract_tmpl))
            raise
        shar_extract_sh = self.deploy_dir + '/' + self.sdk_name + '.sh'
        shutil.copyfile(shar_extract_tmpl, shar_extract_sh)

        # copy relocation script to post_install_command
        shar_relocate_tmpl = os.path.join(self.native_sysroot, 'usr/share/poky/meta/files/toolchain-shar-relocate.sh')
        if not os.path.exists(shar_relocate_tmpl):
            logger.error("{0} does not exist".format(shar_extract_tmpl))
            raise
        post_install_command_path = self.sdk_output + '/post_install_command'
        shutil.copyfile(shar_relocate_tmpl, post_install_command_path)

        # create pre_install_command as a placeholder
        pre_install_command_path = self.sdk_output + '/pre_install_command'
        with open(pre_install_command_path, 'w') as f:
            pass

        # substitute SDK_PRE/POST_INSTALL_COMMAND
        sed_cmd = "sed -i -e '/@SDK_PRE_INSTALL_COMMAND@/r {0}' -e '/@SDK_POST_INSTALL_COMMAND@/r {1}' {2}".format(
            pre_install_command_path, post_install_command_path, shar_extract_sh)
        subprocess.check_call(sed_cmd, shell=True)

        # substitute VARS like SDK_ARCH
        var_dict = self._get_sdk_var_dict()
        sed_cmd = """
        sed -i -e 's#@SDK_ARCH@#{SDK_ARCH}#g' \
                -e 's#@SDKPATH@#{SDKPATH}#g' \
                -e 's#@SDKEXTPATH@#{SDKEXTPATH}#g' \
                -e 's#@OLDEST_KERNEL@#{OLDEST_KERNEL}#g' \
                -e 's#@REAL_MULTIMACH_TARGET_SYS@#{REAL_MULTIMACH_TARGET_SYS}#g' \
                -e 's#@SDK_TITLE@#{SDK_TITLE}#g' \
                -e 's#@SDK_VERSION@#{SDK_VERSION}#g' \
                -e '/@SDK_PRE_INSTALL_COMMAND@/d' \
                -e '/@SDK_POST_INSTALL_COMMAND@/d' \
                -e 's#@SDK_GCC_VER@#{SDK_GCC_VER}#g' \
                -e 's#@SDK_ARCHIVE_TYPE@#{SDK_ARCHIVE_TYPE}#g' \
                {shar_extract_sh}
        """.format(
            SDK_ARCH = var_dict['SDK_ARCH'],
            SDKPATH = var_dict['SDKPATH'],
            SDKEXTPATH = var_dict['SDKEXTPATH'],
            OLDEST_KERNEL = var_dict['OLDEST_KERNEL'],
            REAL_MULTIMACH_TARGET_SYS = var_dict['REAL_MULTIMACH_TARGET_SYS'],
            SDK_TITLE = var_dict['SDK_TITLE'],
            SDK_VERSION = var_dict['SDK_VERSION'],
            SDK_GCC_VER = var_dict['SDK_GCC_VER'],
            SDK_ARCHIVE_TYPE = var_dict['SDK_ARCHIVE_TYPE'],
            shar_extract_sh = shar_extract_sh)
        subprocess.check_call(sed_cmd, shell=True)

        # chmod 755
        os.chmod(shar_extract_sh, 0o755)

        # append sdk archive
        sdk_archive_path = self.deploy_dir + '/' + self.sdk_name + '.tar.gz'
        with open(sdk_archive_path, 'rb') as rf:
            with open(shar_extract_sh, 'ab') as wf:
                shutil.copyfileobj(rf, wf)

        # delete the old archive
        os.unlink(sdk_archive_path)

        logger.info("Finished creating shar {0}".format(shar_extract_sh))
        
    def check_sdk_target_sysroots(self):
        """
        Check if there are broken or dangling symlinks in SDK sysroots
        """
        def norm_path(path):
            return os.path.abspath(path)

        # Get scan root
        SCAN_ROOT = norm_path("%s/%s/sysroots/%s" % (self.sdk_output, self.sdkpath, self.real_multimach_target_sys))
        logger.info('Checking SDK sysroots at ' + SCAN_ROOT)

        def check_symlink(linkPath):
            if not os.path.islink(linkPath):
                return

            # whitelist path patterns that are known to have problem
            whitelist_patterns = ["/etc/mtab",
                                  "/var/lock",
                                  "/etc/resolv-conf.systemd",
                                  "/etc/resolv.conf",
                                  "/etc/udev/rules.d/80-net-setup-link.rules",
                                  "/etc/tmpfiles.d/.*.conf",
                                  "/etc/systemd/network/80-wired.network",
                                  ".*\.patch",
                                  "/etc/ld.so.cache"]
            for wp in whitelist_patterns:
                if re.search(wp, linkPath):
                    return
            
            # Compute the target path of the symlink
            linkDirPath = os.path.dirname(linkPath)
            targetPath = os.readlink(linkPath)
            if not os.path.isabs(targetPath):
                targetPath = os.path.join(linkDirPath, targetPath)
            targetPath = norm_path(targetPath)

            if SCAN_ROOT != os.path.commonprefix( [SCAN_ROOT, targetPath] ):
                logger.warning("Escaping symlink {0!s} --> {1!s}".format(linkPath, targetPath))
                return

            if not os.path.exists(targetPath):
                logger.warning("Broken symlink {0!s} --> {1!s}".format(linkPath, targetPath))
                return

            #if os.path.isdir(targetPath):
            #    dir_walk(targetPath)

        def walk_error_handler(e):
            logger.error(str(e))

        def dir_walk(rootDir):
            for dirPath,subDirEntries,fileEntries in os.walk(rootDir, followlinks=False, onerror=walk_error_handler):
                entries = subDirEntries + fileEntries
                for e in entries:
                    ePath = os.path.join(dirPath, e)
                    check_symlink(ePath)

        # start
        dir_walk(SCAN_ROOT)

    def construct_buildroot(self, installdir, buildroot):
        """
        Construct buildroot from installdir.
        """
        if not os.path.exists(installdir):
            logger.error("%s does not exists!" % installdir)
            sys.exit(1)

        # Copy the whole installdir to buildroot
        if os.path.exists(buildroot):
            shutil.rmtree(buildroot)
        shutil.copytree(installdir, buildroot, symlinks=True, ignore_dangling_symlinks=True)

        # Do any adjustment needed, e.g. /usr merge changes and symlink changes
        
    def construct_spec_file(self, pkg_yaml, buildroot, specfile):
        """
        Construct RPM spec file according to pkg_yaml and buildroot contents
        pkg_yaml: yaml file to specify package details
        installdir: installation directory, which is usually the result of 'make install'
        specfile: specfile path
        """
        logger.info("Constructing spec file from {0} and {1}".format(pkg_yaml, buildroot))
        
        # Parse pkg_yaml file to get package information
        pc = PackageConfig(pkg_yaml)

        # Walk through buildroot and construct files/dirs information for the package
        pc.parse_buildroot(buildroot)

        # write spec file according to package config information
        self.write_spec_file(specfile, pc)

        logger.info("Finished constructing spec file: %s" % specfile)

    def write_spec_file(self, specfile, pc):
        """
        Write spec file according to package config information
        specfile: path to .spec file
        pc: PackageConfig object containing package information
        """
        pc.show(specfile)

    def buildrpm(self, configfile, installdir, pkgarch=None, rpmdir=None, workdir=None):
        """
        Build out rpm package from installdir according to configfile.
        If configfile is a spec file, use it directly. If the config file a yaml file, construct spec file and use it.
        The generated rpm is put in rpmdir (default to $target_sdk_dir/deploy/rpms)
        """
        def exit_and_cleanup_pseudo(pseudodir):
            logger.debug("Exit pseudo and remove %s" % pseudodir)
            utils.exit_fake_root()
            cmd = "rm -rf %s" % pseudodir
            utils.run_cmd_oneshot(cmd)

        if not workdir:
            workdir = os.path.join(self.target_sdk_dir, 'workdir-packaging')
        if not os.path.exists(workdir):
            os.makedirs(workdir)

        utils.fake_root(workdir=workdir)
        atexit.register(exit_and_cleanup_pseudo, os.path.join(workdir, 'pseudo'))
        logger.info("Building rpm from {0} according to {1} ...".format(installdir, configfile))

        # sanity checks
        if not configfile.endswith('.spec') and not configfile.endswith('.yaml') and not configfile.endswith('.yml'):
            logger.error("%s should be a spec file or yaml file" % configfile)
            sys.exit(1)
        
        # get package arch
        if not pkgarch:
            pkgarch = self.real_multimach_target_sys.split('-wrs-')[0]
            logger.info("Guess pkgarch to be {0} from {1}".format(pkgarch, self.real_multimach_target_sys))

        # prepare dirs
        if not rpmdir:
            rpmdir = os.path.join(self.target_sdk_dir, 'deploy/rpms')
        rpmdir = os.path.abspath(rpmdir)
        logger.debug("rpmdir = %s" % rpmdir)
        if not os.path.exists(rpmdir):
            os.makedirs(rpmdir)
        conf_base_name = os.path.basename(configfile).split('.')[0]
        topdir = os.path.join(workdir, conf_base_name)
        logger.debug("topdir = %s" % topdir)
        if not os.path.exists(topdir):
            os.makedirs(topdir)
        
        # Construct buildroot from installdir
        # installdir -> workdir-packaging/configfile_base_name/buildroot
        buildroot = os.path.join(topdir, 'buildroot')
        logger.debug("buildroot = %s" % buildroot)
        self.construct_buildroot(installdir, buildroot)

        # prepare spec file
        if configfile.endswith('.spec'):
            specfile = configfile
        else:
            specfile = os.path.join(topdir, conf_base_name + '.spec')
            self.construct_spec_file(configfile, buildroot, specfile)
        
        # construct rpmbuild command
        cmd = 'rpmbuild'
        cmd = cmd + " --noclean"
        cmd = cmd + " --target " + pkgarch.replace('-', '_')
        cmd = cmd + " --buildroot " + buildroot
        cmd = cmd + " --dbpath " + os.path.join(self.native_sysroot, 'var/lib/rpm')
        cmd = cmd + " --define '_topdir %s'" % topdir
        cmd = cmd + " --define '_rpmdir %s'" % rpmdir
        cmd = cmd + " --define '_build_id_links none'"
        cmd = cmd + " --define '_buildhost windriver-appsdk'"
        cmd = cmd + " --define '_unpackaged_files_terminate_build 0'"
        cmd = cmd + " --define '_tmppath %s'" % topdir
        cmd = cmd + " -bb %s" % specfile
        # run rpmbuild command
        logger.debug(cmd)
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode('utf-8')

        # control the output according to log level
        out_lines = output.split('\n')
        for ol in out_lines:
            logger.debug('%s' % ol)
            if ol.startswith('Wrote: '):
                generated_rpm_path = ol.split('Wrote: ')[1]

        # clean things up
        for entry in ["BUILDROOT", "SRPMS", "BUILD"]:
            shutil.rmtree("%s/%s" % (topdir, entry))
        
        logger.info("Generated %s" % generated_rpm_path)

    def create_index(self, arg):
        index_cmd = arg
        logger.debug("Executing '%s' ..." % index_cmd)
        result = subprocess.check_output(index_cmd, stderr=subprocess.STDOUT, shell=True).decode("utf-8")
        if result:
            logger.debug(result)
        
    def createrepo(self, repo_dir):
        """
        create rpm repo via createrepo_c on repo_dir
        """
        logger.info("Creating rpm repo for %s" % repo_dir)
        self.create_index("createrepo_c --update -q %s" % repo_dir)
        logger.info("Created rpm repo for %s" % repo_dir)

    def _get_rpm_arch(self, rpm):
        cmd = 'rpm -qp --qf "%{left}arch{right}" {0}'.format(rpm, left='{', right='}')
        rpm_arch = subprocess.check_output(cmd, shell=True).decode("utf-8")
        logger.debug("Arch for %s is %s" % (rpm, rpm_arch))
        return rpm_arch
        
    def _copy_rpm_to_repo(self, rpm, repo):
        """
        Copy one RPM to repo
        """
        # path verification
        if not os.path.exists(rpm):
            logger.error("%s does not exist" % rpm)
            sys.exit(1)
        if not rpm.endswith('.rpm'):
            logger.error("%s is not RPM package" % rpm)
            sys.exit(1)

        # normalize paths
        rpm = os.path.abspath(rpm)
        repo = os.path.abspath(repo)
            
        # rpm already under repo, do nothing
        if rpm.startswith(repo):
            logger.info("%s is already under %s" % (rpm, repo))
            return
            
        # get rpm arch
        rpm_arch = self._get_rpm_arch(rpm)

        # determine rpm dest dir
        if repo.endswith(rpm_arch):
            rpm_dest_dir = repo
        else:
            rpm_dest_dir = os.path.join(repo, rpm_arch)
        if not os.path.exists(rpm_dest_dir):
            os.makedirs(rpm_dest_dir)

        # copy the rpm
        shutil.copy(rpm, rpm_dest_dir)
        
    def copy_rpms_to_repo(self, rpms, repo):
        """
        Copy rpms to repo.
        If repo ends with <arch>, copy rpms directly there.
        Otherwise, create repo/<arch> first, and then copy rpms to repo/<arch>
        """
        for rpm in rpms:
            self._copy_rpm_to_repo(rpm, repo)
        
    def publishrpm(self, repo, rpms):
        """
        Publish rpms to repo.
        repo: rpm repo directory
        rpms: list of RPM package paths
        """
        logger.debug("repo = %s, rpms = %s" % (repo, rpms))
        # repo path validation
        if repo.startswith('http:') or repo.startswith('https:'):
            logger.error("Invalid repo path: %s. Please use a local path" % repo)
            sys.exit(1)
        logger.info("Publish RPM repo: %s" % repo)
        #
        # Copy rpms to repo
        #
        if len(rpms):
            self.copy_rpms_to_repo(rpms, repo)
        # Pubish the repo
        self.createrepo(repo)
        logger.info("Finished publishing rpms to repo %s" % repo)
        
        
class PackageConfig(object):
    """
    PackageConfig class to hold information for package settings
    """
    def __init__(self, pkg_yaml):
        if not os.path.exists(pkg_yaml):
            logger.error("%s does not exist!" % pkg_yaml)
            sys.exit(1)

        self.pkg_data = {}
        with open(pkg_yaml) as f:
            yd = yaml.load(f, Loader=yaml.FullLoader)

        #
        # sanity check for yaml file
        #
        # name, version, release, summary, license must be present.
        if not yd:
            logger.error("%s must not be empty" % pkg_yaml)
            sys.exit(1)
        for entry_must in ['name', 'version', 'release', 'summary', 'license']:
            if entry_must not in yd:
                logger.error("'%s' must be specified in %s" % (entry_must, pkg_yaml))
                sys.exit(1)
        
        self.pkg_data['Name'] = yd['name']
        self.pkg_data['Version'] = yd['version']
        self.pkg_data['Release'] = yd['release']
        self.pkg_data['Summary'] = yd['summary']
        self.pkg_data['License'] = yd['license']
        self.pkg_data['description'] = yd['description'] if 'description' in yd else yd['summary']

        # scripts
        map_yd_spec = {}
        map_yd_spec['post_install'] = 'post'
        map_yd_spec['pre_install'] = 'pre'
        map_yd_spec['post_uninstall'] = 'postun'
        map_yd_spec['pre_uninstall'] = 'preun'
        for yd_entry in map_yd_spec:
            spec_entry = map_yd_spec[yd_entry]
            path_yd_entry = yd_entry + '_path'
            if yd_entry in yd and path_yd_entry in yd:
                logger.error("%s and %s both specified. Only one is allowed." % (yd_entry, path_yd_entry))
                sys.exit(1)
            if yd_entry in yd:
                logger.debug("add %{0} section from {1} in {2}".format(spec_entry, yd_entry, pkg_yaml))
                self.pkg_data[spec_entry] = yd[yd_entry]
            if path_yd_entry in yd:
                logger.debug("add %{0} section from {1} in {2}".format(spec_entry, path_yd_entry, pkg_yaml))
                script_path = yd[path_yd_entry]
                with open(script_path, 'r') as sf:
                    self.pkg_data[spec_entry] = sf.read()

        # files and dirs
        if 'dirs' in yd:
            self.pkg_data['dirs'] = yd['dirs']
        else:
            self.pkg_data['dirs'] = []
        if 'files' in yd:
            self.pkg_data['files'] = yd['files']
        else:
            self.pkg_data['files'] = ['/*']

    def show(self, outfile=None):
        """
        Output package settings in spec file format
        """
        if not outfile:
            out = sys.stdout
        else:
            out = open(outfile, 'w')

        # write lines to out
        for entry in ['Name', 'Version', 'Release', 'Summary', 'License']:
            out.write('{0}: {1}\n'.format(entry, self.pkg_data[entry]))
        out.write('\n')
        for entry in ['description', 'post', 'pre', 'postun', 'preun']:
            if entry in self.pkg_data:
                out.write('%{0}\n'.format(entry))
                out.write('{0}\n'.format(self.pkg_data[entry]))
        out.write('%files\n')
        if 'dirs' in self.pkg_data:
            for dir_entry in self.pkg_data['dirs']:
                if '(' in dir_entry:
                    dirpath, dirattr = dir_entry.split(maxsplit=1)
                    out.write('%attr{0} %dir {1}\n'.format(dirattr, dirpath))
                else:
                    dirpath = dir_entry
                    out.write('%dir {0}\n'.format(dirpath))
        for file_entry in self.pkg_data['files']:
            if '(' in file_entry:
                filepath, fileattr = file_entry.split(maxsplit=1)
                out.write('%attr{0} {1}\n'.format(fileattr, filepath))
            else:
                filepath = file_entry
                out.write('{0}\n'.format(filepath))                

        if outfile:
            out.close()

    def parse_buildroot(self, buildroot):
        """
        Parse buildroot to get needed files/dirs information
        """
        default_layout = {}
        dirs_0755_root_root = ['/',
                               '/usr',
                               '/usr/bin',
                               '/usr/sbin',
                               '/usr/local',
                               '/usr/local/bin',
                               '/usr/local/sbin',
                               '/usr/lib',
                               '/usr/lib64',
                               '/usr/lib32',
                               '/usr/libexec',
                               '/usr/share',
                               '/usr/share/doc',
                               '/usr/share/man',
                               '/usr/include',
                               '/etc',
                               '/var']
        for dir in dirs_0755_root_root:
            default_layout[dir] = '(0755, root, root)'

        full_files_list = []
        for fp in self.pkg_data['files']:
            gfp = fp.replace('*', '**')
            gfp = buildroot + gfp
            full_files_list.extend(glob.glob(gfp, recursive=True))
            
        # get dirs specified in yaml
        yaml_dirs = []
        for dir_entry in self.pkg_data['dirs']:
            dirpath = dir_entry.split(maxsplit=1)[0]
            yaml_dirs.append(dirpath)
            
        for root, dirs, files in os.walk(buildroot):
            for d in dirs:
                dirpath = os.path.join(root, d)
                # check if dirpath should be dealt according to 'files' setting
                if not self.is_dirpath_valid(dirpath, full_files_list):
                    continue
                dirpath = dirpath.replace(buildroot, '')
                if dirpath in yaml_dirs:
                    logger.debug("%s is already specified by user in yaml file" % dirpath)
                else:
                    if dirpath in default_layout:
                        logger.debug("adding %s as %s" % (dirpath, default_layout[dirpath]))
                        self.pkg_data['dirs'].append('%s %s' % (dirpath, default_layout[dirpath]))

    def is_dirpath_valid(self, dirpath, full_files_list):
        for f in full_files_list:
            if f.startswith(dirpath):
                return True
        return False
                
    
def test_appsdk():
    set_logger(logger)
    logger.setLevel(logging.DEBUG)
    logger.info("testing appsdk.py ...")
    appsdk = AppSDK()
    if len(sys.argv) < 3:
        logger.error("appsdk.py specfile installdir [pkgarch]")
        sys.exit(1)
    specfile = os.path.abspath(sys.argv[1])
    installdir = os.path.abspath(sys.argv[2])
    if len(sys.argv) == 4:
        pkgarch = sys.argv[3]
    else:
        pkgarch = None
    # prepare fakeroot env
    utils.fake_root()
    appsdk.buildrpm(specfile, installdir, pkgarch = pkgarch)
    logger.info("Done")

def test_packageconfig():
    set_logger(logger)
    logger.setLevel(logging.DEBUG)
    logger.info("testing appsdk.py ...")
    if len(sys.argv) < 2:
        logger.error("appsdk.py yamlfile")
        sys.exit(1)
    yaml_file = sys.argv[1]
    pc = PackageConfig(yaml_file)
    if len(sys.argv) == 3:
        spec_file = sys.argv[2]
        pc.show(spec_file)
    else:
        pc.show()
    logger.info("Done")
    
if __name__ == "__main__":
    test_appsdk()
    #test_packageconfig()
