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

function blockdev_exists(node,	retval)
{
	cmd = "test -b \"" node  "\""
	(system(cmd) == 0) ? retval = 0 : retval = 1
	return retval
}

function parse_vol_id(name)
{
	# ensure these var's are empty
	delete id
	mntdev = mntpnt = ""

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
	# label label_safe type usage uuid version
	while (cmd | getline) {
		sub(/^ID_FS_/, "", $1)
		id[tolower($1)] = $2
	}

	# return if we can't reliably use the partitions filesystem
	if (!id["type"] || id["type"] == "unknown" || id["usage"] !~ /(filesystem|other)/)
		return 0

	# use metainfo for linux native filesystems
	if (id["type"] ~ /^(ext[234]|jfs|reiser|swap|xfs)/) {
		mntdev = (labels && id["label"]) ? "LABEL=" id["label"] : \
			(uuids && id["uuid"]) ? "UUID=" id["uuid"] : dev
	}
	# workaround for non-perfect non-native fs support
	else {
		mntdev = (labels && id["label"]) ? "/dev/disk/by-label/" id["label"] : \
			(uuids && id["uuid"]) ?  "/dev/disk/by-uuid/" id["uuid"] : dev

		if (blockdev_exists(mntdev) != 0)
			mntdev = dev
	}

	# no mount point for swap
	mntpnt = (id["type"] == "swap") ? "none" : "/media/" name
	
	# print something useful for a fstab helper program
	print(mntdev, mntpnt, id["type"])
}

function parse_all() {
	# parse /proc/partitions
	while (getline < "/proc/partitions") {
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

function usage() {
	print("Usage: scanpartitions [-l|--labels] [-u|--uuids] [device]");
	exit(0);
}

BEGIN {
	FS="[ \t=]+"
	if (ARGC > 1) {
		# test devices given as arguments
		for (i = 1; i < ARGC; i++) {
			if (ARGV[i] ~ /^(-u|--uuids)$/) uuids=1
			else if (ARGV[i] ~ /^(-l|--labels)$/) labels=1
			else if (ARGV[i] ~ /^-/) usage()
			else parse_vol_id(ARGV[i])
		}
	}
	else parse_all()
}

