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
	FS="[ \t=]+"
	uuids = 1
}

function blockdev_exists(node,	retval)
{
	cmd = "test -b \"" node  "\""
	(system(cmd) == 0) ? retval = 0 : retval = 1
	return retval
}

function parse_vol_id(name)
{
	# ensure these var's are empty
	fstype = fsusage = mntdev = mntpnt = label = uuid = ""

	# ensure `dev' is prefixed with /dev/
	dev = (name !~ /^\/dev\//) ? "/dev/" name : name

	# test block device node for existance
	if (blockdev_exists(dev) != 0)
		return 0
		
	# device name blacklist
	if (name ~ /^(ram|cloop|loop).+/)
		return 0
	# run vol_id on dev, discard stderr
	cmd = "/lib/udev/vol_id " dev " 2>/dev/null"
	# label label_safe type usage uuid version
	while ((cmd | getline) == 1) {
		sub(/^ID_FS_/, "", $1)
		id[tolower($1)] = $2
	}

	# return if we can't reliably use the partitions filesystem
	if (!id["type"] || id["type"] == "unknown" || id["usage"] !~ /(filesystem|other)/)
		return 0
	
	# use metainfo for linux native filesystems
	if (id["type"] ~ /^(ext[234]|jfs|reiser|swap|xfs)/) {
		if (labels && id["label"]) mntdev = "LABEL=" id["label"]
		else if (uuids && id["uuid"]) mntdev = "UUID=" id["uuid"]
		else mntdev = dev
	}
	# workaround for non-perfect non-native fs support
	else {
		mntdev = id["label"] ? "/dev/disk/by-label/" id["label"] : \
			id["uuid"] ?  "/dev/disk/by-uuid/" id["uuid"] : dev
		
		if (blockdev_exists(mntdev) != 0)
			mntdev = dev
	}
	
	# no mount point for swap
	mntpnt = (id["type"] == "swap") ? "none" : "/media/" name
	
	# print something useful for a fstab helper program
	print(mntdev, mntpnt, fstype)
}

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
			# Note: starts from $2 if anything other than FS=" " is used. I think that's messy from awk, but ok.
			sub(/^[ \t]+/,"")
			# Skip if illegal entry, or if first column not a number, or if third column indicates ext. partition
			# Note: $2 % 16 could be used to determine major block device, such as hda. However superfloppies are
			# possible, so leaving that out.
			if (! $4 || $1 !~ /[0-9]+/ || $3 < 2) continue
			parse_vol_id($4)
		}
	}
}

