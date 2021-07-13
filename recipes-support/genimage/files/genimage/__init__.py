#!/usr/bin/env python3
#
# Copyright (C) 2020 Wind River Systems, Inc.
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

import os.path
import sys
if sys.argv[0].endswith('.real'):
    sys.argv[0] = sys.argv[0][:-5]

import glob
from genimage.constant import DEFAULT_MACHINE

def add_path():
    basepath = os.path.abspath(os.path.dirname(__file__) + '/../../../../..')
    pathlist = "usr/bin/crossscripts usr/bin usr/sbin bin sbin"
    for path in pathlist.split():
        newpath = os.path.join(basepath, path)
        os.environ['PATH'] = newpath + ":" + os.environ['PATH']

    if 'OECORE_NATIVE_SYSROOT' not in os.environ:
        os.environ['OECORE_NATIVE_SYSROOT'] = basepath

    if 'OECORE_TARGET_SYSROOT' not in os.environ:
        basepath = os.path.abspath(basepath + "/..")
        os.environ['OECORE_TARGET_SYSROOT'] = os.path.join(basepath,  DEFAULT_MACHINE)

add_path()

from genimage.genimage import set_subparser
from genimage.genyaml import set_subparser_genyaml
from genimage.exampleyamls import set_subparser_exampleyamls
from genimage.geninitramfs import set_subparser_geninitramfs
from genimage.gencontainer import set_subparser_gencontainer

from genimage.genimage import main
from genimage.genyaml import main_genyaml
from genimage.exampleyamls import main_exampleyamls
from genimage.geninitramfs import main_geninitramfs
from genimage.gencontainer import main_gencontainer

__all__ = [
    "set_subparser",
    "set_subparser_exampleyamls",
    "set_subparser_genyaml",
    "set_subparser_geninitramfs",
    "set_subparser_gencontainer",
    "main",
    "main_exampleyamls",
    "main_genyaml",
    "main_geninitramfs",
    "main_gencontainer",
]


