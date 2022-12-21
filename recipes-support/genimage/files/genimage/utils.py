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
import configparser
from pykwalify.core import Core

from genimage.constant import DEFAULT_MACHINE
import genimage.debian_constant as deb_constant
import genimage.constant as constant

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

current_subprocs = set()

def signal_exit_handler(signal, frame):
    logger.info("Recieve signal %d", signal)
    for proc in current_subprocs:
        if proc.poll() is None:
            pgid = os.getpgid(proc.pid)
            logger.info("Send signal %s to proc pgid %d", signal, pgid)
            os.killpg(pgid, signal)

    sys.exit(1)

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
                               restore_signals=False,
                               preexec_fn=os.setsid,
                               universal_newlines=True, env=env)
    current_subprocs.add(process)
    while True:
        output = process.stdout.readline()
        if output:
            if print_output:
                logger.debug(output.rstrip("\n"))
            outputs += output
        if process.poll() is not None:
            current_subprocs.remove(process)
            break

    # Read the remaining logs from stdout after process terminates
    output = process.stdout.read()
    if output:
        logger.debug(output.rstrip("\n"))
        outputs += output

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

    # The feature is supposed to be "ostree, rpm(todo), secure boot, ima(todo)"
    for feature in ['ostree', 'grub']:
        if feature not in gpg_data:
            continue

        if feature == 'ostree':
            gpgkey = os.path.expandvars(gpg_data[feature]['gpgkey'])
            gpgid = gpg_data[feature]['gpgid']
            gpg_password = gpg_data[feature]['gpg_password']
        elif feature == 'grub':
            gpgkey = os.path.expandvars(gpg_data[feature]['BOOT_GPG_KEY'])
            gpgid = gpg_data[feature]['BOOT_GPG_NAME']
            gpg_password = gpg_data[feature]['BOOT_GPG_PASSPHRASE']

        cmd = "gpg --homedir {0} --list-keys {1}".format(gpg_path, gpgid)
        res, output = run_cmd(cmd, shell=True)
        if not res:
            continue

        cmd = "gpg --batch --homedir {0} --passphrase {1} --import {2}".format(gpg_path, gpg_password, gpgkey)
        res, output = run_cmd(cmd, shell=True)
        if res:
            run_cmd_oneshot(cmd)

def boot_sign_cmd(gpgid, gpgpassword, gpgpath, unsign_file):
    if not os.path.exists(os.path.realpath(unsign_file)):
        logger.debug("Sing file %s not exist", unsign_file)
        return 1

    real_file = unsign_file
    if os.path.islink(unsign_file):
        real_file = os.path.realpath(unsign_file)
        remove(unsign_file+".sig")

    remove(real_file+".sig")

    script_cmd = "echo '%s' | gpg  --pinentry-mode loopback --batch \
                      --homedir %s -u %s --detach-sign \
                      --passphrase-fd 0 '%s'" % (gpgpassword,
                                                gpgpath,
                                                gpgid,
                                                real_file)

    res, output = run_cmd(script_cmd, shell=True)
    if res:
        logger.debug("Run script_cmd failed\n%s", script_cmd, output)
        return res

    if os.path.islink(unsign_file):
        run_cmd_oneshot("ln -snf -r %s.sig %s.sig" % (real_file, unsign_file))

    return 0

def get_ostree_wks(ostree_use_ab="1", machine="intel-x86-64"):
    ostree_ab_wks = "ab" if ostree_use_ab=="1" else "noab"
    ostree_arch_wks = "ostree-grub" if machine=="intel-x86-64" or machine=="amd-snowyowl-64" else "ostree-uboot-sd"
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
   logger.debug("Release mount point under %s" % target_rootfs)
   for f in ["/dev/pts", "/dev", "/proc", "/sys"]:
        mountpoint = target_rootfs + f
        cmd = "grep -q %s /proc/mounts && umount -l %s" % (mountpoint, mountpoint)
        run_cmd(cmd, shell=True, print_output=True)

