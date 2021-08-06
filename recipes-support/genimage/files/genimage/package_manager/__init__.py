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
import importlib
import re
import sys
import os
import hashlib
import logging
import tempfile
import subprocess
import textwrap

from abc import ABCMeta, abstractmethod

import genimage.utils as utils

logger = logging.getLogger('appsdk')

def failed_postinsts_abort(pkgs, log_path):
    message = textwrap.dedent("""\
                  Postinstall scriptlets of %s have failed. If the intention is to defer them to first boot,
                  then please place them into pkg_postinst_ontarget:${PN} ().
                  Deferring to first boot via 'exit 1' is no longer supported.
                  Details of the failure are in %s.""" %(pkgs, log_path))
    logger.error(message)
    sys.exit(1)


class PackageManager(object, metaclass=ABCMeta):
    def __init__(self,
                 workdir = os.path.join(os.getcwd(),"workdir"),
                 target_rootfs = os.path.join(os.getcwd(), "workdir/rootfs"),
                 machine = 'intel-x86-64',
                 remote_pkgdatadir = None):

        self.workdir = workdir
        self.target_rootfs = target_rootfs

        self.temp_dir = os.path.join(workdir, "temp")
        utils.mkdirhier(self.target_rootfs)
        utils.mkdirhier(self.temp_dir)

        self.feed_archs = utils.get_yocto_var("PACKAGE_ARCHS").replace("-", "_")

        self.package_seed_sign = False

        self.bad_recommendations = []
        self.package_exclude = []
        self.primary_arch = machine.replace('-', '_')
        self.machine = machine

        self.remote_pkgdatadir = remote_pkgdatadir

        if utils.is_sdk():
            self.pkgdatadir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], "../pkgdata", machine)
        elif utils.is_build():
            self.pkgdatadir = os.path.join(utils.sysroot_dir, "../pkgdata", machine)
        else:
            logger.error("Neither sdk or build")
            sys.exit(1)

        self.oe_pkgdata_util = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], "usr/share/poky/scripts/oe-pkgdata-util")

        self._initialize_intercepts()

    def _initialize_intercepts(self):
        logger.debug("Initializing intercept dir for %s" % self.target_rootfs)
        # As there might be more than one instance of PackageManager operating at the same time
        # we need to isolate the intercept_scripts directories from each other,
        # hence the ugly hash digest in dir name.
        self.intercepts_dir = os.path.join(self.workdir, "intercept_scripts-%s" %
                                           (hashlib.sha256(self.target_rootfs.encode()).hexdigest()))

        logger.debug("intercepts_dir %s" % self.intercepts_dir)
        postinst_intercepts_path = "%s/usr/share/poky/scripts/postinst-intercepts" % os.environ['OECORE_NATIVE_SYSROOT']
        postinst_intercepts = utils.which_wild('*', postinst_intercepts_path)

        logger.debug('Collected intercepts:\n%s' % ''.join('  %s\n' % i for i in postinst_intercepts))
        utils.remove(self.intercepts_dir, True)
        utils.mkdirhier(self.intercepts_dir)
        for intercept in postinst_intercepts:
            utils.copyfile(intercept, os.path.join(self.intercepts_dir, os.path.basename(intercept)))

    @abstractmethod
    def create_configs(self):
        logger.debug("create_configs")

    @abstractmethod
    def insert_feeds_uris(self, remote_uris, save_repo=True):
        logger.debug("insert_feeds_uris")

    @abstractmethod
    def list_installed(self):
        pass

    @abstractmethod
    def update(self):
        """
        Update the package manager package database.
        """
        pass

    @abstractmethod
    def install(self, pkgs, attempt_only=False):
        """
        Install a list of packages. 'pkgs' is a list object. If 'attempt_only' is
        True, installation failures are ignored.
        """
        pass

    @abstractmethod
    def remove(self, pkgs, with_dependencies=True):
        """
        Remove a list of packages. 'pkgs' is a list object. If 'with_dependencies'
        is False, then any dependencies are left in place.
        """
        pass

    @abstractmethod
    def _handle_intercept_failure(self, registered_pkgs):
        pass

    def post_install(self):
        pass

    def install_complementary(self, globs=""):
        """
        Install complementary packages based upon the list of currently installed
        packages e.g. *-src, *-dev, *-dbg, etc. This will only attempt to install
        these packages, if they don't exist then no error will occur.
        """
        if not globs:
            return

        logger.debug("Installing complementary packages (%s) ..." % globs)
        # we need to write the list of installed packages to a file because the
        # oe-pkgdata-util reads it from a file
        with tempfile.NamedTemporaryFile(mode="w+", prefix="installed-pkgs") as installed_pkgs:
            pkgs = self.list_installed()

            provided_pkgs = set()
            for pkg in pkgs.values():
                provided_pkgs |= set(pkg.get('provs', []))

            output = utils.format_pkg_list(pkgs, "arch")
            installed_pkgs.write(output)
            installed_pkgs.flush()

            cmd = '%s -p %s glob %s %s' % (self.oe_pkgdata_util, self.pkgdatadir, installed_pkgs.name, globs)
            logger.debug(cmd)
            output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode('utf-8')

            complementary_pkgs = set(output.split())
            skip_pkgs = sorted(complementary_pkgs & provided_pkgs)
            install_pkgs = sorted(complementary_pkgs - provided_pkgs)
            logger.debug("Installing complementary packages ... %s (skipped already provided packages %s)" % (
                ' '.join(install_pkgs),
                ' '.join(skip_pkgs)))
            self.install(install_pkgs, attempt_only=True)

    def _postpone_to_first_boot(self, postinst_intercept_hook):
        with open(postinst_intercept_hook) as intercept:
            registered_pkgs = None
            for line in intercept.read().split("\n"):
                m = re.match(r"^##PKGS:(.*)", line)
                if m is not None:
                    registered_pkgs = m.group(1).strip()
                    break

            if registered_pkgs is not None:
                logger.debug("If an image is being built, the postinstalls for the following packages "
                        "will be postponed for first boot: %s" %
                        registered_pkgs)

                # call the backend dependent handler
                self._handle_intercept_failure(registered_pkgs)

    def run_intercepts(self):
        intercepts_dir = self.intercepts_dir

        logger.debug("Running intercept scripts:")
        os.environ['D'] = self.target_rootfs
        os.environ['STAGING_DIR_NATIVE'] = os.environ['OECORE_NATIVE_SYSROOT']
        os.environ['libdir_native'] = "/usr/lib"

        for script in os.listdir(intercepts_dir):
            script_full = os.path.join(intercepts_dir, script)

            if script == "postinst_intercept" or not os.access(script_full, os.X_OK):
                continue

            # we do not want to run any multilib variant of this
            if script.startswith("delay_to_first_boot"):
                self._postpone_to_first_boot(script_full)
                continue

            logger.debug("> Executing %s intercept ..." % script)
            res, output = utils.run_cmd(script_full)
            if res:
                if "qemuwrapper: qemu usermode is not supported" in output:
                    logger.debug("The postinstall intercept hook '%s' could not be executed due to missing qemu usermode support"
                            % (script))
                    self._postpone_to_first_boot(script_full)
                else:
                    logger.warning("The postinstall intercept hook '%s' failed, ignore it\n%s" % (script, output))


def get_pm_class(pkgtype="rpm"):
    if pkgtype == "rpm":
        mod = importlib.import_module('genimage.package_manager.' + pkgtype)
        return mod.DnfRpm
    elif pkgtype == "deb":
        mod = importlib.import_module('genimage.package_manager.' + pkgtype)
        return mod.AptDeb
    elif pkgtype == "external-debian":
        mod = importlib.import_module('genimage.package_manager.deb')
        return mod.ExternalDebian

    sys.exit(1)
