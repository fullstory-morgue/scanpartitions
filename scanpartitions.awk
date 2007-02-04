#!/usr/bin/awk -f
#
# Copyright (C) 2007 Kel Modderman <kel@otaku42.de>
#		     Michiel de Boer <locsmif@kanotix.com>
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

function blockdev_exists(node,    retval)
{
	retval = system("test -b \"" node  "\"")
	return retval
}

function parse_vol_id(name)
{
	# ensure these var's are empty
	delete id
	delete vol_id
	mntdev = mntpnt = ""

	# ensure name has /dev/ stripped from it, and dev is prefixed with /dev/
	sub(/^\/dev\//, "", name); dev = "/dev/" name

	# test block device node for existance
	if (blockdev_exists(dev) != 0) return 0
	# device name blacklist
	if (name ~ /^(ram|cloop|loop).+/) return 0

	# run vol_id on dev, discard stderr
	cmd = "/lib/udev/vol_id " dev " 2>/dev/null"
	# form assoc. array `id'
	while (cmd | getline) {
		# indices: label label_safe type usage uuid version
		split($0, vol_id, "="); sub(/^ID_FS_/, "", vol_id[1])
		id[tolower(vol_id[1])] = vol_id[2]
	}

	# return if we cannot handle fs usage type
	if (id["usage"] !~ /(filesystem|other)/) return 0

	# return if we can't reliably use the partitions filesystem
	if (!id["type"] || id["type"] == "unknown") return 0

	# use metainfo for linux native filesystems
	if (id["type"] ~ /^(ext[234]|jfs|reiser|swap|xfs)/) {
		if 	(labels && id["label"])	mntdev = "LABEL=" id["label"]
		else if	(uuids && id["uuid"])	mntdev = "UUID=" id["uuid"]
	}
	# workaround for non-perfect non-native fs support
	else {
		if	(labels && id["label"])	mntdev = "/dev/disk/by-label/" id["label"]
		else if	(uuids && id["uuid"])	mntdev = "/dev/disk/by-uuid/" id["uuid"]
		
		# block device may not yet exist if vfat/ntfs volume was just created
		if (blockdev_exists(mntdev) != 0) mntdev = dev
	}
	
	# fall back to raw device name if uuid/label not found or wanted
	if (!mntdev) mntdev = dev

	# no mount point for swap
	mntpnt = (id["type"] == "swap") ? "none" : "/media/" name
	
	# print something useful for a fstab helper program
	print(mntdev, mntpnt, id["type"])
}

function parse_all() {
	# parse /proc/partitions
	while (getline < "/proc/partitions") {
		# major minor #blocks name
		#
		# Skip if illegal entry, or if first column is not a number, or if
		# number of blocks indicates ext. partition
		# Note: $2 % 16 could be used to determine major block device,
		# such as hda. However superfloppies are possible, so leaving that
		# out.
		if (! $4 || $1 !~ /[0-9]+/ || $3 < 2) continue
		else parse_vol_id($4)
	}
}

function usage() {
	print("Usage: scanpartitions [-l|--labels] [-u|--uuids] [device]")
	exit(0)
}

BEGIN {
	if (ARGC > 1) {
		# test devices given as arguments
		for (i = 1; i < ARGC; i++) {
			if 	(ARGV[i] ~ /^(-u|--uuids)/)	uuids=1
			else if	(ARGV[i] ~ /^(-l|--labels)/)	labels=1
			else if	(ARGV[i] ~ /^-/)		usage()
			else					disk[++j] = ARGV[i]
		}
	}
	
	if (disk[1]) for (i in disk) parse_vol_id(disk[i])
	else parse_all()
}

