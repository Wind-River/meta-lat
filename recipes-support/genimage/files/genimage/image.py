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
from abc import ABCMeta, abstractmethod
import subprocess
import os
import os.path
import logging
import shutil
from tempfile import NamedTemporaryFile

from genimage import utils
from genimage import constant
import genimage.debian_constant as deb_constant

logger = logging.getLogger('appsdk')

OVMF_ISO_EFI_SECURE_EXTRA = '''
Automatic Certificate Provision to OVMF images
    $ qemu-system-x86_64 -net nic -net user -m @MEM@ \\
        -drive if=none,id=hd,file=boot-image-qemu.hddimg,format=raw \\
        -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd \\
        -cdrom ./deploy/@IMAGE_NAME@-cd.iso \\
        -cpu Nehalem \\
        -drive if=pflash,format=qcow2,file=OVMF_CODE.fd \\
        -drive if=pflash,format=qcow2,file=OVMF_VARS.fd \\
        -no-reboot
'''

class Image(object, metaclass=ABCMeta):
    """
    This is an abstract class. Do not instantiate this directly.
    """
    def __init__(self, **kwargs):
        self.allowed_keys = {'image_name', 'workdir', 'machine', 'target_rootfs', 'deploydir', 'pkg_type'}
        self._set_allow_keys()

        for k, v in kwargs.items():
            if k not in self.allowed_keys:
                raise Exception("Init parameters %s not defined, call _set_allow_keys to define" % k)

        # Initial allowed keys
        self.__dict__.update({k: "" for k in self.allowed_keys})

        # Update keys from input
        self.__dict__.update((k, v) for k, v in kwargs.items() if k in self.allowed_keys)

        # Add internal(not from input) keys
        self._add_keys()

    def _set_allow_keys(self):
        pass

    def _add_keys(self):
        pass

    @abstractmethod
    def create(self):
        pass

    def _write_readme(self, image_type=None):
        image_type_suffix = {
            "container": ".container",
            "ustart": ".ustart.img.gz",
            "wic": ".wic",
            "iso": "-cd.iso"
        }
        if image_type is None or image_type not in image_type_suffix:
            return

        if image_type == "container":
            src = os.path.join(os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/doc"),
                "container.README.md.in")
        elif self.machine != "bcm-2xxx-rpi4" and self.machine in constant.SUPPORTED_ARM_MACHINES:
            src = os.path.join(os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/doc"),
                "target_{0}.README.md.in".format(self.machine))
        else:
            src = os.path.join(os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/doc"),
                "{0}_{1}.README.md.in".format(image_type, self.machine))

        if not os.path.exists(src):
            logger.error("%s not exist", src)
            return

        image_name = "{0}-{1}".format(self.image_name, self.machine)
        readme = os.path.join(self.deploydir, "{0}{1}.README.md".format(image_name, image_type_suffix[image_type]))

        with open(src, "r") as src_f:
            content = src_f.read()
            content = self._edit_readme_content(content)
            content = content.replace("@IMAGE_NAME@", image_name)
            content = content.replace("@PACKAGE_MANAGER_SECTION@", constant.PACKAGE_MANAGER_SECTION[self.pkg_type])
            content = content.replace("@MEM@", utils.get_mem_size(self.pkg_type, image_type))
            if image_type == "ustart":
                burn_cmd = "zcat deploy/%s.ustart.img.gz | sudo dd of=/dev/sdX bs=1M status=progress" % image_name
                content = content.replace("@BURN_COMMAND@", burn_cmd)
            elif image_type == "wic":
                burn_cmd = "sudo dd if=deploy/%s.wic of=/dev/sdX bs=1M status=progress" % image_name
                content = content.replace("@BURN_COMMAND@", burn_cmd)

        with open(readme, "w") as readme_f:
            readme_f.write(content)

    def _edit_readme_content(self, content):
        if self.machine == "intel-x86-64":
            ovmf_code = "ovmf.secboot.qcow2" if os.environ.get('EFI_SECURE_BOOT', 'disable') == 'enable'  else "ovmf.qcow2"
            content = content.replace("@ovmf_code@", ovmf_code)
            ovmf_iso_extra = OVMF_ISO_EFI_SECURE_EXTRA if os.environ.get('EFI_SECURE_BOOT', 'disable') == 'enable'  else ""
            content = content.replace("@OVMF_ISO_EXTRA@", ovmf_iso_extra)

        return content


