# HDL2VolumeUp
----These Scripts are absolutely No Warannty----

These are Landisk HDL2 VolumeUp Scripts

A.ApplicableModel
HDL2-A2.0
May be
(They use same firm ware)
HDL2-A2.0, HDL2-A4.0, HDL2-A6.0, HDL2-A4.0/E, HDL2-AH2.0, HDL2-AH4.0,
HDL2-AH6.0, HDL2-AH2.0W, HDL2-AH4.0W, HDL2-AH6.0W, HDL2-A2.0R, HDL2-A4.0R, 
HDL2-A6.0R, HDL2-A4.0R/E, HDL2-A2.0RT, HDL2-A4.0RT, HDL2-A6.0RT, IPHL2-A4.0RT, 
IPHL2-A6.0RT, IPHL2-A8.0RT, IPHL2-A12RT

B,Prepare
--Landisk Raid1 diskx1 (L or R)
--Blank Diskx2 (Bkank Disk A , Bkank Disk B)
Capacity of New Blank Disk > Landisk Raid1 disk
--USB Disk Interface
--Linux PC

C.StapByStep
a,clear New Blank Disk
PC---->{USB Disk Interface)----->Blank Disk A

$sudo fdisk -l
find Blank Disk
(sample)
/dev/sdb1      2048 11721043967 11721041920   5.5T Linux ファイルシステム
sudo  clear-hdl2-a-disk.sh  /dev/sdb

check  the disk have some soft raid or not
 sudo cat /proc/mdstat
 $ sudo cat /proc/mdstat
Personalities : [raid1] 
md1 : active raid1 sdb1[1] sdc1[2]
      1073610560 blocks super 1.2 [2/2] [UU]
Stop Raid
$ sudo sudo mdadm --stop /dev/md1
mdadm: stopped /dev/md1

Clear Raid Partion

b.Set Landsik Raid Disk and Cleaerd Blank Disk
PC---->{USB Disk Interface)----->Cleard Blank Disk A or B
PC---->{USB Disk Interface)----->Landisk Raid1 disk L or R

c.Disk check
$sudo fdisk -l
(Sample)
PC---->{USB Disk Interface)----->Cleard Blank Disk A or B (/dev/sdd)
PC---->{USB Disk Interface)----->Landisk Raid1 disk L or R (/dev/sde)

d.run script
$sudo bash copy-hdl2-a-disk.sh  /dev/sdd /dev/sde

e.Set Copied Disk and BlankDisk
Landisk L slot ---------->Copied  Blank Disk
Landisk R slot ---------->Cleared  Blank Disk

f.Rebuild Raid automaticaly.





