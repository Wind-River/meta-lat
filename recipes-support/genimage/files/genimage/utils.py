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
import sys
import os
import errno
import time
import subprocess
import glob
import stat
import shutil
import re
from ruamel.yaml.representer import RoundTripRepresenter
from ruamel.yaml import YAML

def repr_str(dumper: RoundTripRepresenter, data: str):
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)

yaml = YAML()
yaml.representer.add_representer(str, repr_str)

logger = logging.getLogger('appsdk')

def set_logger(logger, level=logging.DEBUG, log_path=None):
    logger.setLevel(logging.DEBUG)

    class ColorFormatter(logging.Formatter):
        FORMAT = ("$BOLD%(name)-s$RESET - %(levelname)s: %(message)s")

        BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE = list(range(8))

        RESET_SEQ = "\033[0m"
        COLOR_SEQ = "\033[1;%dm"
        BOLD_SEQ = "\033[1m"

        COLORS = {
            'WARNING': YELLOW,
            'INFO': GREEN,
            'DEBUG': BLUE,
            'ERROR': RED
        }

        def formatter_msg(self, msg, use_color = True):
            if use_color:
                msg = msg.replace("$RESET", self.RESET_SEQ).replace("$BOLD", self.BOLD_SEQ)
            else:
                msg = msg.replace("$RESET", "").replace("$BOLD", "")
            return msg

        def __init__(self, use_color=True):
            msg = self.formatter_msg(self.FORMAT, use_color)
            logging.Formatter.__init__(self, msg)
            self.use_color = use_color

        def format(self, record):
            levelname = record.levelname
            if self.use_color and levelname in self.COLORS:
                fore_color = 30 + self.COLORS[levelname]
                levelname_color = self.COLOR_SEQ % fore_color + levelname + self.RESET_SEQ
                record.levelname = levelname_color
            return logging.Formatter.format(self, record)

    # create file handler and set level to debug
    set_logger_file(logger, log_path)

    # create console handler and set level by input param
    ch = logging.StreamHandler()
    ch.setLevel(level)
    if sys.stdout.isatty():
        ch.setFormatter(ColorFormatter())
    else:
        ch.setFormatter(ColorFormatter(use_color=False))
    logger.addHandler(ch)

def set_logger_file(logger, log_path=None):
    if log_path is None:
        return

    mkdirhier(log_path)
    log = os.path.join(log_path, "log.appsdk_{0}".format(int(time.time())))
    log_symlink = os.path.join(log_path, "log.appsdk")
    if os.path.islink(log_symlink):
        os.remove(log_symlink)
    os.symlink(os.path.basename(log), log_symlink)

    FORMAT = ("%(name)s - %(levelname)s: %(message)s")
    fh = logging.FileHandler(log)
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(logging.Formatter(FORMAT))
    logger.addHandler(fh)

def run_cmd(cmd, shell=False, print_output=True, env=None, cwd=None):
    logger.debug('Running %s' % cmd)
    if env is None:
        env = os.environ

    outputs = ""
    process = subprocess.Popen(cmd,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT,
                               shell=shell,
                               cwd=cwd,
                               universal_newlines=True, env=env)
    while True:
        output = process.stdout.readline()
        if output:
            if print_output:
                logger.debug(output.rstrip("\n"))
            outputs += output
        if process.poll() is not None:
            break

    rc = process.poll()
    logger.debug("rc %d" % rc)
    return rc, outputs

def run_cmd_oneshot(cmd, shell=True, print_output=False, cwd=None):
    res, output = run_cmd(cmd, shell, print_output, cwd=cwd)
    if res:
        raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                           % (cmd, res, output))

day_time = time.strftime("%Y%m%d%H%M%S")
def get_today():
    return day_time

def fake_root(workdir = os.path.join(os.getcwd(),"workdir")):
    if os.getuid() == 0:
        logger.info("Already root, do not use fake root")
        return

    native_sysroot = os.environ['OECORE_NATIVE_SYSROOT']
    os.environ['PSEUDO_PREFIX'] = os.path.join(native_sysroot, 'usr')
    os.environ['PSEUDO_LOCALSTATEDIR'] = os.path.join(workdir, 'pseudo')
    os.environ['PSEUDO_NOSYMLINKEXP'] = "1"
    os.environ['LD_PRELOAD'] = os.path.join(native_sysroot, 'usr/lib/pseudo/lib64/libpseudo.so')
    os.environ['LC_ALL'] = "en_US.UTF-8"
    os.environ['libexecdir'] = '/usr/libexec'

def exit_fake_root():
    pseudo_vars = ['PSEUDO_PREFIX', 'PSEUDO_LOCALSTATEDIR', 'PSEUDO_NOSYMLINKEXP', 'LD_PRELOAD']
    for pv in pseudo_vars:
        if pv in os.environ:
            del os.environ[pv]

def fake_root_set_passwd(rootfs=None):
    if rootfs is None:
        raise Exception("fake_root_set_passwd rootfs is None")
    os.environ['PSEUDO_PASSWD'] = rootfs
    logger.debug("PSEUDO_PASSWD %s" % os.environ['PSEUDO_PASSWD'])