class CreateInitramfs(Image):
    def _add_keys(self):
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)

    def create(self):
        self._create_cpio_gz()
        if self.machine in constant.SUPPORTED_ARM_MACHINES:
            self._create_uboot()
        self._create_symlinks()

    def _create_uboot(self):
        arch = "arm64"
        if self.machine in constant.SUPPORTED_ARM32_MACHINES:
            arch = "arm"
        extra_args = ""
        if self.machine == "marvell-cn96xx":
            extra_args = "-f auto"
        cmd = "cd %s && mkimage %s -A %s -O linux -T ramdisk -C none -n %s -d %s.rootfs.cpio.gz %s.rootfs.cpio.gz.u-boot" % \
             (self.deploydir, extra_args, arch, self.image_fullname, self.image_fullname, self.image_fullname)
        utils.run_cmd_oneshot(cmd)

        cmd = "rm %s/%s.rootfs.cpio.gz" % (self.deploydir, self.image_fullname)
        utils.run_cmd_oneshot(cmd)

    def _create_cpio_gz(self):
        cmd = "cd %s && find . | sort | cpio --reproducible -o -H newc > %s/%s.rootfs.cpio" % \
             (self.target_rootfs, self.deploydir, self.image_fullname)
        utils.run_cmd_oneshot(cmd)

        cmd = "cd %s && pigz -f -9 -n -c --rsyncable %s.rootfs.cpio > %s.rootfs.cpio.gz && rm %s.rootfs.cpio" % \
            (self.deploydir, self.image_fullname, self.image_fullname, self.image_fullname)
        utils.run_cmd_oneshot(cmd)

    def _create_symlinks(self):
        dst = os.path.join(self.deploydir, self.image_linkname + ".cpio.gz")
        src = os.path.join(self.deploydir, self.image_fullname + ".rootfs.cpio.gz")
        if self.machine in constant.SUPPORTED_ARM_MACHINES:
            dst = dst + ".u-boot"
            src = src + ".u-boot"

        if os.path.exists(src):
            logger.debug("Creating symlink: %s -> %s" % (dst, src))
            utils.resymlink(os.path.basename(src), dst)
        else:
            logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))


