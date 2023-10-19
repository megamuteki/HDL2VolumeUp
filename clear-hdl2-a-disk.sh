#!/bin/bash

# 2012/08/21 v0.1
#	- 1st build

export LANG=C
export PATH=/sbin:/usr/sbin:/usr/bin:/bin

PROGNAME=`basename $0`

# exit with last procedures and exitcode
exit_with_last_procedures_and_exitcode() {
	local exitcode=$1
	# last procedures...
	# (none for this)
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
check_disk() {
	local disk=$1
	local errmes="'$disk' does not seem to be a HDL2-A HDD"

	# print the parted command and the result, even if it returns error.
	echo "parted -s $disk u s print"
	parted -s $disk u s print
	if [ $? != 0 ]; then
		echo "parted can not read the partition table of '$disk'."
		ask_yn "Write new disk label(GPT) onto ${disk}? LOSE ALL DATA!"
		run parted -s $disk mklabel gpt
	fi

	# read the sector number of disk
	local sector=`parted -s $disk u s print | grep "^Disk $disk: " | awk '{ print $3; }' | tr -d s | grep "^[0-9]\+$"`
	[ -n "$sector" ] || error_exit "fail to read sector number of $disk"

	# check the disk size if it is enough
	if [ "$sector" -lt "$((5*1024*1024*1024/512))" ]; then
		error_exit "sector size($sector) is too small, need to be >5GB"
	fi 

	local parts=`parted -s $disk u s print | grep "^ [0-9] \+[0-9]\+s" | awk '{ print $2" "$3; }'`

	# check if the parittion number is 6
	if [ `echo $parts | wc -w` != 12 ]; then
		echo "This does not seem to be a HDL-A HDD."
		return
	fi

	local elmparts="40s 1048623s 1048624s 3145783s 3145784s 7340095s 7340096s 7602247s 7602248s 8650831s"
	# check if the basic parittion sizes are same as HDL2-A HDD
	if [ "`echo $parts | cut -f 1-10 -d ' '`" != "$elmparts" ]; then
		echo "This does not seem to be a HDL-A HDD."
		return
	fi

	echo "This is a HDL-A HDD."
}


# clear the disk! wow!
clear_disk() {
	local disk=$1
	local ddcmd="dd if=/dev/zero of=$disk conv=notrunc bs=512 count=256"

	# clear partition head, for clearing filesystem signature
	run $ddcmd seek=40
	run $ddcmd seek=1048624
	run $ddcmd seek=3145784
	run $ddcmd seek=7340096
	run $ddcmd seek=7602248
	run $ddcmd seek=8650832

	# clear partition tail, for clearing md signature
	run $ddcmd seek=$((1048624-256))
	run $ddcmd seek=$((3145784-256))
	run $ddcmd seek=$((7340096-256))
	run $ddcmd seek=$((7602248-256))
	run $ddcmd seek=$((8650832-256))

	# clear tail of the disk
	local lastsect=`parted -s $disk u s print | grep "Disk $disk: " | awk '{ print $3; }' | tr -d s`
	[ $? = 0 -a -n "$lastsect" ] || error_exit "last sector of the disk can not be collected."
	# reduce GPT sectors(=34)
	run $ddcmd seek=$(($lastsect-34-256))

	# again, clear the tail of the last partition if it exists
	lastsect=`parted -s $disk u s print | grep "^ 6 " | awk '{ print $3; }' | tr -d s`
	[ -z "$lastsect" ] || run $ddcmd seek=$(($lastsect-256))

	# clear partition table
	run parted -s $disk mklabel gpt
}


############## main routine #############################################

# print note.
echo "$PROGNAME :"
echo "    clear a HDL2-A HDD in very short time, to be blank HDD."
echo "    This clears only md signature and partition tables."
echo "    In case of clearing all data on the HDD completely, consider to run:"
echo "      # dd if=/dev/zero of=/dev/<THE_HDD> bs=100M"
echo "    instead of using this tool."
echo ""
echo "below command is recommended to be run before running this:"
echo "    # udevadm control --stop-exec-queue"
echo "or"
echo "    # udevcontrol stop_exec_queue"
echo ""


# check command line arguments at first
if [ $# != 1 ]; then
	echo "usage: $PROGNAME <HDD_device_of_HDL2-A>"
	error_end "Wrong argument"
fi
disk=$1

if [ -e /proc/mdstat ] && grep -qE "${disk##/dev/}[1-6]" /proc/mdstat; then
	error_end "`cat /proc/mdstat`
$disk is used in /proc/mdstat, please stop it at first"
fi


[ -r $disk ] || error_end "'$disk' does not exist"
[ -w $disk ] || error_end "'$dstdisk' can not be written"

# trap Ctrl+C, to run the last procedures.
trap "error_exit 'Aborted.'" 2

# run actually
check_disk $disk
ask_yn "Would you really like to clear '$disk'? LOSE ALL DATA!"
clear_disk $disk

# ok, now the disk has been cleared!
echo ""
echo "Done successfully!"
echo ""
echo "Below command is better to be run if you stopped udev once:"
echo "    # udevadm control --start-exec-queue"
echo "or"
echo "    # udevcontrol start_exec_queue"
echo ""

exit_with_last_procedures_and_exitcode 0

