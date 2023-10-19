#!/bin/bash

# 2012/08/21 v0.1
#	- 1st build

export LANG=C
export PATH=/sbin:/usr/sbin:/usr/bin:/bin

PROGNAME=`basename $0`

WORKMD=/dev/md17
MNTPNT_SRC=`mktemp -d /tmp/tmp-of-copy-hdl2-a-disk-src.XXXXXXXX`
MNTPNT_DST=`mktemp -d /tmp/tmp-of-copy-hdl2-a-disk-dst.XXXXXXXX` 


# exit with last procedures and exitcode
exit_with_last_procedures_and_exitcode() {
	local exitcode=$1
	# last procedures...
	umount $MNTPNT_SRC $MNTPNT_DST > /dev/null 2>&1
	rmdir $MNTPNT_SRC $MNTPNT_DST  > /dev/null 2>&1
	mdadm --stop $WORKMD           > /dev/null 2>&1
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


# check source disk whether it is certainly HDL2-A HDD(RAID1).
check_source_disk() {
	local srcdisk=$1
	local errmes="'$srcdisk' does not seem to be a HDL2-A HDD"
	run parted -s $srcdisk u s print
	local parts=`parted -s $srcdisk u s print | grep "^ [0-9] \+[0-9]\+s" | awk '{ print $2" "$3; }'`
	local elmparts="40s 1048623s 1048624s 3145783s 3145784s 7340095s 7340096s 7602247s 7602248s 8650831s"

	# check if the parittion number is 6
	if [ `echo $parts | wc -w` != 12 ]; then
		error_exit "$errmes, due to illegal partiiton number"
	fi

	# check if the basic parittion sizes are same as HDL2-A HDD
	if [ "`echo $parts | cut -f 1-10 -d ' '`" != "$elmparts" ]; then
		error_exit "$errmes, due to illegal partition size"
	fi

	# check if the XFS can be mounted
	local srcpart="${srcdisk}6"
	[ -e "$srcpart" ] || srcpart="${srcdisk}p6"
	[ -e "$srcpart" ] || error_exit "No partition exists: '${srcdisk}6' or '${srcdisk}p6'"
	run mount -t xfs -r $srcpart $MNTPNT_SRC
	run umount $MNTPNT_SRC 
}

# check destination disk whether it is certainly be a suitable as destination
check_destination_disk() {
	local disk=$1
	[ -e "$disk" ] || error_exit "The device file '$disk' does not exist"
#	[ "${disk##/dev/}" != "$disk" ] || error_exit "$disk is not in /dev/"
#	[ "${disk%%[0-9]}" = "$disk" ] || error_exit "$disk is a partition, not a whole of disk"

	# check if it has disk label
	local mes=`parted -s $disk u s print 2>&1`
	if [ "$mes" = "Error: $disk: unrecognised disk label" ]; then
		ask_yn "Write new disk label(GPT) onto ${disk}? LOSE ALL DATA!"
		run parted $disk mklabel gpt
	fi

	# read the sector size of disk
	run parted -s $disk u s print
	local sector=`parted -s $disk u s print | grep "^Disk $disk: " | awk '{ print $3; }' | tr -d s | grep "^[0-9]\+$"`
	[ -n "$sector" ] || error_exit "fail to read sector number of $disk"

	# check the disk size if it is enough
	if [ "$sector" -lt "$((5*1024*1024*1024/512))" ]; then
		error_exit "sector size($sector) is too small, need to be >5GB"
	fi 
}


# copy basic image(top of the source disk) to the destination disk
copy_basic_image() {
	local srcdisk=$1 dstdisk=$2
	echo "Copying basic image, will take 80sec or more"
	run dd if=$srcdisk of=$dstdisk bs=512 count=8650832 conv=notrunc
}


# make necessary partitions for HDL2-A*.*
make_partitions() {
	local disk=$1

	run parted -s $disk mklabel gpt
	local lastsect=`parted -s $disk u s print | grep "Disk $disk: " | awk '{ print $3; }' | tr -d s`
	[ $? = 0 -a -n "$lastsect" ] || error_exit "last sector of the disk can not be collected."
	# reduce GPT sectors(=34)
	lastsect=$(($lastsect-34))
	# align to 8sectors(=4096byte)
	lastsect=$((($lastsect/8)*8-1))

	run parted -s $disk u s mkpart primary 40      1048623
	run parted -s $disk u s mkpart primary 1048624 3145783
	run parted -s $disk u s mkpart primary 3145784 7340095
	run parted -s $disk u s mkpart primary 7340096 7602247
	run parted -s $disk u s mkpart primary 7602248 8650831
 	# clear md header of version 0.9/1.0
	run dd if=/dev/zero of=$disk conv=notrunc bs=512 seek=$(($lastsect-256)) count=256
	run parted -s $disk u s mkpart primary 8650832 $lastsect
	# partprobe is necessary for waiting for creating all partitions
	run partprobe $disk
}


# copy xfs partition(=#6), even if it is different size
copy_xfs_partition() {
	local srcdisk=$1 dstdisk=$2
	local srcpart="${srcdisk}6" dstpart="${dstdisk}6"
	[ -e "$srcpart" ] || srcpart="${srcdisk}p6"
	[ -e "$srcpart" ] || error_exit "No partition exists: '${srcdisk}6' or '${srcdisk}p6'"
	[ -e "$dstpart" ] || dstpart="${dstdisk}p6"
	[ -e "$dstpart" ] || error_exit "No partition exists: '${dstdisk}6' or '${dstdisk}p6'"

	# create md
	run mdadm --create $WORKMD --force --level=raid1 --raid-device=2 --metadata=1.0 $dstpart missing

	# check whether src_sector_number is smaller than dst_sector_number
	local srcsize=`parted -s $srcdisk u s print | grep "Disk $srcdisk:" | awk '{ print $3; }' | tr -d s`
	local dstsize=`parted -s $dstdisk u s print | grep "Disk $dstdisk:" | awk '{ print $3; }' | tr -d s`

	# show sizes
	run mount -t xfs -r $srcpart $MNTPNT_SRC
	local srcused=`df $MNTPNT_SRC | tail -n 1 | awk '{print $3;}'`
	run umount $MNTPNT_SRC
	echo ""
	echo "               Source disk size = $srcdisk : $(($srcsize*512/1024/1024)) MB"
	echo "          Destination disk size = $dstdisk : $(($dstsize*512/1024/1024)) MB"
	echo "     Source partition used size = $srcpart: $(($srcused/1024)) MB"

	# set time(in minutes) to copy the data, in case the speed is 50MB/s
	local copymes="This will take time, probably $(($srcused/50000/60))min or more..."

	if [ $srcsize -le $dstsize ]; then 
		echo ""
		# if src_disk_size <= dst_disk_size, then just copy and grow it
		echo "Starting copying by 'xfs_copy' and 'xfs_growfs':"
		echo "$copymes"
		# Note: $srcpart can be read as xfs without mdadm --assemble
		{
		# run xfs_copy $srcpart $WORKMD
			# xfs_copy exits 137 even when it finished successfully.
			# see: http://oss.sgi.com/cgi-bin/gitweb.cgi?p=xfs/cmds/xfsprogs.git;a=commitdiff;h=2277ce35c37c75aa3c146261d5abe32f9cc39baa
			echo "# xfs_copy $srcpart $WORKMD"
			xfs_copy $srcpart $WORKMD
			[ $? = 0 -o $? = 137 ] || error_exit "xfs_copy failed"
		}
		run mount -t xfs $WORKMD $MNTPNT_DST
		run xfs_growfs $WORKMD
		run umount $MNTPNT_DST
	else
		# if src_disk_size > dst_disk_size, then try mkfs.xfs and cp
		run mkfs.xfs -f $WORKMD
		run mount -t xfs -r $srcpart $MNTPNT_SRC
		run mount -t xfs $WORKMD     $MNTPNT_DST
		# get dstfree sizes
		local dstfree=`df $MNTPNT_DST | tail -n 1 | awk '{print $4;}'`
		echo "Destination partition free size = $dstpart: $(($dstfree/1024)) MB"
		echo ""

		# Note: $srcpart can be read as xfs without mdadm --assemble
		if [ $srcused -gt $dstfree ]; then
			run df $MNTPNT_SRC
			run df $MNTPNT_DST
			echo "$dstpart is smaller than $srcpart, could be full."
			ask_yn "Continue copying?"
		fi
		# If there's rsync, use it as it is faster than "cp -a"
		if [ -x /usr/bin/rsync ]; then
			echo "Starting copying by 'rsync':"
			echo "$copymes"
			run rsync -aHAX --quiet $MNTPNT_SRC/ $MNTPNT_DST/
		else
			echo "Starting copying by 'cp':"
			echo "$copymes"
			run cp -a $MNTPNT_SRC/. $MNTPNT_DST/
		fi
		run umount $MNTPNT_SRC
		run umount $MNTPNT_DST
	fi
	run mdadm --stop $WORKMD
}


############## main routine #############################################

# print note.
echo "$PROGNAME :"
echo "    copy one of a HDL2-A HDD(RAID1 only) to another blank HDD."
echo "    This can copy the contents in source HDD to different size HDD,"
echo "    even it is larger/smaller(but enough larger to save the contents)."
echo ""
echo "below command is recommended to be run before running this:"
echo "    # udevadm control --stop-exec-queue"
echo "or"
echo "    # udevcontrol stop_exec_queue"
echo ""

# check command line arguments at first
if [ $# != 2 ]; then
	echo "usage: $PROGNAME <source_HDD_device_of_HDL2-A> <destination_blank_HDD>"
	error_end "Wrong argument"
fi
srcdisk=$1
dstdisk=$2

[ -e /proc/mdstat ] || modprobe md
if grep -q "^${WORKMD##/dev/} : " /proc/mdstat; then
	error_end "$WORKMD is used in /proc/mdstat, please stop it at first"
fi
if grep -qE "${dstdisk##/dev/}[1-6]" /proc/mdstat; then
	error_end "`cat /proc/mdstat`
$dstdisk is used in /proc/mdstat, please stop it at first"
fi

[ -r $srcdisk ] || error_end "'$srcdisk' does not exist"
[ -r $dstdisk ] || error_end "'$dstdisk' does not exist"
[ -w $dstdisk ] || error_end "'$dstdisk' can not be written"

# trap Ctrl+C, to run the last procedures.
trap "error_exit 'Aborted.'" 2

# run actually
check_source_disk $srcdisk
check_destination_disk $dstdisk

echo "Copying $srcdisk to $dstdisk will DESTROY $dstdisk completely."
ask_yn "Would you really like to start copying?"

copy_basic_image $srcdisk $dstdisk
make_partitions $dstdisk
copy_xfs_partition $srcdisk $dstdisk

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
echo "1. Connect the HDD($dstdisk) onto HDL2-A as *1 drive only*"
echo "2. Boot up HDL2-A and stop it(to make it recognize one disk is broken)"
echo "3. Add another blank HDD onto HDL2-A and boot it up"
echo "4. Wait for the finish of RAID1 rebuilding(will take several hours)"
echo ""
echo "Enjoy!"
echo ""

exit_with_last_procedures_and_exitcode 0

