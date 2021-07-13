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
import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

setuptools.setup(
    name="genimage", # Replace with your own username
    version="1.0",
    author="Hongxu Jia",
    author_email="hongxu.jia@windriver.com",
    description="Implementation of Full Image generator with Application SDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="todo",
    packages=setuptools.find_packages(),
    entry_points = {
        'console_scripts': [
            'genimage=genimage:main',
            'genyaml=genimage:main_genyaml',
            'exampleyamls=genimage:main_exampleyamls',
            'geninitramfs=genimage:main_geninitramfs',
            'gencontainer=genimage:main_gencontainer'
        ],
    },
    license="GNU General Public License v2.0",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    python_requires='>=3.6',
)

