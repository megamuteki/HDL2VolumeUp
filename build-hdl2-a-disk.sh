#!/bin/bash

# 2012/08/21 v0.2
#	- skip checking that the dev is "/dev/*".
#	- skip checking that the dev is not "*[0-9]".
#	- add skipping copying imagefile in case the filename is "--"
#	- check if the disk has disk label in check_disk().
#	- change WORKMD from /dev/md0 to /dev/md2, to avoid confliction
#	- add WORKLOOP for partitioning image file
#	- check ${disk}6 or ${disk}p6 for loopback devices
#	- add function expanding gz/bz2/xz imagefile
# 2012/08/19 v0.1
#	- 1st build

export LANG=C
export PATH=/sbin:/usr/sbin:/usr/bin:/bin

PROGNAME=`basename $0`

WORKMD=/dev/md17
WORKLOOP=/dev/loop3


# exit with last procedures and exitcode
exit_with_last_procedures_and_exitcode() {
	local exitcode=$1
	# last procedures...
	kpartx -d $WORKLOOP                > /dev/null 2>&1
	losetup -d $WORKLOOP               > /dev/null 2>&1
	mdadm --stop $WORKMD               > /dev/null 2>&1
	exit $exitcode
}


# print an error message, and exit with last procedures.
error_exit() {
	echo "### ERROR ################################################" 1>&2
	echo "$*" 1>&2
	echo "### ERROR ################################################" 1>&2
	exit_with_last_procedures_and_exitcode 1
}


# just print an error message, and exit.
error_end() {
	echo "### ERROR ################################################" 1>&2
	echo "$*" 1>&2
	echo "### ERROR ################################################" 1>&2
	exit 1
}


# run a command with arguments, and exit if any errors occur.
run() {
	echo "# $*"
	eval "$*"
	local ret=$?
	if [ $ret != 0 ]; then
		echo "Error: returned $ret" 1>&2
		exit_with_last_procedures_and_exitcode $ret
	fi
	return 0
}


# ask yes/no and abort in case of no
ask_yn() {
	local yn
	echo -n "$* y/n[n]: "
	read yn
	[ "$yn" = "y" -o "$yn" = "Y" ] || error_exit "Aborted."
}