class CreateWicImage(Image):
    def _set_allow_keys(self):
        self.allowed_keys.update({"wks_file", "pre_script", "post_script"})

    def _add_keys(self):
        self.wks_full_path = ""
        self.wks_in_environ = os.environ.copy()
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)

    def set_wks_in_environ(self, **kwargs):
        for k, v in kwargs.items():
            self.wks_in_environ[k] = v

    def _write_wks_template(self):
        base, ext = os.path.splitext(self.wks_file)
        if ext == '.in' and os.path.exists(self.wks_file):
            env_back = os.environ.copy()
            os.environ = self.wks_in_environ
            wks_content = ""
            with open(self.wks_file, "r") as f:
                wks_content = f.read()
                wks_content = os.path.expandvars(wks_content)
                for e in ['OSTREE_WKS_ROOT_SIZE', 'OSTREE_WKS_FLUX_SIZE']:
                    if e not in os.environ:
                        continue
                    wks_content = wks_content.replace('@%s@'%e, os.environ[e])
            self.wks_full_path = os.path.join(self.deploydir, os.path.basename(base))
            open(self.wks_full_path, "w").write(wks_content)
            os.environ = env_back
        elif os.path.exists(self.wks_file):
            self.wks_full_path = self.wks_file

    def _write_qemuboot_conf(self):
        qemuboot_conf_in = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/qemu_data/qemuboot.conf.in")
        if not os.path.exists(qemuboot_conf_in):
            return

        with open(qemuboot_conf_in, "r") as qemuboot_conf_in_f:
            content = qemuboot_conf_in_f.read()
            content = content.replace("@DEPLOYDIR@", self.deploydir)
            content = content.replace("@IMAGE_LINK_NAME@", self.image_linkname)
            content = content.replace("@IMAGE_NAME@", self.image_fullname)
            content = content.replace("@MEM@", utils.get_mem_size(self.pkg_type, "wic"))

        qemuboot_conf = os.path.join(self.deploydir, "{0}.qemuboot.conf".format(self.image_fullname))
        with open(qemuboot_conf, "w") as qemuboot_conf_f:
            qemuboot_conf_f.write(content)

    def create(self):
        self._write_wks_template()
        self._write_qemuboot_conf()
        self._write_readme("wic")

        wic_env = os.environ.copy()
        wic_env['IMAGE_ROOTFS'] = self.target_rootfs
        wic_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        wic_env['WORKDIR'] = self.workdir
        wic_env['IMAGE_NAME'] = self.image_name
        wic_env['MACHINE'] = self.machine
        wic_env['WKS_FILE'] = self.wks_full_path
        wic_env['DATETIME'] = self.date

        self._pre_wic()


        if 'LD_PRELOAD' in wic_env:
            del wic_env['LD_PRELOAD']
        cmd = os.path.join(wic_env['OECORE_NATIVE_SYSROOT'], "usr/share/genimage/scripts/run.do_image_wic")
        res, output = utils.run_cmd(cmd, env=wic_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))

        self._create_symlinks()

        self._post_wic()

    def _pre_wic(self):
        if not self.pre_script:
            return

        logger.debug("Executing '%s' preprocess script..." % self.pre_script)
        scriptFile = NamedTemporaryFile(delete=True, dir=".")
        with open(scriptFile.name, 'w') as f:
            f.write("#!/usr/bin/env bash\n")
            f.write(self.pre_script + "\n")
        os.chmod(scriptFile.name, 0o777)
        scriptFile.file.close()

        wic_env = os.environ.copy()
        wic_env['IMAGE_ROOTFS'] = self.target_rootfs
        wic_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        wic_env['WORKDIR'] = self.workdir
        wic_env['IMAGE_NAME'] = self.image_name
        wic_env['MACHINE'] = self.machine
        wic_env['DATETIME'] = self.date
        res, output = utils.run_cmd(scriptFile.name, shell=True, env=wic_env)
        if res:
            raise Exception("Executing %s preprocess wic failed\nExit code %d. Output:\n%s"
                               % (self.pre_script, res, output))

    def _post_wic(self):
        if not self.post_script:
            return

        logger.debug("Executing '%s' postprocess script..." % self.post_script)
        scriptFile = NamedTemporaryFile(delete=True, dir=".")
        with open(scriptFile.name, 'w') as f:
            f.write("#!/usr/bin/env bash\n")
            f.write(self.post_script + "\n")
        os.chmod(scriptFile.name, 0o777)
        scriptFile.file.close()

        wic_env = os.environ.copy()
        wic_env['IMAGE_ROOTFS'] = self.target_rootfs
        wic_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        wic_env['WORKDIR'] = self.workdir
        wic_env['IMAGE_NAME'] = self.image_name
        wic_env['MACHINE'] = self.machine
        wic_env['DATETIME'] = self.date
        res, output = utils.run_cmd(scriptFile.name, shell=True, env=wic_env)
        if res:
            raise Exception("Executing %s postprocess wic failed\nExit code %d. Output:\n%s"
                               % (self.post_script, res, output))

    def _create_symlinks(self):
        for suffix_dst, suffix_src in [(".wic", ".rootfs.wic"),
                                       (".wic.bmap", ".rootfs.wic.bmap"),
                                       (".qemuboot.conf", ".qemuboot.conf")]:
            dst = os.path.join(self.deploydir, self.image_linkname + suffix_dst)
            src = os.path.join(self.deploydir, self.image_fullname + suffix_src)
            if os.path.exists(src):
                logger.debug("Creating symlink: %s -> %s" % (dst, src))
                utils.resymlink(os.path.basename(src), dst)
            else:
                if suffix_dst != ".qemuboot.conf":
                    logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))


