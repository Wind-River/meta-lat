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
import os.path
import subprocess
from collections import OrderedDict
import logging
from tempfile import NamedTemporaryFile

from genimage.package_manager import get_pm_class
from genimage.constant import DEFAULT_IMAGE_PKGTYPE
import genimage.utils as utils
from genimage.utils import yaml

logger = logging.getLogger('appsdk')

class Rootfs(object):
    def __init__(self,
                 workdir,
                 data_dir,
                 machine,
                 pkg_feeds,
                 packages,
                 external_packages=[],
                 exclude_packages=[],
                 remote_pkgdatadir=None,
                 target_rootfs=None,
                 image_linguas=None,
                 pkgtype=DEFAULT_IMAGE_PKGTYPE,
                 pkg_globs=None):

        self.workdir = workdir
        self.data_dir = data_dir
        self.machine = machine
        self.pkg_feeds = pkg_feeds
        self.packages = packages
        self.external_packages = external_packages
        self.exclude_packages = exclude_packages
        self.exclude_packages.append('kernel-dbg')

        self.pkg_globs = "" if pkg_globs is None else pkg_globs
        if image_linguas:
            self.pkg_globs += " %s" % self._image_linguas_globs(image_linguas)
            self.packages = list(map(lambda s: "locale-base-%s" % s, image_linguas.split())) + self.packages
        if target_rootfs:
            self.target_rootfs = target_rootfs
        else:
            self.target_rootfs = os.path.join(self.workdir, "rootfs")
        self.packages_yaml = os.path.join(self.workdir, "packages.yaml")

        self.rootfs_pre_scripts = [os.path.join(self.data_dir, 'pre_rootfs', 'create_merged_usr_symlinks.sh')]
        if remote_pkgdatadir and utils.is_sdk():
            script_cmd = os.path.join(self.data_dir, 'pre_rootfs', 'update_pkgdata.sh')
            os.environ['REMOTE_PKGDATADIR'] = remote_pkgdatadir
            res, output = utils.run_cmd(script_cmd, shell=True)
            if res:
                raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                                   % (script_cmd, res, output))

        PackageManager = get_pm_class(pkgtype=pkgtype)
        if remote_pkgdatadir:
            self.pm = PackageManager(self.workdir, self.target_rootfs, self.machine, remote_pkgdatadir)
        else:
            self.pm = PackageManager(self.workdir, self.target_rootfs, self.machine)

        self.pm.create_configs()

        self.installed_pkgs = dict()

        utils.fake_root_set_passwd(self.target_rootfs)

        self.rootfs_post_scripts = []

    def _image_linguas_globs(self, image_linguas=""):
        logger.debug("image_linguas %s", image_linguas)
        if not image_linguas:
            return ""

        globs = ""
        split_linguas = set()

        for translation in image_linguas.split():
            split_linguas.add(translation)
            split_linguas.add(translation.split('-')[0])

        split_linguas = sorted(split_linguas)

        for lang in split_linguas:
            globs += " *-locale-%s" % lang

        logger.debug("globs %s", globs)
        return globs

    def add_rootfs_post_scripts(self, script_cmd=None):
        if script_cmd is None:
            return

        if "/etc/sysdef/run_on_upgrade.d/" in script_cmd:
            script_cmd = script_cmd.replace("/etc/sysdef/run_on_upgrade.d/",
                                            "/etc/sysdef/run_on_upgrade.d/%s/" % utils.get_today())

        self.rootfs_post_scripts.append(script_cmd)

    def add_rootfs_pre_scripts(self, script_cmd=None):
        if script_cmd is None:
            return
        self.rootfs_pre_scripts.append(script_cmd)

    def _pre_rootfs(self):
        os.environ['IMAGE_ROOTFS'] = self.pm.target_rootfs
        os.environ['libexecdir'] = '/usr/libexec'

        for script in self.rootfs_pre_scripts:
            logger.debug("Executing '%s' preprocess rootfs..." % script)
            scriptFile = NamedTemporaryFile(delete=True, dir=".")
            with open(scriptFile.name, 'w') as f:
                f.write("#!/usr/bin/env bash\n")
                f.write(script + "\n")
            os.chmod(scriptFile.name, 0o777)
            scriptFile.file.close()
            res, output = utils.run_cmd(scriptFile.name, shell=True)
            if res:
                raise Exception("Executing %s postprocess rootfs failed\nExit code %d. Output:\n%s"
                                   % (script, res, output))

    def _post_rootfs(self):
        for script in self.rootfs_post_scripts:
            logger.debug("Executing '%s' postprocess rootfs..." % script)
            scriptFile = NamedTemporaryFile(delete=True, dir=".")
            with open(scriptFile.name, 'w') as f:
                f.write("#!/usr/bin/env bash\n")
                f.write(script + "\n")
            os.chmod(scriptFile.name, 0o777)
            scriptFile.file.close()
            res, output = utils.run_cmd(scriptFile.name, shell=True)
            if res:
                raise Exception("Executing %s postprocess rootfs failed\nExit code %d. Output:\n%s"
                                   % (script, res, output))

    def _save_installed(self):
        for k, v in self.pm.list_installed().items():
            self.installed_pkgs[k] = v

        with open(self.packages_yaml, "w") as f:
            yaml.dump(self.installed_pkgs, f)
            logger.debug("Save Installed Packages Yaml File to : %s" % (self.packages_yaml))

    def create(self):
        self._pre_rootfs()

        self.pm.create_configs()
        self.pm.insert_feeds_uris(self.pkg_feeds, True if 'dnf' in self.packages or 'apt' in self.packages else False)
        self.pm.set_exclude(self.exclude_packages)
        self.pm.update()
        self.pm.install(self.packages)
        self.pm.install_complementary(self.pkg_globs)

        #
        # We install external packages after packages been installed,
        # because we don't want complementary package logic apply to it.
        #
        duplicate_pkgs = set(self.pm.list_installed().keys()) & set(self.external_packages)
        explicit_duplicate_pkgs = set(self.packages) & set(self.external_packages)
        implicit_duplicate_pkgs = duplicate_pkgs - explicit_duplicate_pkgs
        if explicit_duplicate_pkgs:
            logger.warning("The following packages are specfied both in external-packages and packages: \n\t%s" % '\n\t'.join(sorted(explicit_duplicate_pkgs)))
        if implicit_duplicate_pkgs:
            logger.warning("The following packages are specfied in external-packages, but are brought in by dependencies of packages: \n\t%s" % '\n\t'.join(sorted(implicit_duplicate_pkgs)))
        self.pm.install(self.external_packages)
        self._save_installed()

        self.pm.post_install()

        self.pm.run_intercepts()

        self._post_rootfs()

        self._generate_kernel_module_deps()

    def image_list_installed_packages(self):
        return self.installed_pkgs

    def _check_for_kernel_modules(self, modules_dir):
        for root, dirs, files in os.walk(modules_dir, topdown=True):
            for name in files:
                found_ko = name.endswith(".ko")
                if found_ko:
                    return found_ko
        return False

    def _generate_kernel_module_deps(self):
        modules_dir = os.path.join(self.target_rootfs, 'lib', 'modules')
        # if we don't have any modules don't bother to do the depmod
        if not self._check_for_kernel_modules(modules_dir):
            logger.info("No Kernel Modules found, not running depmod")
            return

        for kernel_ver in os.listdir(modules_dir):
            if os.path.isdir(os.path.join(modules_dir, kernel_ver)):
                utils.run_cmd_oneshot("depmodwrapper -a -b {0} {1}".format(self.target_rootfs, kernel_ver))


