# ata-secure-erase

A bash script to securely erase ATA disks, runs the `SECURITY ERASE UNIT` command using `hdparm`.

The script functions along similar lines to `hderase.py`, but is written entirely in `bash`.

Suited to minimal Linux environments, or for those who object to use of Python on religious grounds.

For highly sensitive uses, particularly with SSDs, care should be taken to validate the erasure, or first overwrite the drive with a pass of zeroes:

* https://www.usenix.org/legacy/event/fast11/tech/full_papers/Wei.pdf

## Usage

	$ sudo ./ata-secure-erase.sh -h

	Usage:  ata-secure-erase.sh [-f] [-e] [-p] device | -l
	Erase a disk with the ATA SECURITY ERASE UNIT command

	OPTIONS
			-l    List available disks to erase
			-e    Perform "ENHANCED" security erase
			-p    Show estimated progress during erase
			-f    Don't prompt before erasing (USE WITH CAUTION)

	EXAMPLES
		- Erase the device /dev/sda:

			ata-secure-erase.sh /dev/sda

## Locked or Frozen Disks

If your (SSD) disk is locked or frozen, or perhaps already has a user password set, you may be able to unlock using a master password for the device:

* https://serverfault.com/questions/712849/how-to-unlock-an-ssd-disk-with-hdparm
* https://web.archive.org/web/20141115020359/http://ipv5.wordpress.com/2008/04/14/list-of-hard-disk-ata-master-passwords/

## Erasing NVME disks

NVME devices are not the same as ATA devices, and require different routines to erase at the device level.  These may help:

* https://superuser.com/questions/1530363/how-to-securely-erase-an-nvme-ssd

## See Also

* https://github.com/TigerOnVaseline/ata-secure-erase
* https://github.com/yoshiaki-u/hderase.py