class CreateISOImage(Image):
    def set_wks_in_environ(self, **kwargs):
        for k, v in kwargs.items():
            self.wks_in_environ[k] = v

    def _set_allow_keys(self):
        self.allowed_keys.update({"iso_post_script"})

    def _add_keys(self):
        self.wks_full_path = ""
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)
        self.wks_file = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], "usr/share/genimage/data/wic/mkhybridiso.wks.in")
        self.wks_in_environ = os.environ.copy()

    def _write_wks_template(self):
        source_params = "loader=grub-efi,image_name=%s," % self.image_fullname
        if 'instl=/ostree_repo' in self.wks_in_environ['BOOT_PARAMS']:
            source_params += "payload_dir=%s/ostree_repo,dest_dir=ostree_repo," % self.deploydir

        if self.iso_post_script and os.path.exists(self.iso_post_script):
            source_params += "iso_post_script=%s," % self.iso_post_script

        if self.pkg_type == "external-debian" :
            source_params += "initrd=%s-%s.cpio.gz" % (deb_constant.DEFAULT_INITRD_NAME, self.machine)
        else:
            source_params += "initrd=%s-%s.cpio.gz" % (constant.DEFAULT_INITRD_NAME, self.machine)

        base, ext = os.path.splitext(self.wks_file)
        if ext == '.in' and os.path.exists(self.wks_file):
            env_back = os.environ.copy()
            os.environ = self.wks_in_environ
            wks_content = ""
            with open(self.wks_file, "r") as f:
                wks_content = f.read()
                wks_content = os.path.expandvars(wks_content)
                wks_content = wks_content.replace('@SOURCE_PARAMS@', source_params)
            self.wks_full_path = os.path.join(self.workdir, os.path.basename(base))
            open(self.wks_full_path, "w").write(wks_content)
            os.environ = env_back
        elif os.path.exists(self.wks_file):
            self.wks_full_path = self.wks_file

    def create(self):
        self._write_wks_template()
        self._write_readme("iso")

        iso_env = os.environ.copy()
        # No real rootfs for iso image
        iso_env['IMAGE_ROOTFS'] = self.target_rootfs
        iso_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        iso_env['STAGING_DATADIR'] = os.path.join(iso_env['OECORE_TARGET_SYSROOT'], "usr/share")
        iso_env['FAKEROOTCMD'] = os.path.join(iso_env['OECORE_NATIVE_SYSROOT'], "usr/bin/pseudo")
        iso_env['RECIPE_SYSROOT_NATIVE'] = iso_env['OECORE_NATIVE_SYSROOT']
        iso_env['EFI_SECURE_BOOT'] = iso_env.get('EFI_SECURE_BOOT', 'disable')
        iso_env['IMAGE_NAME'] = self.image_name

        if 'LD_PRELOAD' in iso_env:
            del iso_env['LD_PRELOAD']
        cmd = "wic create --debug --image-name {0} {1}".format(self.image_name, self.wks_full_path)
        res, output = utils.run_cmd(cmd, shell=True, cwd=self.workdir, env=iso_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))

        self._rename_and_symlink()

    def _rename_and_symlink(self):
        for suffix_dst, suffix_src in [("-cd.iso", "-cd.iso")]:
            old = os.path.join(self.workdir, self.image_fullname + suffix_dst)
            new = os.path.join(self.deploydir, self.image_fullname + suffix_dst)
            logger.debug("Rename: %s -> %s" % (old, new))
            os.rename(old, new)

            dst = os.path.join(self.deploydir, self.image_linkname + suffix_dst)
            src = os.path.join(self.deploydir, self.image_fullname + suffix_src)
            if os.path.exists(src):
                logger.debug("Creating symlink: %s -> %s" % (dst, src))
                utils.resymlink(os.path.basename(src), dst)
            else:
                logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))