def mkdirhier(directory):
    """Create a directory like 'mkdir -p', but does not complain if
    directory already exists like os.makedirs
    """
    try:
        subprocess.check_call("mkdir -p %s" % directory, shell=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        raise Exception("Create dir %s failed, please make sure you have the permission" % directory)

def write(file_path, mode="w", content=None):
    if not file_path or not mode or content is None:
        return
    if not content:
        cmd = "touch %s" % file_path
    else:
        if mode == "w":
            cmd = "echo '%s' > %s" % (content, file_path)
        elif mode in ["w+", "a+"]:
            cmd = "echo '%s' >> %s" % (content, file_path)
    try:
        res = subprocess.check_call(cmd, shell=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        raise Exception("Write file %s failed" % res)

def remove(path, recurse=False, ionice=False):
    """Equivalent to rm -f or rm -rf"""
    if not path:
        return
    if recurse:
        for name in glob.glob(path):
            if _check_unsafe_delete_path(path):
                raise Exception('bb.utils.remove: called with dangerous path "%s" and recurse=True, refusing to delete!' % path)
        # shutil.rmtree(name) would be ideal but its too slow
        cmd = [] 
        if ionice:
            cmd = ['ionice', '-c', '3'] 
        subprocess.check_call(cmd + ['rm', '-rf'] + glob.glob(path))
        return
    for name in glob.glob(path):
        try: 
            os.unlink(name)
        except OSError as exc: 
            if exc.errno != errno.ENOENT:
                raise

def _check_unsafe_delete_path(path):
    """
    Basic safeguard against recursively deleting something we shouldn't. If it returns True,
    the caller should raise an exception with an appropriate message.
    NOTE: This is NOT meant to be a security mechanism - just a guard against silly mistakes
    with potentially disastrous results.
    """
    extra = ''
    # HOME might not be /home/something, so in case we can get it, check against it
    homedir = os.environ.get('HOME', '')
    if homedir:
        extra = '|%s' % homedir
    if re.match('(/|//|/home|/home/[^/]*%s)$' % extra, os.path.abspath(path)):
        return True
    return False

def resymlink(source, destination, rm_old_src=True, rm_old_dst=True):
    """Create a symbolic link and remove old if available"""
    try:
        if rm_old_src:
            remove(os.path.realpath(destination))
        if rm_old_dst:
            remove(destination)
        os.symlink(source, destination)
    except OSError as e:
        if e.errno != errno.EEXIST or os.readlink(destination) != source:
            raise

def copyfile(src, dest, newmtime = None, sstat = None):
    """
    Copies a file from src to dest, preserving all permissions and
    attributes; mtime will be preserved even when moving across
    filesystems.  Returns true on success and false on failure.
    """
    #print "copyfile(" + src + "," + dest + "," + str(newmtime) + "," + str(sstat) + ")"
    try:
        if not sstat:
            sstat = os.lstat(src)
    except Exception as e:
        logger.warning("copyfile: stat of %s failed (%s)" % (src, e))
        return False

    destexists = 1
    try:
        dstat = os.lstat(dest)
    except:
        dstat = os.lstat(os.path.dirname(dest))
        destexists = 0

    if destexists:
        if stat.S_ISLNK(dstat[stat.ST_MODE]):
            try:
                os.unlink(dest)
                destexists = 0
            except Exception as e:
                pass

    if stat.S_ISLNK(sstat[stat.ST_MODE]):
        try:
            target = os.readlink(src)
            if destexists and not stat.S_ISDIR(dstat[stat.ST_MODE]):
                os.unlink(dest)
            os.symlink(target, dest)
            os.lchown(dest,sstat[stat.ST_UID],sstat[stat.ST_GID])
            return os.lstat(dest)
        except Exception as e:
            logger.warning("copyfile: failed to create symlink %s to %s (%s)" % (dest, target, e))
            return False

    a = subprocess.getstatusoutput("/bin/cp -f " + "'" + src + "' '" + dest + "'")
    if a[0] != 0:
        logger.warning("copyfile: failed to copy special file %s to %s (%s)" % (src, dest, a))
        return False # failure
    try:
        os.lchown(dest, sstat[stat.ST_UID], sstat[stat.ST_GID])
        os.chmod(dest, stat.S_IMODE(sstat[stat.ST_MODE])) # Sticky is reset on chown
    except Exception as e:
        logger.debug("copyfile: failed to chown/chmod %s (%s)" % (dest, e))
        return False

    if newmtime:
        os.utime(dest, (newmtime, newmtime))
    else:
        os.utime(dest, (sstat[stat.ST_ATIME], sstat[stat.ST_MTIME]))
        newmtime = sstat[stat.ST_MTIME]
    return newmtime

def which_wild(pathname, path=None, mode=os.F_OK, *, reverse=False, candidates=False):
    """Search a search path for pathname, supporting wildcards.

    Return all paths in the specific search path matching the wildcard pattern
    in pathname, returning only the first encountered for each file. If
    candidates is True, information on all potential candidate paths are
    included.
    """
    paths = (path or os.environ.get('PATH', os.defpath)).split(':')
    if reverse:
        paths.reverse()

    seen, files = set(), []
    for index, element in enumerate(paths):
        if not os.path.isabs(element):
            element = os.path.abspath(element)

        candidate = os.path.join(element, pathname)
        globbed = glob.glob(candidate)
        if globbed:
            for found_path in sorted(globbed):
                if not os.access(found_path, mode):
                    continue
                rel = os.path.relpath(found_path, element)
                if rel not in seen:
                    seen.add(rel)
                    if candidates:
                        files.append((found_path, [os.path.join(p, rel) for p in paths[:index+1]]))
                    else:
                        files.append(found_path)

    return files

def format_pkg_list(pkg_dict, ret_format=None):
    output = []

    if ret_format == "arch":
        for pkg in sorted(pkg_dict):
            output.append("%s %s" % (pkg, pkg_dict[pkg]["arch"]))
    elif ret_format == "file":
        for pkg in sorted(pkg_dict):
            output.append("%s %s %s" % (pkg, pkg_dict[pkg]["filename"], pkg_dict[pkg]["arch"]))
    elif ret_format == "ver":
        for pkg in sorted(pkg_dict):
            output.append("%s %s %s" % (pkg, pkg_dict[pkg]["arch"], pkg_dict[pkg]["ver"]))
    elif ret_format == "deps":
        for pkg in sorted(pkg_dict):
            for dep in pkg_dict[pkg]["deps"]:
                output.append("%s|%s" % (pkg, dep))
    else:
        for pkg in sorted(pkg_dict):
            output.append(pkg)

    output_str = '\n'.join(output)

    if output_str:
        # make sure last line is newline terminated
        output_str += '\n'

    return output_str

def check_gpg_keys(gpg_data):
    gpg_path = os.path.expandvars(gpg_data['gpg_path'])
    if not os.path.isdir(gpg_path):
        run_cmd_oneshot("mkdir -m 0700 -p %s" % gpg_path)

    # The feature is supposed to be "ostree, rpm, boot, ima"
    for feature in ['ostree']:
        gpgkey = os.path.expandvars(gpg_data[feature]['gpgkey'])
        gpgid = gpg_data[feature]['gpgid']
        gpg_password = gpg_data[feature]['gpg_password']

        cmd = "gpg --homedir {0} --list-keys {1}".format(gpg_path, gpgid)
        res, output = run_cmd(cmd, shell=True)
        if not res:
            continue

        cmd = "gpg --batch --homedir {0} --passphrase {1} --import {2}".format(gpg_path, gpg_password, gpgkey)
        res, output = run_cmd(cmd, shell=True)
        if res:
            run_cmd_oneshot(cmd)

def get_ostree_wks(ostree_use_ab="1", machine="intel-x86-64"):
    ostree_ab_wks = "ab" if ostree_use_ab=="1" else "noab"
    ostree_arch_wks = "ostree-grub" if machine=="intel-x86-64" else "ostree-uboot-sd"
    wks_template = "{0}-{1}.wks.in".format(ostree_arch_wks, ostree_ab_wks)
    wks_full_path = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], "usr/share/genimage/data/wic", wks_template)

    return wks_full_path

