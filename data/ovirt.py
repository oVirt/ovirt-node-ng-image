#
# rhv.py
#
# Copyright (C) 2016  Red Hat, Inc.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

from pyanaconda.installclass import BaseInstallClass
from pyanaconda.product import productName
from pyanaconda.kickstart import getAvailableDiskSpace
from pyanaconda.storage.partspec import PartSpec
from pyanaconda.platform import platform
from pyanaconda.storage.autopart import swap_suggestion
from blivet.size import Size
from pykickstart.constants import AUTOPART_TYPE_LVM_THINP

__all__ = ["OvirtBaseInstallClass"]


class OvirtBaseInstallClass(BaseInstallClass):
    name = "oVirt Node Next"
    sortPriority = 21000
    hidden = not productName.startswith("oVirt")

    efi_dir = "fedora"
    default_autopart_type = AUTOPART_TYPE_LVM_THINP

    # there is a RHV branded help content variant
    help_folder = "/usr/share/anaconda/help/rhv"

    def configure(self, anaconda):
        BaseInstallClass.configure(self, anaconda)

    def setDefaultPartitioning(self, storage):
        autorequests = [PartSpec(mountpoint="/", fstype=storage.default_fstype,
                                 size=Size("6GiB"), thin=True,
                                 grow=True, lv=True),
                        PartSpec(mountpoint="/home",
                                 fstype=storage.default_fstype,
                                 size=Size("1GiB"), thin=True, lv=True),
                        PartSpec(mountpoint="/tmp",
                                 fstype=storage.default_fstype,
                                 size=Size("1GiB"), thin=True, lv=True),
                        PartSpec(mountpoint="/var",
                                 fstype=storage.default_fstype,
                                 size=Size("15GiB"), thin=True, lv=True),
                        PartSpec(mountpoint="/var/log",
                                 fstype=storage.default_fstype,
                                 size=Size("8GiB"), thin=True, lv=True),
                        PartSpec(mountpoint="/var/log/audit",
                                 fstype=storage.default_fstype,
                                 size=Size("2GiB"), thin=True, lv=True)]

        bootreqs = platform.set_default_partitioning()
        if bootreqs:
            autorequests.extend(bootreqs)

        disk_space = getAvailableDiskSpace(storage)
        swp = swap_suggestion(disk_space=disk_space)
        autorequests.append(PartSpec(fstype="swap", size=swp, grow=False,
                                     lv=True, encrypted=True))

        for autoreq in autorequests:
            if autoreq.fstype is None:
                if autoreq.mountpoint == "/boot":
                    autoreq.fstype = storage.default_boot_fstype
                    autoreq.size = Size("1GiB")
                else:
                    autoreq.fstype = storage.default_fstype

        storage.autopart_requests = autorequests
        storage.autopart_type = AUTOPART_TYPE_LVM_THINP

    def __init__(self):
        BaseInstallClass.__init__(self)
