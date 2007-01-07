#!/usr/bin/awk -f
#
# Copyright (C) 2007 Kel Modderman <kel@otaku42.de>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this package; if not, write to the Free Software 
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, 
# MA 02110-1301, USA.
#
# On Debian GNU/Linux systems, the text of the GPL license can be
# found in /usr/share/common-licenses/GPL.

BEGIN {
	if (ARGC > 1) {
		# test devices given as arguments
		for (i = 1; i < ARGC; i++) {
			parse_vol_id(ARGV[i])
		}
	}
	else {
		# parse /proc/partitions
		while ((getline < "/proc/partitions") == 1) {
			# major minor #blocks name
			if (!$4)
				# discard invalid records
				continue
			else if ($3 < 2)
				# discard extended partitions
				continue
			else
				parse_vol_id($4)
		}
	}
}

function parse_vol_id(name)
{
	# ensure these var's are empty
	fstype = fsusage = mntdev = mntpnt = label = uuid = ""

	# ensure name has /dev/ stripped from it
	gsub(/^\/dev\//, "", name)
	
	# ensure `dev' is prefixed with /dev/
	dev = "/dev/" name

	# test block device node for existance
	if (blockdev_exists(dev) != 0)
		return 0
		
	# device name blacklist
	if (name ~ /^(ram|cloop|loop).+/)
		return 0
	
	# run vol_id on dev, discard stderr
	cmd = "/lib/udev/vol_id " dev " 2>/dev/null"
	while ((cmd | getline) == 1) {
		split($0, vol_info, "=")
		# store volume information
		if (vol_info[1] == "ID_FS_USAGE")
			fsusage = vol_info[2]
		else if (vol_info[1] == "ID_FS_TYPE")
			fstype = vol_info[2]
		else if (vol_info[1] == "ID_FS_UUID" && uuids)
			uuid = vol_info[2]
		else if	(vol_info[1] == "ID_FS_LABEL_SAFE" && labels)
			label = vol_info[2]
		else
			continue
	}
	
	# return if we can't reliably use the partitions filesystem
	if (!fstype || fstype == "unknown" || fsusage !~ /(filesystem|other)/)
		return 0
	
	# use metainfo for linux native filesystems
	if (fstype ~ /^(ext[234]|jfs|reiser|swap|xfs)/) {
		mntdev = label ? "LABEL=" label : uuid ? "UUID=" uuid : dev
	}
	# workaround for non-perfect non-native fs support
	else {
		mntdev = label ? "/dev/disk/by-label/" label : \
			uuid ?  "/dev/disk/by-uuid/" uuid : dev
		
		if (blockdev_exists(mntdev) != 0)
			mntdev = dev
	}
	
	# no mount point for swap
	mntpnt = (fstype == "swap") ? "none" : "/media/" name
	
	# print something useful for a fstab helper program
	print mntdev, mntpnt, fstype
}

function blockdev_exists(node,	retval)
{
	cmd = "test -b \"" node  "\""
	(system(cmd) == 0) ? retval = 0 : retval = 1
	return retval
}