class CreatePXE(Image):
    def _set_allow_keys(self):
        self.allowed_keys = {'image_name',
                             'deploydir',
                             'machine',
                             'pkg_type',
                             'pxe_initrd_name',
                             'pxe_rootfs',
                             'grub_cfg',
                             'syslinux_cfg',
                             'gpgid',
                             'gpgpassword',
                             'gpgpath'}

    def _add_keys(self):
        self.wks_full_path = ""
        self.date = utils.get_today()
        self.image_fullname = "pxe-tftp-%s-%s" % (self.image_name, self.date)
        self.image_linkname = "pxe-tftp-%s" % (self.image_name)
        self.tftp_dir = os.path.join(self.deploydir, "pxe_tftp_%s" % self.image_name)
        self.pxe_initrd = "{0}/{1}.cpio.gz".format(self.tftp_dir, self.pxe_initrd_name)

    def _create_pxe_cpio_gz(self):
        cmd = "cd %s && find . | sort | cpio --reproducible -o -H newc > %s/%s.cpio" % \
             (self.pxe_rootfs, self.tftp_dir, self.pxe_initrd_name)
        utils.run_cmd_oneshot(cmd)

        cmd = "cd %s && pigz -f -9 -n -c --rsyncable %s.cpio > %s.cpio.gz && rm %s.cpio" % \
            (self.tftp_dir, self.pxe_initrd_name, self.pxe_initrd_name, self.pxe_initrd_name)
        utils.run_cmd_oneshot(cmd)

    def create(self):
        utils.run_cmd_oneshot("rm %s -rf" % (self.tftp_dir))
        os.umask(0)
        os.makedirs(os.path.join(self.tftp_dir, "EFI/BOOT"), 0o777)
        os.makedirs(os.path.join(self.tftp_dir, "pxelinux.cfg"), 0o777)

        self._create_pxe_cpio_gz()

        utils.run_cmd_oneshot("install -m 0644 %s %s/EFI/BOOT/grub.cfg" % (self.grub_cfg, self.tftp_dir))

        utils.run_cmd_oneshot("install -m 0644 %s/bzImage* %s/" % (self.deploydir, self.tftp_dir))

        for f in ["libcom32.c32", "ldlinux.c32", "libutil.c32", "vesamenu.c32", "pxelinux.0"]:
            s = os.path.join(os.environ['OECORE_TARGET_SYSROOT'], "usr/share/syslinux", f)
            d = os.path.join(self.tftp_dir, f)
            shutil.copyfile(s, d)

        utils.run_cmd_oneshot("install -m 0644 %s %s/pxelinux.cfg/default" % (self.syslinux_cfg, self.tftp_dir))
        utils.run_cmd_oneshot("install -m 0644 %s/*.efi* %s/EFI/BOOT/" % (self.deploydir, self.tftp_dir))

        for bootfile in ["pxelinux.cfg/default", "EFI/BOOT/grub.cfg"]:
            bootfile = os.path.join(self.tftp_dir, bootfile)
            with open(bootfile, "r") as f:
                content = f.read()
                content = content.replace("@INITRD@", os.path.basename(self.pxe_initrd))
            with open(bootfile, "w") as f:
                f.write(content)

        if os.environ.get('EFI_SECURE_BOOT', 'disable') == 'enable':
            # Sign pxe initrd
            utils.boot_sign_cmd(self.gpgid, self.gpgpassword, self.gpgpath, self.pxe_initrd)

            # Sign grub.cfg
            utils.boot_sign_cmd(self.gpgid, self.gpgpassword, self.gpgpath, "%s/EFI/BOOT/grub.cfg"%self.tftp_dir)

            # On some host, PXE searches grubx64.efi from tftp/ dir rather than tftp/EFI/BOOT/
            utils.run_cmd_oneshot("install -m 0644 %s/grubx64.efi %s/" % (self.deploydir, self.tftp_dir))

        self._write_readme()

        self._create_tar()

    def _write_readme(self):
        for (dst_prefix, src) in [("PXE-for-EFI", "pxe-efi_intel-x86-64.README.md.in"),
                           ("PXE-for-Legacy", "pxe-bios_intel-x86-64.README.md.in")]:
            src = os.path.join(os.environ['OECORE_NATIVE_SYSROOT'], "usr/share/genimage/doc", src)
            with open(src, "r") as src_f:
                content = src_f.read()
                content = self._edit_readme_content(content)
                content = content.replace("@IMAGE_NAME@", self.image_name)
                content = content.replace("@PACKAGE_MANAGER_SECTION@", constant.PACKAGE_MANAGER_SECTION[self.pkg_type])
                ostree_repo = os.path.join(self.deploydir, "ostree_repo")
                content = content.replace("@MEM@", utils.get_mem_size(self.pkg_type, "pxe", ostree_repo))

            dst = os.path.join(self.deploydir, "%s_%s.README.md" % (dst_prefix, self.image_name))
            with open(dst, "w") as readme_f:
                readme_f.write(content)

    def _create_tar(self):
        cmd = "tar -cvf %s.tar %s" % (self.image_fullname, os.path.basename(self.tftp_dir))
        utils.run_cmd_oneshot(cmd, cwd=self.deploydir)
        self._rename_and_symlink()

    def _rename_and_symlink(self):
        for suffix_dst, suffix_src in [(".tar", ".tar")]:
            old = os.path.join(self.deploydir, self.image_fullname + suffix_dst)
            new = os.path.join(self.deploydir, self.image_fullname + suffix_dst)
            logger.debug("Rename: %s -> %s" % (old, new))
            os.rename(old, new)

            dst = os.path.join(self.deploydir, self.image_linkname + suffix_dst)
            src = os.path.join(self.deploydir, self.image_fullname + suffix_src)
            if os.path.exists(src):
                logger.debug("Creating symlink: %s -> %s" % (dst, src))
                utils.resymlink(os.path.basename(src), dst)
            else:
                logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))


