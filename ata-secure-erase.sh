#!/usr/bin/env bash

# ata-secure-erase.sh
# Use hdparm (8) to erase an ATA disk with the SECURITY ERASE UNIT (F4h)
# command under Linux

# Copyright (c) 2023 Eric Engstrom
# Copyright (c) 2015 TigerOnVaseline
#
# https://github.com/eengstrom/secure-erase

# This code is licensed under MIT license:
# http://opensource.org/licenses/MIT

# POSIX conventions and the Shell Style Guide have been adhered to where viable
# https://google.github.io/styleguide/shell.xml

# Linted with shellcheck: https://github.com/koalaman/shellcheck

# References:
# T13/1699-D, AT Attachment 8 - ATA/ATAPI Command Set (ATA8-ACS)
# http://www.t13.org/documents/UploadedDocuments/docs2007/D1699r4a-ATA8-ACS.pdf

# Related Tutorials:
# - https://www.thomas-krenn.com/en/wiki/Perform_a_SSD_Secure_Erase
# - https://www.stevenmaude.co.uk/posts/securely-erasing-frozen-hard-disks-with-hdparm

# DISCLAIMER
# Whilst care has been taken to thoroughly test this script using a variety of
# cases, # as with all Linux/UNIX-like affairs, it may still fail in mysterious
# circumstances. In particular, ERASE UNIT may fail to erase some SSD drives:
# M. Wei, L. M. Grupp, F. M. Spada, and S. Swanson, 'Reliably Erasing Data
# from Flash-Based Solid State Drives'
# https://www.usenix.org/legacy/event/fast11/tech/full_papers/Wei.pdf