def mount(target_rootfs):
    umount(target_rootfs)
    logger.debug("Create mount point under %s" % target_rootfs)
    for f in ["/dev", "/dev/pts", "/proc", "/sys"]:
        mkdirhier("%s%s" % (target_rootfs, f))
        cmd = "mount -o bind %s %s%s" % (f, target_rootfs, f)
        run_cmd(cmd, shell=True, print_output=True)

def cleanup(image_workdir, ostree_osname):
    rootfs_ota = os.path.join(image_workdir, "rootfs_ota/ostree/deploy/%s/deploy" % ostree_osname)
    if os.path.exists(rootfs_ota):
        run_cmd("chattr -i %s/*" % rootfs_ota, shell=True)

    run_cmd_oneshot("rm -rf %s/rootfs*" % image_workdir)

deb_pattern = re.compile(r"^deb\s+.*(?P<mirror>http://[^\s]+) (?P<distro>[^\s]+) (?P<comps>.*)")
def get_debootstrap_input(package_feeds, debian_distros):
    logger.debug("package_feeds %s" % package_feeds)
    mirror = distro = comps = None
    for url in package_feeds:
        m = deb_pattern.match(url)
        if m:
            mirror = m.group('mirror')
            distro = m.group('distro')
            comps = m.group('comps').split()
            if distro in debian_distros:
                logger.info("Matched: Distro %s, Components %s", distro, comps)
                return mirror, distro, comps

    logger.info("Guessed: Distro %s, Components %s",distro, comps)
    return mirror, distro, comps

def get_mem_size(pkg_type, image_type, extra_file=None):
    size = 0
    if extra_file and os.path.exists(extra_file):
        cmd = "du %s --block-size=MB -s | awk '{print $1}'" % extra_file
        output = subprocess.check_output(cmd, shell=True).decode("utf-8")
        logger.debug("Size of %s(%s) is %s", extra_file, pkg_type, output)

        size = int(output.replace("MB", ""))
        size = 2 * size

    if image_type == "pxe":
        if pkg_type in ["rpm", "deb"]:
            size += 2048
        else:
            size += 4096
    else:
        if pkg_type in ["rpm", "deb"]:
            size += 768
        else:
            size += 2048

    logger.debug("Allocate Memory Size: %d MB", size)

    return str(size)

def get_yocto_var(key):
    if is_sdk():
        yocto_env = os.path.join(sysroot_dir, "pkgdata", DEFAULT_MACHINE, ".yocto_vars.env")
    elif is_build():
        yocto_env = os.path.join(sysroot_dir, "../pkgdata", DEFAULT_MACHINE, ".yocto_vars.env")
    if not os.path.join(yocto_env):
        logger.error("Yocto Env File '%s' not found", yocto_env)
        return None

    try:
        config = configparser.ConfigParser()
        config.read(yocto_env)
        val = config.get('yocto',key)
    except Exception as e:
        logger.error("Get value of %s from %s failed\n%s" % (key, yocto_env, str(e)))
        return None

    logger.debug("Get Yocto Var: %s=%s", key, val)

    return val

def validate_inputyamls(yaml_file, no_validate=False, pykwalify_schemas=None):
    if no_validate:
        logger.info("Do not validate parameters in %s", yaml_file)
        return

    if pykwalify_schemas is None:
        logger.debug("No pykwalify schemas")
        return

    try:
        pykwalify_dir = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], 'usr/share/genimage/data/pykwalify')
        extensions = [os.path.join(pykwalify_dir, 'ext.py')]
        c = Core(source_file=yaml_file, schema_files=pykwalify_schemas, extensions=extensions)
        c.validate(raise_exception=True)
    except Exception as e:
        logger.error("Load %s failed\n%s", yaml_file, e)
        sys.exit(1)