class CreateVMImage(Image):
    def _set_allow_keys(self):
        self.allowed_keys = {'image_name', 'machine', 'deploydir', 'vm_type', 'pkg_type'}

    def _add_keys(self):
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)

    def create(self):
        vm_env = os.environ.copy()
        if 'LD_PRELOAD' in vm_env:
            del vm_env['LD_PRELOAD']
        img = os.path.join(self.deploydir, "{0}.rootfs.wic".format(self.image_fullname))
        cmd = "qemu-img convert -O {0} {1} {2}.{3}".format(self.vm_type, img, img, self.vm_type)
        utils.run_cmd(cmd, shell=True, env=vm_env)

        self._create_symlinks()

    def _create_symlinks(self):
        dst = os.path.join(self.deploydir, "{0}.wic.{1}".format(self.image_linkname, self.vm_type))
        src = os.path.join(self.deploydir, "{0}.rootfs.wic.{1}".format(self.image_fullname, self.vm_type))
        if os.path.exists(src):
            logger.debug("Creating symlink: %s -> %s" % (dst, src))
            utils.resymlink(os.path.basename(src), dst)
        else:
            logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))


class CreateOstreeRepo(Image):
    def _set_allow_keys(self):
        self.allowed_keys.update({"gpgid", "gpg_password", "gpg_path", "image_manifest", "ostree_branchname"})

    def _add_keys(self):
        self.ostree_kernel = constant.OSTREE_KERNEL
        self.use_fit = '0'

    def set_fit(self, ostree_kernel='fitimage', use_fit='1'):
        self.ostree_kernel = ostree_kernel
        self.use_fit = use_fit

    def create(self):
        ostreerepo_env = os.environ.copy()
        ostreerepo_env['IMAGE_ROOTFS'] = self.target_rootfs
        ostreerepo_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        ostreerepo_env['WORKDIR'] = self.workdir
        ostreerepo_env['IMAGE_NAME'] = self.image_name
        ostreerepo_env['MACHINE'] = self.machine

        ostreerepo_env['OSTREE_GPGID'] = self.gpgid
        ostreerepo_env['OSTREE_GPG_PASSPHRASE'] = self.gpg_password
        ostreerepo_env['GPGPATH'] = self.gpg_path

        ostreerepo_env['USE_FIT'] = self.use_fit
        ostreerepo_env['OSTREE_KERNEL'] = self.ostree_kernel
        ostreerepo_env['RAMDISK_EXT'] = constant.RAMDISK_EXT
        ostreerepo_env['KERNEL_DEVICETREE'] = constant.KERNEL_DEVICETREE
        ostreerepo_env['APP_DIRECTORY'] = constant.APP_DIRECTORY

        if self.ostree_branchname:
            ostreerepo_env['OSTREE_BRANCHNAME'] = self.ostree_branchname

        if self.image_manifest:
            ostreerepo_env['MANIFEST'] = self.image_manifest

        cmd = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/scripts/run.do_image_ostree")
        res, output = utils.run_cmd(cmd, env=ostreerepo_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))

    def gen_env(self, data):
        env = {
            'FAKEROOTCMD': '$OECORE_NATIVE_SYSROOT/usr/bin/pseudo',
            'RECIPE_SYSROOT_NATIVE': '$OECORE_NATIVE_SYSROOT',
            'DEPLOY_DIR_IMAGE': self.deploydir,
            'OSTREE_USE_AB': data['ostree']['ostree_use_ab'],
            'OSTREE_REMOTE_URL': data['ostree']['ostree_remote_url'],
            'OSTREE_FLUX_PART': data['wic']['OSTREE_FLUX_PART'],
            'OSTREE_GRUB_USER': data['ostree']['OSTREE_GRUB_USER'],
            'OSTREE_GRUB_PW_FILE': data['ostree']['OSTREE_GRUB_PW_FILE'],
            'OSTREE_FDISK_BLM': data['ostree']['OSTREE_FDISK_BLM'],
            'OSTREE_FDISK_FSZ': data['ostree']['OSTREE_FDISK_FSZ'],
            'OSTREE_FDISK_BSZ': data['ostree']['OSTREE_FDISK_BSZ'],
            'OSTREE_FDISK_RSZ': data['ostree']['OSTREE_FDISK_RSZ'],
            'OSTREE_FDISK_VSZ': data['ostree']['OSTREE_FDISK_VSZ'],
            'OSTREE_CONSOLE': data['ostree']['OSTREE_CONSOLE'],
            'IMAGE_BOOT_FILES': '{0} {1}'.format(constant.IMAGE_BOOT_FILES, constant.EXTRA_IMAGE_BOOT_FILES[self.machine]),
            'IMAGE_BASENAME': self.image_name,
            'BOOT_GPG_NAME': data['gpg']['grub']['BOOT_GPG_NAME'],
            'BOOT_GPG_PASSPHRASE': data['gpg']['grub']['BOOT_GPG_PASSPHRASE'],
            'BOOT_KEYS_DIR': data['gpg']['grub']['BOOT_KEYS_DIR'],
            'DISTRO_FEATURES': 'efi-secure-boot' if os.environ.get('EFI_SECURE_BOOT') else '',
        }
        env_file = os.path.join(self.deploydir, '{0}-{1}.env'.format(self.image_name, self.machine))
        with open(env_file, 'w') as f:
            f.writelines('{}="{}"\n'.format(k,v) for k, v in env.items())