# Read arguments and count into arrays to prevent them getting mangled
readonly SCRIPT_NAME=${0##*/}
readonly -a ARGV=("$@")
readonly ARGC=("$#")
readonly DISK_PASSWORD="123456"
readonly REQUIRED_OS="Linux"
readonly MIN_KERNEL_VERSION=20627
readonly MIN_BASH_VERSION=4
readonly REQUIRED_COMMANDS="awk grep hdparm lsblk udevadm uname pv"

# Global variables, with defaults
ENHANCED=""   # NOTE: this is a string global, for simplicity of coding, but not readability.

show_usage() {
    cat <<- _EOF_ >&2

Usage:  ${SCRIPT_NAME} [-f] [-e] [-p] device | -l
Erase a disk with the ATA SECURITY ERASE UNIT command

OPTIONS
    -l    List available disks to erase
    -e    Perform "ENHANCED" security erase
    -p    Show estimated progress during erase
    -f    Don't prompt before erasing (USE WITH CAUTION)

EXAMPLES
  - Erase the device /dev/sda:
    ${SCRIPT_NAME} /dev/sda

_EOF_
}

list_available_disks() {
    local device
    local eligible_disk
    local -a eligible_disks
    udevadm settle # Syncronise with udev first
    for device in $(lsblk --nodeps --noheadings --output NAME --paths); do
        if is_block_device "${device}" && ata_erase_support "${device}"; then
            eligible_disks+=("${device}")
        fi
    done
    if [[ ${#eligible_disks[@]} -gt 0 ]]; then
        echo "Available disks for ${ENHANCED@L}secure erase are:"
        for eligible_disk in "${eligible_disks[@]}"; do
            echo "${eligible_disk} - $(estimated_erase_time_info "${eligible_disk}")"
        done
    else
        echo >&2 "No supported disks found for secure erase"
    fi
}

is_block_device() {
    local file="$1"
    if [[ -b ${file} ]]; then
        true
    else
        false
    fi
}

ata_erase_support() {
    local disk="$1"
    # if the search for time to erase is empty, this will return non-zero.
    estimated_erase_time_info "${disk}" >/dev/null
}

# old_ata_erase_support() {
#     local disk="$1"
#     local -a hdparm_identify_result
#     local identify_index
#     # If SECURITY ERASE UNIT is supported, hdparm -I (identify) output should
#     # match "Security:" with "supported" on either the first or second
#     # subsequent line:
#     # https://salsa.debian.org/debian/hdparm/blob/master/identify.c
#     readarray -t hdparm_identify_result < <( hdparm -I "${disk}" 2>/dev/null )
#     # Could probably have done this with grep -c instead. Oh, well.
#     for identify_index in "${!hdparm_identify_result[@]}"; do
#         if [[ "${hdparm_identify_result[$identify_index]}" =~ ^Security: ]]; then
#             if [[ "${hdparm_identify_result[$identify_index+1]//$'\t'/}" =~ ^supported \
#                 || "${hdparm_identify_result[$identify_index+2]//$'\t'/}" =~ ^supported ]]; then
#                 true
#             else
#                 false
#             fi
#         break
#         else
#             false
#         fi
#     done
# }

is_unfrozen() {
    local frozen_state
    frozen_state=$(hdparm -I "${ata_disk}" 2>/dev/null | awk '/frozen/ { print $1,$2 }')
    if [ "${frozen_state}" == "not frozen" ]; then
        true
    else
        false
    fi
}

set_password () {
    local ata_disk="$1"
    hdparm --user-master u --security-set-pass "${DISK_PASSWORD}" "${ata_disk}" >/dev/null
}

is_password_set () {
    local password_state
    password_state=$(hdparm -I "$1" 2>/dev/null | awk '/Security:/{n=NR+3} NR==n { print $1,$2 }')
    if [[ ${password_state} == "enabled" ]]; then
        true
    else
        false
    fi
}

show_disk_partitions () {
    local ata_disk="$1"
    lsblk -o 'NAME,TYPE,SIZE,FSTYPE,FSVER,LABEL,MOUNTPOINT' "${ata_disk}" \
        | sed 's/^[\t ]*/  /'
}

estimated_erase_time_info () {
    local ata_disk="$1"
    hdparm -I "${ata_disk}" 2>/dev/null \
      | grep -oE "[0-9]+min for ${ENHANCED}SECURITY ERASE UNIT."
}

# return estimated erase time, in minutes.
estimated_erase_time_min () {
    local ata_disk="$1"
    estimated_erase_time_info "${ata_disk}" \
        | grep -oE '^[0-9]+'
}

erase_disk() {
    local ata_disk="$1"
    local enhanced_opt="${ENHANCED:+-${ENHANCED@L}}"
    hdparm --user-master u --security-erase${enhanced_opt} "${DISK_PASSWORD}" "$ata_disk" >/dev/null
}

# show an estimated progress meter and timer, which requires `pv`.
# idea from https://stackoverflow.com/questions/23630501/how-to-progress-bar-in-bash
show_progress() {
    local ata_disk="$1"
    local est_time="$(estimated_erase_time_min "${ata_disk}")"
    local est_sec=$(("${est_time}" * 60))
    local est_max=$(("${est_sec}" * 4))
    echo "NOTE: drive reported **estimated** time to completion;"
    echo "      may take *much* more or less than predicted..."
    for x in $(seq "${est_max}") ; do
      printf .; sleep 1;
    done | pv -ptec -s"${est_sec}" > /dev/null
    # done | pv -ptec -i0.5 -s"${est_sec}" > /dev/null
}

main() {

    local system_name
    local kernel_release
    local kernel_version
    local kernel_version_numeric
    local list_only=false
    local force=false
    local progress=false
    local -l user_choice # Force lower case

    # setup signal handlers to kill entire process tree on exit
    # https://unix.stackexchange.com/questions/67532/what-does-kill-0-do-actually
    # https://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits
    trap "exit" INT TERM
    trap "kill 0" EXIT

    if [[ "${BASH_VERSINFO[0]}" -lt "${MIN_BASH_VERSION}" ]]; then
        echo >&2 "Error: This script requires bash-4.0 or higher"
        exit 1
    fi

    # Get operating system name (POSIX)
    system_name=$(uname -s)

    if [[ "${system_name}" != "${REQUIRED_OS}" ]]; then
        echo >&2 "This script can only run on ${REQUIRED_OS}"
        exit 1
    fi

    kernel_release=$(uname --kernel-release)
    kernel_version=(${kernel_release//[.-]/ })
    kernel_version_numeric=$(((kernel_version[0] * 10000) + (kernel_version[1] * 100) + kernel_version[2]))

    # lsblk requires sysfs block directory (kernel 2.6.27 and above)
    if [[ ${kernel_version_numeric} -lt ${MIN_KERNEL_VERSION} ]]; then
        echo >&2 "This script requires kernel version ${MIN_KERNEL_VERSION} or higher"
    fi

    if [[ "${EUID}" -ne  "0" ]]; then
        echo >&2 "Error: This script must be run as root or with sudo (8)"
        exit 1
    fi

    # POSIX-compliant method for checking a command is available
    local required_command
    for required_command in ${REQUIRED_COMMANDS}
    do
        if ! type "${required_command}" >/dev/null 2>&1; then
            echo >&2 "Error: This script requires ${required_command}"
            exit 1
        fi
    done

    while getopts ":efhlp" option
    do
        case "${option}" in
        l)
            list_only=true
            ;;
        h)
            show_usage
            exit 0
            ;;
        e)
            ENHANCED="ENHANCED " # NOTE: intentional space at end of string!
            ;;
        f)
            force=true
            ;;
        p)
            progress=true
            ;;
        *)
            show_usage
            exit 1
            ;;
        esac
    done
    shift $((OPTIND-1))

    if ${list_only}; then
        list_available_disks
        exit 0
    fi

    # remaining args should start with disk to erase
    local ata_disk="$1"
    if [[ -z "${ata_disk}" ]]; then
        show_usage
        exit 1
    fi

    # Check the specifed device exists and is a block device
    if ! is_block_device "${ata_disk}"; then
        echo >&2 "Error: No such block device ${ata_disk}, use ${SCRIPT_NAME} -l to list available disks"
        exit 1
    fi

    if ! ata_erase_support "${ata_disk}"; then
        echo >&2 "Error: ATA ${ENHANCED}SECURITY ERASE UNIT unsupported on ${ata_disk}, use ${SCRIPT_NAME} -l to list available disks"
        exit 1
    fi

    # Check for frozen state
    if ! is_unfrozen "${ata_disk}"; then
        echo >&2 "Error: Disk ${ata_disk} security state is frozen; c.f. https://ata.wiki.kernel.org/index.php/ATA_Secure_Erase for options"
        exit 1
    fi

    echo "Disk erase on ${ata_disk}:"
    show_disk_partitions "${ata_disk}"
    echo "ESTIMATED $(estimated_erase_time_info "${ata_disk}")"

    if ! ${force}; then
        echo "[5m[1;31mWARNING: about to erase all data on ${ata_disk} beyond recovery.[0m"
        read -p "Continue [y/N]? " -r user_choice
        if [[ "${user_choice}" != [yY] ]]; then
            echo "Secure erase operation cancelled"
            exit 0
        fi
    fi

    echo -n "Attempting to set user password and enable secure erase..."
    set_password "${ata_disk}"
    if ! is_password_set "${ata_disk}"; then
        echo " done."
    else
        echo
        echo >&2 "Error setting user password on ${ata_disk}"
        exit 1
    fi

    echo "Initiating ${ENHANCED}secure erase for ${ata_disk}..."
    # if requested, add (background) progress-ish meter/timer
    ${progress} && (show_progress "${ata_disk}" &) && sleep 0.5
    # local progress_pid=$!
    # sleep 0.5
    erase_disk "${ata_disk}"
    # kill $progress_pid
    # re-read partition table
    partprobe  "${ata_disk}"
    # Sucessful erase should reset "enabled" value to "not"
    if ! is_password_set "${ata_disk}"; then
        echo "${ENHANCED}Secure erase was successful for ${ata_disk}";
        exit 0
    else
        echo >&2 "Error performing ${ENHANCED}secure erase on ${ata_disk}"
        exit 1
    fi;
}

main "${ARGV[@]}"
