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
import os.path
import logging
logger = logging.getLogger('appsdk')

def ext_file_exists(value, rule_obj, path):
    if value.startswith("http:") or value.startswith("https:") or value.startswith("ftp:"):
        return True

    if "sub_deploy/deploy" in value:
        return True

    if not os.path.exists(value):
        logger.error("'%s' does not exist", value)
        if "exampleyamls/" in value:
            logger.error("Please run `appsdk exampleyamls' first!!!")
        logger.error("path: %s", path)
        return False

    return True
