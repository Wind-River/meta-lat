#!/usr/bin/env python3
# PYTHON_ARGCOMPLETE_OK
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

import sys
if sys.argv[0].endswith('.real'):
    sys.argv[0] = sys.argv[0][:-5]

import os
import glob

def add_path():
    basepath = os.path.abspath(os.path.dirname(__file__) + '/../../../../..')
    pathlist = "usr/bin/crossscripts usr/bin usr/sbin bin sbin"
    for path in pathlist.split():
        newpath = os.path.join(basepath, path)
        os.environ['PATH'] = newpath + ":" + os.environ['PATH']

    if 'OECORE_NATIVE_SYSROOT' not in os.environ:
        os.environ['OECORE_NATIVE_SYSROOT'] = basepath

add_path()

import argparse
import argcomplete
import re
import logging
from appsdk.appsdk import AppSDK
from genimage.utils import set_logger
import genimage.utils as utils
import genimage

logger = logging.getLogger('appsdk')

def set_subparser(subparsers=None):
    if subparsers is None:
        sys.exit(1)

    parser_gensdk = subparsers.add_parser('gensdk', help='Generate a new SDK')
    parser_gensdk.add_argument('-f', '--file',
                               help='An input yaml file specifying image information.',
                               required=True)
    parser_gensdk.add_argument('-o', '--output',
                               help='The path of the generated SDK. Default to deploy/AppSDK.sh in current directory',
                               default='deploy/AppSDK.sh')
    parser_gensdk.set_defaults(func=gensdk)
    
    parser_checksdk = subparsers.add_parser('checksdk', help='Sanity check for SDK')
    parser_checksdk.set_defaults(func=checksdk)

    parser_buildrpm = subparsers.add_parser('genrpm', help='Build RPM package')
    parser_buildrpm.add_argument('-f', '--file', required=True,
                                 help='A yaml or spec file specifying package information')
    parser_buildrpm.add_argument('-i', '--installdir', required=True,
                                 help='An installdir serving as input to generate RPM package')
    parser_buildrpm.add_argument('-o', '--outputdir',
                                 help='Output directory to hold the generated RPM package',
                                 default='deploy/rpms')
    parser_buildrpm.add_argument('--pkgarch',
                                 help='package arch about the generated RPM package', default=None)
    parser_buildrpm.set_defaults(func=buildrpm)

    parser_publishrpm = subparsers.add_parser('publishrpm', help='Publish RPM package')
    parser_publishrpm.add_argument('-r', '--repo', required=True,
                                   help='Local RPM repo path')
    parser_publishrpm.add_argument('rpms', help='RPM package paths',
                                   nargs='*')
    parser_publishrpm.set_defaults(func=publishrpm)

def main():
    parser = argparse.ArgumentParser(
        description='Wind River Linux Assembly Tool',
        epilog='Use %(prog)s <subcommand> --help to get help')
    parser.add_argument('-d', '--debug',
                        help = "Enable debug output",
                        action='store_const', const=logging.DEBUG, dest='loglevel', default=logging.INFO)
    parser.add_argument('-q', '--quiet',
                        help = 'Hide all output except error messages',
                        action='store_const', const=logging.ERROR, dest='loglevel', default=logging.INFO)
    parser.add_argument('--log-dir',
                        default=None,
                        dest='logdir',
                        help='Specify dir to save debug messages as log.appsdk regardless of the logging level',
                        action='store')

    subparsers = parser.add_subparsers(help='Subcommands. "%(prog)s <subcommand> --help" to get more info')

    set_subparser(subparsers)

    # Add genimage to appsdk
    genimage.set_subparser(subparsers)

    # Add geninitramfs to appsdk
    genimage.set_subparser_geninitramfs(subparsers)

    # Add gencontainer to appsdk
    genimage.set_subparser_gencontainer(subparsers)

    # Add genyaml to appsdk
    genimage.set_subparser_genyaml(subparsers)

    # Add exampleyamls to appsdk
    genimage.set_subparser_exampleyamls(subparsers)

    argcomplete.autocomplete(parser)

    if len(sys.argv) == 1:
        parser.print_help()
        parser.exit(1)

    args = parser.parse_args()
    set_logger(logger, level=args.loglevel, log_path=args.logdir)
    args.func(args)

def gensdk(args):
    appsdk = AppSDK()
    appsdk.generate_sdk(args.file, args.output)

def checksdk(args):
    appsdk = AppSDK()
    appsdk.check_sdk()

def buildrpm(args):
    appsdk = AppSDK()
    appsdk.buildrpm(args.file, args.installdir, rpmdir=args.outputdir, pkgarch=args.pkgarch)

def publishrpm(args):
    appsdk = AppSDK()
    appsdk.publishrpm(args.repo, args.rpms)
    
if __name__ == "__main__":
    try:
        ret = main()
    except Exception:
        ret = 1
        import traceback
        traceback.print_exc()
    sys.exit(ret)
