#!/usr/bin/env bash

shopt -s nocasematch

branch=${1:-"master"}

uefi=true

if [ ! -d "/sys/firmware/efi/efivars" ]; then
  uefi=false
fi

clear && echo

cat << EOF
[38;2;6;221;155m░[39m[38;2;7;221;154m█[39m[38;2;7;222;154m▀[39m[38;2;7;222;154m▀[39m[38;2;7;222;154m░[39m[38;2;7;222;153m▀[39m[38;2;7;222;153m█[39m[38;2;7;223;153m▀[39m[38;2;7;223;153m░[39m[38;2;7;223;152m█[39m[38;2;7;223;152m▀[39m[38;2;7;223;152m█[39m[38;2;7;223;152m░[39m[38;2;8;224;151m█[39m[38;2;8;224;151m▀[39m[38;2;8;224;151m▀[39m[38;2;8;224;151m░[39m[38;2;8;224;150m█[39m[38;2;8;224;150m░[39m[38;2;8;225;150m█[39m[38;2;8;225;150m[39m
[38;2;7;223;152m░[39m[38;2;7;223;152m▀[39m[38;2;7;223;152m▀[39m[38;2;8;224;151m█[39m[38;2;8;224;151m░[39m[38;2;8;224;151m░[39m[38;2;8;224;151m█[39m[38;2;8;224;150m░[39m[38;2;8;224;150m░[39m[38;2;8;225;150m█[39m[38;2;8;225;150m▀[39m[38;2;8;225;149m█[39m[38;2;8;225;149m░[39m[38;2;8;225;149m█[39m[38;2;8;225;149m░[39m[38;2;9;225;148m░[39m[38;2;9;226;148m░[39m[38;2;9;226;148m█[39m[38;2;9;226;148m▀[39m[38;2;9;226;147m▄[39m[38;2;9;226;147m[39m
[38;2;8;225;150m░[39m[38;2;8;225;149m▀[39m[38;2;8;225;149m▀[39m[38;2;8;225;149m▀[39m[38;2;8;225;149m░[39m[38;2;9;225;148m░[39m[38;2;9;226;148m▀[39m[38;2;9;226;148m░[39m[38;2;9;226;148m░[39m[38;2;9;226;147m▀[39m[38;2;9;226;147m░[39m[38;2;9;226;147m▀[39m[38;2;9;227;147m░[39m[38;2;9;227;146m▀[39m[38;2;9;227;146m▀[39m[38;2;9;227;146m▀[39m[38;2;10;227;146m░[39m[38;2;10;227;145m▀[39m[38;2;10;228;145m░[39m[38;2;10;228;145m▀[39m[38;2;10;228;145m[39m
EOF

echo -e "\nStack v0.0.1 - $([ $uefi == true ] && echo 'UEFI' || echo 'BIOS')"
echo -e "Starting the bootstrap process...\n"

echo -e "Partitioning the installation disk..."
echo -e "The following disks found in your system:"

lsblk

read -p "Enter the name of disk the new system will be installed on: " device
device=/dev/$device

while [ ! -b "$device" ]; do
  echo -e "Invalid disk device: '$device'"
  read -p "Please enter a valid disk device: " device
  device=/dev/$device
done

echo -e "Installation disk set to block device '$device'"

echo -e "\nIMPORTANT, all data in '$device' will be lost"
read -p "Shall we proceed and partition the disk? [y/N] " answer
answer=${answer:-"no"}

if [[ ! $answer =~ ^(yes|y)$ ]]; then
  echo -e "\nCanceling the installation process..."
  echo -e "Process exiting with code: 0"
  exit 0
fi

if [[ $uefi == true ]]; then
  echo -e "\nCreating a clean GPT partition table..."

  parted --script $device mklabel gpt

  parted --script $device mkpart "Boot" fat32 1MiB 501MiB
  parted --script $device set 1 boot on

  echo -e "Boot partition created under '${device}1'"

  parted --script $device mkpart "Root" ext4 501Mib 100%

  echo -e "Root partition created under '${device}2'"

  echo -e "Partitioning table completed successfully:\n"

  parted --script $device print

  echo -e "Formatting partitions in '$device'..."

  mkfs.fat -F 32 ${device}1
  mkfs.ext4 -F -q ${device}2

  echo -e "Formating has been completed successfully"

  echo -e "\nMounting the boot and root partitions..."

  mount ${device}2 /mnt
  mount --mkdir ${device}1 /mnt/boot

  echo -e "Boot partition '${device}1' mounted to '/mnt/boot'"
  echo -e "Root partition '${device}2' mounted to '/mnt'"
else
  echo -e "\nCreating a clean MBR partition table..."

  parted --script $device mklabel msdos

  parted --script $device mkpart primary ext4 1Mib 100%
  parted --script $device set 1 boot on

  echo -e "Root partition created under '${device}1'"

  echo -e "Partitioning table completed successfully:\n"

  parted --script $device print

  echo -e "\nFormatting partitions in '$device'..."

  mkfs.ext4 -F -q ${device}1

  echo -e "Formating has been completed successfully"

  echo -e "\nMounting the root partition..."

  mount ${device}1 /mnt

  echo -e "Root partition '${device}1' mounted to '/mnt'"
fi

echo -e "Disk layout of '$device' after partitioning:\n"

lsblk $device

echo -e "\nUpdating the system clock..."

timedatectl set-ntp true
sleep 60
timedatectl status

echo -e "System clock has been updated"

echo -e "\nUpdating the mirror list..."

read -p "What is your current location? [Greece] " country
country=${country:-"Greece"}

echo -e "Refreshing the mirror list from servers in $country..."

reflector --country $country --age 8 --sort age --save /etc/pacman.d/mirrorlist

while [ ! $? -eq 0 ]; do
  echo -e "Reflector failed for '$country'"
  read -p "Please enter another country: [Greece] " country
  country=${country:-"Greece"}

  reflector --country $country --age 8 --sort age --save /etc/pacman.d/mirrorlist
done

pacman --noconfirm -Sy archlinux-keyring

echo -e "The mirror list is now up to date"

echo -e "\nInstalling the base system..."

read -p "Which linux kernels to install: [stable/lts/ALL] " kernels
kernels=${kernels:-"all"}

while [[ ! $kernels =~ ^(stable|lts|all)$ ]]; do
  echo -e "Invalid linux kernel: '$kernels'"
  read -p "Please enter which linux kernels to install: [stable/lts/ALL] " kernels
  kernels=${kernels:-"all"}
done

if [[ $kernels =~ ^stable$ ]]; then
  linux_kernels="linux"
  linux_headers="linux-headers"
elif [[ $kernels =~ ^lts$ ]]; then
  linux_kernels="linux-lts"
  linux_headers="linux-lts-headers"
else
  linux_kernels="linux linux-lts"
  linux_headers="linux-headers linux-lts-headers"
fi

pacstrap /mnt base $linux_kernels $linux_headers linux-firmware archlinux-keyring reflector rsync sudo

echo -e "Base packages have been installed successfully"

echo -e "\nCreating the file system table..."

genfstab -U /mnt >> /mnt/etc/fstab

echo -e "The file system table has been created in '/mnt/etc/fstab'"

echo -e "\nBootstrap process has been completed successfully"
echo -e "Moving to the new system in 15 secs (ctrl-c to skip)..."

sleep 15

arch-chroot /mnt \
  bash -c "$(curl -sLo- https://raw.githubusercontent.com/tzeikob/stack/$branch/stack.sh)" -s "$device" "$branch" "$kernels" "$country" 2>&1 | tee /mnt/var/log/stack.log &&
  echo -e "Unmounting all partitions under '/mnt'..." &&
  umount -R /mnt || echo -e "Ignoring any busy mounted points..." &&
  echo -e "Rebooting the system in 15 secs (ctrl-c to skip)..." &&
  sleep 15 &&
  reboot