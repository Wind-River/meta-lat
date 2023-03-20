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
import logging
import os
import sys
import shutil
import subprocess
import collections
import hashlib
import re
import tempfile
import configparser

from genimage.utils import set_logger
from genimage.constant import DEFAULT_LOCAL_RPM_PACKAGE_FEED
from genimage.package_manager import PackageManager
from genimage.package_manager import failed_postinsts_abort
import genimage.utils as utils
logger = logging.getLogger('appsdk')

class DnfRpm(PackageManager):
    def _configure_dnf(self):
        # libsolv handles 'noarch' internally, we don't need to specify it explicitly
        archs = [i for i in reversed(self.feed_archs.split()) if i not in ["any", "all", "noarch"]]
        # This prevents accidental matching against libsolv's built-in policies
        if len(archs) <= 1:
            archs = archs + ["bogusarch"]
        # This architecture needs to be upfront so that packages using it are properly prioritized
        #archs = ["sdk_provides_dummy_target"] + archs
        confdir = "%s/%s" %(self.target_rootfs, "etc/dnf/vars/")
        utils.mkdirhier(confdir)
        open(confdir + "arch", 'w').write(":".join(archs))
        distro_codename = None
        open(confdir + "releasever", 'w').write(distro_codename if distro_codename is not None else '')

        if not os.path.exists(os.path.join(self.target_rootfs, "etc/dnf/dnf.conf")):
            open(os.path.join(self.target_rootfs, "etc/dnf/dnf.conf"), 'w').write("")


    def _configure_rpm(self):
        # We need to configure rpm to use our primary package architecture as the installation architecture,
        # and to make it compatible with other package architectures that we use.
        # Otherwise it will refuse to proceed with packages installation.
        platformconfdir = "%s/%s" %(self.target_rootfs, "etc/rpm/")
        rpmrcconfdir = "%s/%s" %(self.target_rootfs, "etc/")
        utils.mkdirhier(platformconfdir)
        open(platformconfdir + "platform", 'w').write("%s-pc-linux\n" % self.primary_arch)
        with open(rpmrcconfdir + "rpmrc", 'w') as f:
            f.write("arch_compat: %s: %s\n" % (self.primary_arch, self.feed_archs if len(self.feed_archs) > 0 else self.primary_arch))
            f.write("buildarch_compat: %s: noarch\n" % self.primary_arch)

        open(platformconfdir + "macros", 'w').write("%_transaction_color 7\n")
        open(platformconfdir + "macros", 'w').write("%_var /var\n")

        if self.machine == "intel-x86-64":
            open(platformconfdir + "macros", 'a').write("%_prefer_color 7\n")

    def create_configs(self):
        logger.debug("create_configs")
        self._configure_dnf()
        self._configure_rpm()

    def _prepare_pkg_transaction(self):
        os.environ['D'] = self.target_rootfs
        os.environ['OFFLINE_ROOT'] = self.target_rootfs
        os.environ['IPKG_OFFLINE_ROOT'] = self.target_rootfs
        os.environ['OPKG_OFFLINE_ROOT'] = self.target_rootfs
        os.environ['INTERCEPT_DIR'] = self.intercepts_dir
        os.environ['NATIVE_ROOT'] = os.environ['OECORE_NATIVE_SYSROOT']
        os.environ['RPM_NO_CHROOT_FOR_SCRIPTS'] = "1"

    def get_gpgkey(self):
        return None

    def insert_feeds_uris(self, remote_uris, save_repo=True):
        from urllib.parse import urlparse

        gpg_opts = ''
        if self.package_seed_sign:
            gpg_opts += 'repo_gpgcheck=1\n'
            gpg_opts += 'gpgkey=file://etc/pki/packagefeed-gpg/%s\n' % (self.get_gpgkey())
        else:
            gpg_opts += 'gpgcheck=0\n'

        utils.remove(os.path.join(self.temp_dir, "yum.repos.d"), recurse=True)
        utils.mkdirhier(os.path.join(self.temp_dir, "yum.repos.d"))
        utils.mkdirhier(os.path.join(self.target_rootfs, "etc", "yum.repos.d"))
        for uri in remote_uris:
            repo_base = "oe-remote-repo" + "-".join(urlparse(uri).path.split("/"))
            repo_name = "OE Remote Repo:" + " ".join(urlparse(uri).path.split("/"))
            repo_uri = uri

            if save_repo:
                open(os.path.join(self.target_rootfs, "etc", "yum.repos.d", repo_base + ".repo"), 'w').write(
                        "[%s]\nname=%s\nbaseurl=%s\n%s" % (repo_base, repo_name, repo_uri, gpg_opts))

            if utils.is_sdk():
                repo_cacert = os.path.join(os.environ["OECORE_NATIVE_SYSROOT"], "etc/ssl/certs/ca-certificates.crt")
                open(os.path.join(self.temp_dir, "yum.repos.d", repo_base + ".repo"), 'w').write(
                        "[%s]\nname=%s\nbaseurl=%s\nsslcacert=%s\n%s" % (repo_base, repo_name, repo_uri, repo_cacert, gpg_opts))

            # For native build
            elif utils.is_build():
                # Do not use remote package repo to generate image
                if self.remote_pkgdatadir and repo_uri.startswith(self.remote_pkgdatadir):
                    continue

                # Use third party repo to generate image
                open(os.path.join(self.temp_dir, "yum.repos.d", repo_base + ".repo"), 'w').write(
                        "[%s]\nname=%s\nbaseurl=%s\n%s" % (repo_base, repo_name, repo_uri, gpg_opts))

        if utils.is_build():
            for uri in DEFAULT_LOCAL_RPM_PACKAGE_FEED:
                repo_base = "oe-local-repo" + "-".join(urlparse(uri).path.split("/"))
                repo_name = "OE Local Repo:" + " ".join(urlparse(uri).path.split("/"))
                repo_uri = uri
                open(os.path.join(self.temp_dir, "yum.repos.d", repo_base + ".repo"), 'w').write(
                        "[%s]\nname=%s\nbaseurl=%s\n%s" % (repo_base, repo_name, repo_uri, gpg_opts))

    def _invoke_dnf(self, dnf_args, fatal = True, print_output = True ):
        os.environ['RPM_ETCCONFIGDIR'] = self.target_rootfs
        path = os.getenv('PATH')
        python3native = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/bin/python3-native')
        if os.path.exists(python3native):
            path = "{0}:{1}".format(python3native, path)
        dnf_cmd = shutil.which("dnf", path=path)
        standard_dnf_args = ["-v", "--rpmverbosity=info", "-y",
                             "-c", os.path.join(self.target_rootfs, "etc/dnf/dnf.conf"),
                             "--setopt=reposdir=%s" %(os.path.join(self.temp_dir, "yum.repos.d")),
                             "--setopt=keepcache=True",
                             "--setopt=cachedir=%s" % (os.path.join(self.workdir, "dnfcache")),
                             "--installroot=%s" % (self.target_rootfs),
                             "--setopt=logdir=%s" % (self.temp_dir)
                            ]
        if hasattr(self, "rpm_repo_dir"):
            standard_dnf_args.append("--repofrompath=oe-repo,%s" % (self.rpm_repo_dir))
        cmd = [dnf_cmd] + standard_dnf_args + dnf_args
        logger.debug('Running %s' % ' '.join(cmd))

        env = os.environ.copy()
        env['PATH'] = path
        res, output = utils.run_cmd(cmd, print_output=print_output, env=env)
        if res:
            logger.error("Could not invoke dnf. Command "
                     "'%s' returned %d:\n%s" % (' '.join(cmd), res, output))

            sys.exit(1)
        return output

    def set_exclude(self, package_exclude = None):
        if not package_exclude:
            return

        self.package_exclude.extend(package_exclude)
        self.package_exclude = list(set(self.package_exclude))
        logger.debug("Set Exclude Packages: %s", self.package_exclude)

    def post_install(self):
        logger.debug("post_install")
        if 'dnf' in self.list_installed():
            self._set_target_dnf_conf()

    def _set_target_dnf_conf(self):
        if not self.package_exclude:
            return

        dnf_conf = os.path.join(self.target_rootfs, "etc/dnf/dnf.conf")
        if not os.path.exists(dnf_conf):
            return

        config = configparser.ConfigParser()
        config.read(dnf_conf)

        exclude = config.get('main', 'exclude', fallback='')
        if exclude:
            exclude += ' {0}'.format(' '.join(self.package_exclude))
        else:
            exclude = ' '.join(self.package_exclude)

        config.set('main', 'exclude', exclude)

        with open(dnf_conf, 'w') as f:
            config.write(f, space_around_delimiters=False)

    def install(self, pkgs, attempt_only = False):
        logger.debug("dnf install: %s, attemplt %s" % (pkgs, attempt_only))
        if len(pkgs) == 0:
            return
        self._prepare_pkg_transaction()

        exclude_pkgs = (self.bad_recommendations.split() if self.bad_recommendations else [])
        exclude_pkgs += (self.package_exclude if self.package_exclude else [])

        output = self._invoke_dnf((["--skip-broken"] if attempt_only else []) +
                         (["-x", ",".join(exclude_pkgs)] if len(exclude_pkgs) > 0 else []) +
                         (["--setopt=install_weak_deps=False"] if os.environ.get('NO_RECOMMENDATIONS', '0') == '1' else []) +
                         (["--nogpgcheck"] if not self.package_seed_sign else ["--setopt=gpgcheck=True"]) +
                         ["install"] +
                         pkgs)

        failed_scriptlets_pkgnames = collections.OrderedDict()
        for line in output.splitlines():
            if line.startswith("Error in POSTIN scriptlet in rpm package"):
                failed_scriptlets_pkgnames[line.split()[-1]] = True

        if len(failed_scriptlets_pkgnames) > 0:
            failed_postinsts_abort(list(failed_scriptlets_pkgnames.keys()),
                                   self.temp_dir)

    def remove(self, pkgs, with_dependencies = True):
        logger.debug("dnf remove: %s" % (pkgs))
        if not pkgs:
            return

        self._prepare_pkg_transaction()

        if with_dependencies:
            self._invoke_dnf(["remove"] + pkgs)
        else:
            cmd = shutil.which("rpm", path=os.getenv('PATH'))
            args = ["-e", "-v", "--nodeps", "--root=%s" %self.target_rootfs]
            logger.info("Running %s" % ' '.join([cmd] + args + pkgs))
            res, output = utils.run_cmd([cmd] + args + pkgs)
            if res:
                raise Exception("Could not invoke rpm. Command "
                     "'%s' returned %d:\n%s" % (' '.join([cmd] + args + pkgs), res, output))


    def upgrade(self):
        self._prepare_pkg_transaction()
        self._invoke_dnf(["upgrade"])

    def autoremove(self):
        self._prepare_pkg_transaction()
        self._invoke_dnf(["autoremove"])

    def list_installed(self):
        output = self._invoke_dnf(["repoquery", "--installed", "--queryformat", "Package: %{name} %{arch} %{version} %{name}-%{version}-%{release}.%{arch}.rpm\nDependencies:\n%{requires}\nRecommendations:\n%{recommends}\nDependenciesEndHere:\n"],
                                  print_output = False)
        packages = {}
        current_package = None
        current_deps = None
        current_state = "initial"
        for line in output.splitlines():
            if line.startswith("Package:"):
                package_info = line.split(" ")[1:]
                current_package = package_info[0]
                package_arch = package_info[1]
                package_version = package_info[2]
                package_rpm = package_info[3]
                packages[current_package] = {"arch":package_arch, "ver":package_version, "filename":package_rpm}
                current_deps = []
            elif line.startswith("Dependencies:"):
                current_state = "dependencies"
            elif line.startswith("Recommendations"):
                current_state = "recommendations"
            elif line.startswith("DependenciesEndHere:"):
                current_state = "initial"
                packages[current_package]["deps"] = current_deps
            elif len(line) > 0:
                if current_state == "dependencies":
                    current_deps.append(line)
                elif current_state == "recommendations":
                    current_deps.append("%s [REC]" % line)

        return packages

    def update(self):
        self._invoke_dnf(["makecache", "--refresh"])

    def _script_num_prefix(self, path):
        files = os.listdir(path)
        numbers = set()
        numbers.add(99)
        for f in files:
            numbers.add(int(f.split("-")[0]))
        return max(numbers) + 1

    def save_rpmpostinst(self, pkg):
        logger.debug("Saving postinstall script of %s" % (pkg))
        cmd = shutil.which("rpm", path=os.getenv('PATH'))
        args = ["-q", "--root=%s" % self.target_rootfs, "--queryformat", "%{postin}", pkg]
        res, output = utils.run_cmd([cmd] + args)
        if res:
            raise Exception("Could not invoke rpm. Command "
                     "'%s' returned %d:\n%s" % (' '.join([cmd] + args), res, output))

        # may need to prepend #!/bin/sh to output

        target_path = os.path.join(self.target_rootfs, 'etc/rpm-postinsts/')
        utils.mkdirhier(target_path)
        num = self._script_num_prefix(target_path)
        saved_script_name = os.path.join(target_path, "%d-%s" % (num, pkg))
        open(saved_script_name, 'w').write(output)
        os.chmod(saved_script_name, 0o755)

    def _handle_intercept_failure(self, registered_pkgs):
        rpm_postinsts_dir = self.target_rootfs + '/etc/rpm-postinsts/'
        utils.mkdirhier(rpm_postinsts_dir)

        # Save the package postinstalls in /etc/rpm-postinsts
        for pkg in registered_pkgs.split():
            self.save_rpmpostinst(pkg)

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

def test():
    from genimage.constant import DEFAULT_RPM_PACKAGE_FEED
    from genimage.constant import DEFAULT_PACKAGES
    from genimage.constant import DEFAULT_MACHINE
    from genimage.constant import DEFAULT_IMAGE
    from genimage.utils import  fake_root

    logger = logging.getLogger('dnf')
    set_logger(logger)
    logger.setLevel(logging.DEBUG)

    fake_root()
    package = DEFAULT_PACKAGES[DEFAULT_MACHINE]
    pm = DnfRpm(machine=DEFAULT_MACHINE)
    pm.create_configs()
    pm.update()
    pm.insert_feeds_uris(DEFAULT_RPM_PACKAGE_FEED)
    pm.install(package)
    pm.install_complementary("*-src *-dev *-dbg")
    #pm.run_intercepts()
    #pm.install([p + '-doc' for p in package], attempt_only = True)
    #pm.remove(['grub-efi'])


if __name__ == "__main__":
    test()
