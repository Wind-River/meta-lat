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
if [ -z $BASH_VERSION ]; then
    echo "Only bash support argcomplete"
    return
fi
eval "$(register-python-argcomplete appsdk)"
eval "$(register-python-argcomplete geninitramfs)"
eval "$(register-python-argcomplete genimage)"
eval "$(register-python-argcomplete genyaml)"
eval "$(register-python-argcomplete exampleyamls)"
eval "$(register-python-argcomplete gencontainer)"