class CreateExtDebOstreeRepo(CreateOstreeRepo):
    def gen_env(self, data):
        env = {
            'RECIPE_SYSROOT_NATIVE': '$OECORE_NATIVE_SYSROOT',
            'DEPLOY_DIR_IMAGE': self.deploydir,
            'OSTREE_USE_AB': data['ostree']['ostree_use_ab'],
            'OSTREE_REMOTE_URL': data['ostree']['ostree_remote_url'],
            'OSTREE_FLUX_PART': data['wic']['OSTREE_FLUX_PART'],
            'OSTREE_INITRD': deb_constant.DEFAULT_INITRD_NAME,
            'OSTREE_GRUB_USER': data['ostree']['OSTREE_GRUB_USER'],
            'OSTREE_GRUB_PW_FILE': data['ostree']['OSTREE_GRUB_PW_FILE'],
            'OSTREE_FDISK_BLM': data['ostree']['OSTREE_FDISK_BLM'],
            'OSTREE_FDISK_FSZ': data['ostree']['OSTREE_FDISK_FSZ'],
            'OSTREE_FDISK_BSZ': data['ostree']['OSTREE_FDISK_BSZ'],
            'OSTREE_FDISK_RSZ': data['ostree']['OSTREE_FDISK_RSZ'],
            'OSTREE_FDISK_VSZ': data['ostree']['OSTREE_FDISK_VSZ'],
            'OSTREE_CONSOLE': data['ostree']['OSTREE_CONSOLE'],
            'IMAGE_BOOT_FILES': '{0} {1}'.format(constant.IMAGE_BOOT_FILES, constant.EXTRA_IMAGE_BOOT_FILES[self.machine]),
            'IMAGE_BASENAME': self.image_name,
            'BOOT_GPG_NAME': data['gpg']['grub']['BOOT_GPG_NAME'],
            'BOOT_GPG_PASSPHRASE': data['gpg']['grub']['BOOT_GPG_PASSPHRASE'],
            'BOOT_KEYS_DIR': data['gpg']['grub']['BOOT_KEYS_DIR'],
            'DISTRO_FEATURES': 'efi-secure-boot' if os.environ.get('EFI_SECURE_BOOT') else '',
        }
        env_file = os.path.join(self.deploydir, '{0}-{1}.env'.format(self.image_name, self.machine))
        with open(env_file, 'w') as f:
            f.writelines('{}="{}"\n'.format(k,v) for k, v in env.items())