def show_task_info(msg):
    def show_task_info_decorator(func):
        def func_wrapper(self):
            logger.info("%s: Started", msg)
            start_time = time.time()
            func(self)
            logger.info("%s: Succeeded(took %d seconds) ", msg, time.time()-start_time)

        return func_wrapper
    return show_task_info_decorator

sysroot_dir = os.path.abspath(os.path.dirname(__file__) + '/../../../../../..')
def is_sdk():
    if len(glob.glob('%s/x86_64-*-linux' % sysroot_dir)) == 0:
        return False
    if not 'CC' in os.environ:
        return False
    if not '--sysroot=' in os.environ['CC']:
        return False
    return True
def is_build():
    if os.path.exists(os.path.join(sysroot_dir, "x86_64")):
        return True
    return False

def umount(target_rootfs):
   for f in ["/dev/pts", "/dev", "/proc", "/sys"]:
        cmd = "umount %s%s" % (target_rootfs, f)
        run_cmd(cmd, shell=True, print_output=True)

def cleanup(image_workdir, ostree_osname):
    rootfs_ota = os.path.join(image_workdir, "rootfs_ota/ostree/deploy/%s/deploy" % ostree_osname)
    if os.path.exists(rootfs_ota):
        run_cmd_oneshot("chattr -i %s/*" % rootfs_ota)

    run_cmd_oneshot("rm -rf %s/rootfs*" % image_workdir)

def get_debootstrap_input(package_feeds, debian_distros):
    debian_mirror = ""
    debian_distro = ""
    for url in package_feeds:
        apt_source = url.split()
        for distro in debian_distros:
            if distro in apt_source:
                i = apt_source.index(distro)
                mirror = apt_source[i-1]
                logger.info("Mirror: %s, Distro %s", mirror, distro)
                return mirror, distro

    logger.info("Mirror: %s, Distro %s", mirror, distro)
    return None, None