# Parse multiple yamls, return a dict data
def parse_yamls(yaml_files, no_validate=False, pykwalify_schemas=None, quiet=False):
    data = dict()
    for yaml_file in yaml_files:
        if not quiet:
            logger.info("Input YAML File: %s" % yaml_file)
        validate_inputyamls(yaml_file, no_validate, pykwalify_schemas)

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
                if key == "image_type":
                    if 'initramfs' in data[key] and (set(data[key]) - set(['initramfs'])):
                        logger.error("Input YAML File: %s" % yaml_file)
                        logger.error("image type 'initramfs' conflicts with '%s'", ' '.join(list(set(data[key]) - set(['initramfs']))))
                        sys.exit(1)
                    elif 'container' in data[key] and (set(data[key]) - set(['container'])):
                        logger.error("Input YAML File: %s" % yaml_file)
                        logger.error("image type 'container' conflicts with '%s'", ' '.join(list(set(data[key]) - set(['container']))))
                        sys.exit(1)

            # Collect and update each item of dict values
            elif key in ['ostree',
                         'features',
                         'gpg',
                         'wic']:
                for sub_key in d[key]:
                    if data[key].get(sub_key) and data[key][sub_key] != d[key][sub_key]:
                        logger.warn("There are multiple %s->%s: %s vs %s, choose the latter one", key, sub_key, data[key][sub_key], d[key][sub_key])
                    data[key][sub_key] = d[key][sub_key]

            elif key in ['name',
                         'package_type']:
                if data[key] != d[key]:
                    logger.error("Input YAML File: %s" % yaml_file)
                    logger.error("There are multiple %s: %s vs %s, only one is allowed", key, data[key], d[key])
                    sys.exit(1)

            # Except packages, the duplicated param is not allowed
            elif key in data:
                logger.error("There is duplicated '%s' in Yaml File %s", key, yaml_file)
                sys.exit(1)
    return data

def deploy_kickstart_example(pkg_type, outdir):
    native_sysroot = os.environ['OECORE_NATIVE_SYSROOT']
    kickstart_dir = os.path.join(outdir, "kickstart")
    kickstart_src = os.path.join(native_sysroot, 'usr/share/genimage/data/kickstart/lat-installer*.ks')
    cmd = "mkdir -p {0} && cp -f {1} {2}/".format(kickstart_dir, kickstart_src, kickstart_dir)
    run_cmd_oneshot(cmd)

    kickstart_doc_in = os.path.join(native_sysroot, "usr/share/genimage/data/kickstart", "kickstart.README.md.in")
    content = open(kickstart_doc_in, "r").read()
    if pkg_type ==  "external-debian":
        content = content.replace("@PKG_TYPE@", "--pkg-type external-debian")
        content = content.replace("@IMAGE_NAME@", deb_constant.DEFAULT_IMAGE)
    elif pkg_type == "rpm":
        content = content.replace("@PKG_TYPE@", "")
        content = content.replace("@IMAGE_NAME@", constant.DEFAULT_IMAGE)

    kickstart_doc = os.path.join(outdir, "kickstart", "kickstart.README.md")
    with open(kickstart_doc, "w") as f:
        f.write(content)

GRUB_CFG_HEAD = '''\
set default=0
set timeout=5
set color_normal='light-gray/black'
set color_highlight='light-green/blue'

'''

GRUB_CFG_SECURE = '''\
if [ "${boot_part}" = "" ] ; then
  get_efivar -f uint8 -s secured SecureBoot
  if [ "${secured}" = "1" ]; then
    set default=0

    # Enable user authentication to make grub unlockable
    set superusers="%OSTREE_GRUB_USER%"
     password_pbkdf2 %OSTREE_GRUB_USER% %OSTREE_GRUB_PW%
  else
    get_efivar -f uint8 -s unprovisioned SetupMode

    if [ "${unprovisioned}" = "1" ]; then
        set timeout=0

        menuentry "Automatic Certificate Provision" --unrestricted {
            chainloader ${prefix}/LockDown.efi
        }
    else
      set default=0
    fi
  fi
fi
'''