class CreateOstreeOTA(Image):
    def _set_allow_keys(self):
        self.allowed_keys.remove('target_rootfs')
        self.allowed_keys.update({'gpgid',
                                  'ostree_use_ab',
                                  'ostree_osname',
                                  'ostree_branchname',
                                  'ostree_skip_boot_diff',
                                  'ostree_remote_url'
                                 })

    def _add_keys(self):
        self.image_boot_files = constant.IMAGE_BOOT_FILES
        self.use_fit = '0'


    def set_fit(self, boot_files='', use_fit='1'):
        self.use_fit = use_fit
        self.image_boot_files = boot_files

    def create(self):
        ota_env = os.environ.copy()
        ota_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        ota_env['WORKDIR'] = self.workdir
        ota_env['IMAGE_NAME'] = self.image_name
        ota_env['MACHINE'] = self.machine

        ota_env['OSTREE_GPGID'] = self.gpgid
        ota_env['OSTREE_USE_AB'] = self.ostree_use_ab
        ota_env['OSTREE_OSNAME'] = self.ostree_osname
        ota_env['OSTREE_SKIP_BOOT_DIFF'] = self.ostree_skip_boot_diff
        ota_env['OSTREE_REMOTE_URL'] = self.ostree_remote_url
        ota_env['IMAGE_BOOT_FILES'] = self.image_boot_files
        ota_env['OSTREE_COPY_IMAGE_BOOT_FILES'] = constant.OSTREE_COPY_IMAGE_BOOT_FILES
        ota_env['USE_FIT'] = self.use_fit
        ota_env['APP_DIRECTORY'] = constant.APP_DIRECTORY

        if self.ostree_branchname:
            ota_env['OSTREE_BRANCHNAME'] = self.ostree_branchname

        cmd = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/scripts/run.do_image_otaimg")
        res, output = utils.run_cmd(cmd, env=ota_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))


class CreateBootfs(Image):
    def _set_allow_keys(self):
        self.allowed_keys.remove('target_rootfs')
        self.allowed_keys.update({'ostree_osname', 'boot_params', 'post_script', 'bootfs_params'})

    def _add_keys(self):
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)

    def create(self):
        self._write_readme("ustart")

        ustart_env = os.environ.copy()
        ustart_env['OSTREE_OSNAME'] = self.ostree_osname
        if 'LD_PRELOAD' in ustart_env:
            del ustart_env['LD_PRELOAD']
        cmd = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/bin/bootfs.sh")
        cmd = "{0} -e {1}/{2}-{3}.env -a '{4}' {5}".format(cmd, self.deploydir, self.image_name, self.machine, self.boot_params, self.bootfs_params)
        res, output = utils.run_cmd(cmd, shell=True, cwd=self.workdir, env=ustart_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))

        self._rename_and_symlink()

        self._post_ustart()

    def _post_ustart(self):
        if not self.post_script:
            return

        logger.debug("Executing '%s' postprocess script..." % self.post_script)
        scriptFile = NamedTemporaryFile(delete=True, dir=".")
        with open(scriptFile.name, 'w') as f:
            f.write("#!/usr/bin/env bash\n")
            f.write(self.post_script + "\n")
        os.chmod(scriptFile.name, 0o777)
        scriptFile.file.close()

        ustart_env = os.environ.copy()
        ustart_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        ustart_env['WORKDIR'] = self.workdir
        ustart_env['IMAGE_NAME'] = self.image_name
        ustart_env['MACHINE'] = self.machine
        ustart_env['DATETIME'] = self.date
        res, output = utils.run_cmd(scriptFile.name, shell=True, env=ustart_env)
        if res:
            raise Exception("Executing %s postprocess ustart failed\nExit code %d. Output:\n%s"
                               % (self.post_script, res, output))

    def _rename_and_symlink(self):
        for suffix in ["ustart.img.gz", "ustart.img.bmap"]:
            old = os.path.join(self.workdir, suffix)
            new = os.path.join(self.deploydir, "{0}.{1}".format(self.image_fullname, suffix))
            logger.debug("Rename: %s -> %s" % (old, new))
            os.rename(old, new)

            dst = os.path.join(self.deploydir, "{0}.{1}".format(self.image_linkname, suffix))
            src = os.path.join(self.deploydir, "{0}.{1}".format(self.image_fullname, suffix))
            if os.path.exists(src):
                logger.debug("Creating symlink: %s -> %s" % (dst, src))
                utils.resymlink(os.path.basename(src), dst)
            else:
                logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))