class ExtDebRootfs(Rootfs):
    def __init__(self,
                 workdir,
                 data_dir,
                 machine,
                 bootstrap_mirror,
                 bootstrap_distro,
                 bootstrap_components,
                 apt_sources,
                 apt_preference,
                 packages,
                 image_type,
                 debootstrap_key="",
                 apt_keys=[],
                 external_packages=[],
                 exclude_packages=[],
                 target_rootfs=None):

        self.workdir = workdir
        self.data_dir = data_dir
        self.machine = machine
        self.packages = packages
        self.image_type = image_type
        self.external_packages = external_packages
        self.exclude_packages = exclude_packages

        if target_rootfs:
            self.target_rootfs = target_rootfs
        else:
            self.target_rootfs = os.path.join(self.workdir, "rootfs")
        self.packages_yaml = os.path.join(self.workdir, "packages.yaml")

        self.rootfs_pre_scripts = []

        PackageManager = get_pm_class(pkgtype="external-debian")
        self.pm = PackageManager(bootstrap_mirror,
                                 bootstrap_distro,
                                 bootstrap_components,
                                 apt_sources,
                                 apt_preference,
                                 debootstrap_key,
                                 apt_keys,
                                 self.workdir,
                                 self.target_rootfs,
                                 self.machine)

        self.installed_pkgs = dict()

        self.rootfs_post_scripts = []

    def create(self):
        self.pm.create_configs()
        self._pre_rootfs()
        self.pm.set_exclude(self.exclude_packages)
        self.pm.update()

        self.pm.install(self.packages)

        #
        # We install external packages after packages been installed,
        # because we don't want complementary package logic apply to it.
        #
        duplicate_pkgs = set(self.pm.list_installed().keys()) & set(self.external_packages)
        explicit_duplicate_pkgs = set(self.packages) & set(self.external_packages)
        implicit_duplicate_pkgs = duplicate_pkgs - explicit_duplicate_pkgs
        if explicit_duplicate_pkgs:
            logger.warning("The following packages are specfied both in external-packages and packages: \n\t%s" % '\n\t'.join(sorted(explicit_duplicate_pkgs)))
        if implicit_duplicate_pkgs:
            logger.warning("The following packages are specfied in external-packages, but are brought in by dependencies of packages: \n\t%s" % '\n\t'.join(sorted(implicit_duplicate_pkgs)))
        self.pm.install(self.external_packages)
        self._save_installed()

        self.pm.post_install()

        self._post_rootfs()

        self._generate_kernel_module_deps()