GRUB_CFG_ISO_ENTRY = '''\
menuentry "OSTree Install %NAME%" --unrestricted {
    set fallback=1
    efi-watchdog enable 0 180
    linux /bzImage %BOOT_PARAMS%
    initrd @INITRD@
}
'''

def create_grub_cfg(entries, output_dir, secure_boot='disable', grub_user='', grub_pw_file='', image_type='', grub_cfg_extra='', grub_cfg_entry=None):
    grub_cfg = os.path.join(output_dir, "grub-%s.cfg" % image_type)
    content = GRUB_CFG_HEAD
    if secure_boot == 'enable':
        content += GRUB_CFG_SECURE
        content = content.replace("%OSTREE_GRUB_USER%", grub_user)
        with open(os.path.expandvars(grub_pw_file), "r") as f:
            grub_pw = f.read()
            content = content.replace("%OSTREE_GRUB_PW%", grub_pw)

    if grub_cfg_extra:
        content += grub_cfg_extra

    for entry in entries:
        if image_type in ['iso', 'pxe']:
            entry_content = GRUB_CFG_ISO_ENTRY if grub_cfg_entry is None else grub_cfg_entry
            if image_type == 'iso':
                entry_content = entry_content.replace('@INITRD@', '/initrd')
        else:
            entry_content = ''
        entry_content = entry_content.replace('%BOOT_PARAMS%', entry['boot_params']+" BOOTIF=$net_default_mac")
        entry_content = entry_content.replace('%NAME%', entry['name'])
        content += entry_content

    with open(grub_cfg, 'w') as f:
        f.write(content)

    return grub_cfg


SYSLINUX_CFG_HEAD = '''\
PROMPT 0
TIMEOUT 100

ALLOWOPTIONS 1
SERIAL 0 115200

ui vesamenu.c32
menu title Select kernel options and boot kernel
menu tabmsg Press [Tab] to edit, [Return] to select
DEFAULT %NAME%

'''
SYSLINUX_CFG_ISO_ENTRY = '''
LABEL %NAME%
    menu label ^OSTree Install %NAME%
    kernel /bzImage
    ipappend 2
    append initrd=@INITRD@ %BOOT_PARAMS%
'''

def create_syslinux_cfg(entries, output_dir, syslinux_cfg_entry=None, image_type='pxe'):
    syslinux_cfg = os.path.join(output_dir, "syslinux.cfg")
    content = SYSLINUX_CFG_HEAD

    for entry in entries:
        entry_content = SYSLINUX_CFG_ISO_ENTRY if syslinux_cfg_entry is None else syslinux_cfg_entry
        entry_content = entry_content.replace('%BOOT_PARAMS%', entry['boot_params'])
        entry_content = entry_content.replace('%NAME%', entry['name'])
        if image_type == 'iso':
            entry_content = entry_content.replace('@INITRD@', '/initrd')
        content += entry_content

    with open(syslinux_cfg, 'w') as f:
        f.write(content)

    return syslinux_cfg

def replace_str_in_file(old_str, new_str, src_file, dst_file=None):
    if not old_str:
        logger.error("old_str is not set")
        return False
    if not new_str:
        logger.error("new_str is not set")
        return False
    if not src_file:
        logger.error("No src file specified")
        return False
    if not os.path.exists(src_file):
        logger.error("The src file %s does not exist", src_file)
        return False

    if dst_file is None:
        dst_file = src_file

    try:
        with open(src_file, "r") as f:
            content = f.read()
    except Exception as e:
        logger.error("Read %s failed\n%s" % (src_file, e))
        return False

    content = content.replace(old_str, new_str)

    try:
        with open(dst_file, "w") as f:
            f.write(content)
    except Exception as e:
        logger.error("Write %s failed\n%s" % (dst_file, e))
        return False

    return True