# make necessary partitions for HDL2-A*.*
make_partitions() {
	local disk=$1

	run parted -s $disk mklabel gpt

	local lastsect=`parted -s $disk u s print | grep "Disk $disk: " | awk '{ print $3; }' | sed -e 's/s$//'`
	[ $? = 0 -a -n "$lastsect" ] || error_exit "last sector of the disk can not be collected."
	# reduce GPT sectors(=34)
	lastsect=$(($lastsect-34))
	# align to 8sectors(=4096byte)
	lastsect=$((($lastsect/8)*8-1))
 	# clear md header of version 0.9/1.0
	run dd if=/dev/zero of=$disk conv=notrunc bs=512 seek=$(($lastsect-255)) count=256

	# make partitions at one time, to avoid md auto-recognition by udev
	run parted -s $disk u s mkpart primary 40      1048623
	run parted -s $disk u s mkpart primary 1048624 3145783
	run parted -s $disk u s mkpart primary 3145784 7340095
	run parted -s $disk u s mkpart primary 7340096 7602247
	run parted -s $disk u s mkpart primary 7602248 8650831
	run parted -s $disk u s mkpart primary 8650832 $lastsect

	local orgdisk=""
	if [ ! -b "$disk" ]; then
		# if it is just a normal file, need to be block device
		orgdisk="$disk"
		run losetup $WORKLOOP $disk
		run kpartx -s -a $WORKLOOP
		disk=/dev/mapper/${WORKLOOP##/dev/}
	fi
	# create md
	local mdpart=${disk}6
	[ -e $mdpart ] || mdpart=${disk}p6
	[ -e $mdpart ] || error_exit "No partition exists: '${disk}6' or '${disk}p6'"
	run mdadm --create $WORKMD --force --level=raid1 --raid-device=2 --metadata=1.0 $mdpart missing
#	run mkfs.xfs -f $WORKMD
	run mdadm --stop $WORKMD
	if [ -n "$orgdisk" ]; then
		# disable the temporal block device
		run kpartx -d $WORKLOOP
		run losetup -d $WORKLOOP
		disk="$orgdisk"
	fi
}


# check whether user really want to process the disk
check_disk() {
	local disk=$1
	[ -e "$disk" ] || error_exit "The device file '$disk' does not exist"
#	[ "${disk##/dev/}" != "$disk" ] || error_exit "$disk is not in /dev/"
#	[ "${disk%%[0-9]}" = "$disk" ] || error_exit "$disk is a partition, not a whole of disk"

	if [ ! -b $disk ]; then
		echo "Disk '$disk' is not a block device file."
		run ls -al $disk
	else
		local mes=`parted -s $disk u s print 2>&1`
		if [ "$mes" = "Error: $disk: unrecognised disk label" ]; then
			echo "Disk '$disk' does not have disk label(gpt/msdos)."
			run ls -al $disk
		else
			echo "Disk '$disk' is below:"
			echo "======================"
			run parted -s $disk u s print
			echo "======================"
		fi
	fi
	echo

	ask_yn "Is it O.K. to re-partition this for HDL2-A?"
}


# write imagefile onto the disk
write_imagefile() {
	local disk=$1 imagefile=$2

	# skip copying if the imagefile name is "--"
	[ "$imagefile" != "--" ] || return

	# write the imagefile to disk, even if it is compressed
	local ext="${imagefile##*.}"
	if [ "$ext" = "gz" ]; then
		run "gzip -dc $imagefile | dd of=$disk bs=128M conv=notrunc"
	elif [ "$ext" = "bz2" ]; then
		run "bzip2 -dc $imagefile | dd of=$disk bs=128M conv=notrunc"
	elif [ "$ext" = "xz" ]; then
		run "xz -dc $imagefile | dd of=$disk bs=128M conv=notrunc"
	else
		run "dd if=$imagefile of=$disk bs=128M conv=notrunc"
	fi
}


############## main routine #############################################

# print note.
echo "$PROGNAME :"
echo "    build a disk for HDL2-A with automatic/suitable sizing."
echo "    All you need to do is specifing HDD_device_file and HDL2-A image"
echo "    file, sized 4430MB, copy of top of the origial HDD of HDL2-A."
echo "    HDL2-A_diskimage_file can be '--' to skip copying the image"
echo ""
echo "below command is recommended to be run before running this:"
echo "    # udevadm control --stop-exec-queue"
echo "or"
echo "    # udevcontrol stop_exec_queue"
echo ""

# check command line arguments at first
if [ $# != 2 ]; then
	echo "usage: $PROGNAME <HDD_device_file_to_be_written> <HDL2-A_diskimage_file>"
	error_end "Wrong argument"
fi
disk=$1
imagefile=$2

if [ "$imagefile" != "--" -a ! -r $imagefile ]; then
	error_end "'$imagefile' does not exist"
fi
[ -r $disk ] || error_end "'$disk' does not exist"

[ -e /proc/mdstat ] || modprobe md
if grep -q "^${WORKMD##/dev/} : " /proc/mdstat; then
	error_end "$WORKMD is used in /proc/mdstat, please stop it at first"
fi
if grep -qE "${disk##/dev/}[1-6]" /proc/mdstat; then
	error_end "`cat /proc/mdstat`
$disk is used in /proc/mdstat, please stop it at first"
fi
if losetup $WORKLOOP > /dev/null 2>&1; then
	run losetup $WORKLOOP
	error_end "$WORKLOOP is used, please stop it at first"
fi

# trap Ctrl+C, to run the last procedures.
trap "error_exit 'Aborted.'" 2

# run actually
check_disk $disk
write_imagefile $disk $imagefile
make_partitions $disk

# ok, now the disk has been updated!
echo ""
echo "Done successfully!"
echo ""
echo "Below command is better to be run if you stopped udev once:"
echo "    # udevadm control --start-exec-queue"
echo "or"
echo "    # udevcontrol start_exec_queue"
echo ""
echo "Follow the instructions below:"
echo "1. Connect the HDD($disk) onto HDL2-A as *1 drive only*"
echo "2. Boot up HDL2-A with the one HDD and configure it"
echo "3. Add another blank HDD onto HDL2-A for furture configuration"
echo ""
echo "Enjoy!"

exit_with_last_procedures_and_exitcode 0

