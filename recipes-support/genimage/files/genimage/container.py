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
import subprocess
import os
import os.path
import logging

from genimage import utils
from genimage.image import Image
from genimage.constant import DEFAULT_OCI_CONTAINER_DATA

logger = logging.getLogger('appsdk')

class CreateContainer(Image):
    def _set_allow_keys(self):
        self.allowed_keys.update({'container_oci'})

    def _add_keys(self):
        self.date = utils.get_today()
        self.image_fullname = "%s-%s-%s" % (self.image_name, self.machine, self.date)
        self.image_linkname =  "%s-%s" % (self.image_name, self.machine)

    def _create_oci(self):
        ota_env = os.environ.copy()
        ota_env['DEPLOY_DIR_IMAGE'] = self.deploydir
        ota_env['IMAGE_NAME'] = self.image_linkname
        ota_env['IMAGE_NAME_SUFFIX'] = '.rootfs'
        ota_env['MACHINE'] = self.machine
        for k in self.container_oci:
            ota_env[k] = self.container_oci[k]

        cmd = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/scripts/run.do_image_oci")
        res, output = utils.run_cmd(cmd, env=ota_env)
        if res:
            raise Exception("Executing %s failed\nExit code %d. Output:\n%s"
                               % (cmd, res, output))

    def _write_load_run_container_yaml(self):
        src = os.path.expandvars("$OECORE_NATIVE_SYSROOT/usr/share/genimage/data/yaml_template/startup-container.yaml.in")
        image_name = "{0}-{1}".format(self.image_name, self.machine)
        yaml_file = os.path.join(self.deploydir, "{0}.startup-container.yaml".format(image_name))

        with open(src, "r") as src_f:
            content = src_f.read()
            content = content.replace("@IMAGE_NAME@", image_name)

        with open(yaml_file, "w") as yaml_file_f:
            yaml_file_f.write(content)

    def create(self):
        self._write_readme("container")

        cmd = "rm -rf {0}.rootfs-oci".format(self.image_linkname)
        utils.run_cmd_oneshot(cmd, cwd=self.deploydir)

        self._create_oci()

        cmd = "skopeo copy oci:{0}.rootfs-oci docker-archive:{1}.docker-image.tar.bz2:{2}".format(self.image_linkname, self.image_fullname, self.image_linkname)
        utils.run_cmd_oneshot(cmd, cwd=self.deploydir)

        self._write_load_run_container_yaml()

        self._create_symlinks()

    def _create_symlinks(self):
        container_dst = os.path.join(self.deploydir, self.image_linkname + ".docker-image.tar.bz2")
        container_src = os.path.join(self.deploydir, self.image_fullname + ".docker-image.tar.bz2")

        for dst, src in [(container_dst, container_src)]:

            if os.path.exists(src):
                logger.debug("Creating symlink: %s -> %s" % (dst, src))
                utils.resymlink(os.path.basename(src), dst)
            else:
                logger.error("Skipping symlink, source does not exist: %s -> %s" % (dst, src))
