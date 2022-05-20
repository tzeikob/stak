#!/usr/bin/env bash

set -e -u

VERSION="0.1.0"

BLANK="^(""|[ *])$"
YES="^([Yy][Ee][Ss]|[Yy])$"
INT="^[0-9]+$"

echo -e "Stack v$VERSION"
echo -e "Starting base installation process"

if [ ! -d "/sys/firmware/efi/efivars" ]; then
  echo -e "This script supports only UEFI systems"
  echo -e "Process exiting with code: 1"
  exit 1
fi

echo -e "\nPartitioning and formatting the installation disk..."
echo -e "The following disks found in your system:"

lsblk

read -p "Enter the device path of the disk to apply the installation: " device

while [ ! -b "$device" ]; do
  echo -e "Invalid device path: '$device'"
  read -p "Please enter a valid device path: " device
done

read -p "Enter the size of the swap partition in GB (0 to skip swap): " swapsize

while [[ ! $swapsize =~ $INT ]]; do
  echo -e "Invalid swap size: '$swapsize'"
  read -p "Please enter a valid size: " swapsize
done

read -p "IMPORTANT, all data in '$device' will be lost, shall we proceed? [y/N] " answer

if [[ ! $answer =~ $YES ]]; then
  echo -e "Canceling the installation process..."
  echo -e "Process exiting with code: 0"
  exit 0
fi

echo -e "\nStarting partitioning in '$device'..."
echo -e "Erasing any existing GPT and MBR data tables..."

sgdisk -Z "$device"

echo -e "Creating a clean GPT table free of partitions..."

sgdisk -og "$device"

echo -e "Creating the boot EFI partition..."

sgdisk -n 1:0:+500M -c 1:"EFI System Partition" -t 1:ef00 "$device"
dev_efi=${device}1

if [[ $swapsize -gt 0 ]]; then
  echo -e "Creating the swap partition..."

  sgdisk -n 2:0:+${swapsize}G -c 2:"Swap Partition" -t 2:8200 "$device"
  dev_swap=${device}2

  echo -e "Creating the root partition..."

  sgdisk -n 3:0:0 -c 3:"Root Partition" -t 3:8300 "$device"
  dev_root=${device}3
else
  echo -e "Creating the root partition..."

  sgdisk -n 2:0:0 -c 2:"Root Partition" -t 2:8300 "$device"
  dev_root=${device}2
fi

echo -e "Partitioning on '$device' has completed:\n"

sgdisk -p "$device"

echo -e "\nFormatting partitions in '$device'..."
echo -e "Formating the '$dev_efi' boot EFI partition as FAT32..."

mkfs.fat -F 32 $dev_efi

if [[ $swapsize -gt 0 ]]; then
  echo -e "Formating the '$dev_swap' swap partition..."
  mkswap $dev_swap
  swapon $dev_swap
fi

echo -e "Formating the '$dev_root' root partition as EXT4..."

mkfs.ext4 -q $dev_root

echo -e "Formating has been completed successfully"

echo -e "\nMounting the boot and root partitions..."

mount $dev_root /mnt

mkdir -p /mnt/boot
mount $dev_efi /mnt/boot

echo -e "Partitions have been mounted under '/mnt':\n"

lsblk $device

echo -e "\nStarting the installation of the base packages..."
echo -e "Updating the system clock..."

timedatectl set-ntp true
timedatectl status

echo -e "System clock has been updated"

echo -e "Refreshing the packages mirror list..."

reflector --age 8 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy

echo -e "The mirror list is now up to date"
echo -e "Installing base linux packages..."

pacstrap /mnt base linux linux-headers linux-lts linux-lts-headers linux-firmware archlinux-keyring

echo -e "Base packages have been installed successfully"

echo -e "\nCreating the file system table..."

genfstab -U /mnt >> /mnt/etc/fstab

echo -e "The file system table has been created in '/mnt/etc/fstab'"

echo -e "Generating the root installation script..."

cat << \EOF | sed 's/  //' > /mnt/install.sh
  #!/usr/bin/env bash

  set -e -u

  BLANK="^(""|[ *])$"
  YES="^([Yy][Ee][Ss]|[Yy])$"

  NVIDIA="^(nvidia|n)$"
  AMD="^(amd|a)$"
  INTEL="^(intel|i)$"
  VIRTUAL="^(virtual|v)$"

  CPU="($AMD|$INTEL)"
  GPU="($NVIDIA|$AMD|$INTEL|$VIRTUAL)"

  shopt -s nocasematch

  echo -e "Starting the installation script..."

  echo -e "\nSetting up the local timezone..."
  read -p "Enter your timezone in slash form (e.g. Europe/Athens): " timezone

  while [ ! -f "/usr/share/zoneinfo/$timezone" ]; do
    echo -e "Invalid timezone: '$timezone'"
    read -p "Please enter a valid timezone: " timezone
  done

  ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
  hwclock --systohc

  echo -e "System clock synchronized to the hardware clock"
  echo -e "Enabling NTP synchronization..."

  timedatectl set-ntp true
  timedatectl status

  echo -e "Local timezone has been set successfully"

  echo -e "\nSetting up the system locales..."

  echo "LANG=en_US.UTF-8" >> /etc/locale.conf

  sed -i 's/#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  sed -i 's/#\(el_GR\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen

  echo -e "Locales have been genereated successfully"

  echo -e "\nSetting up hostname and hosts..."
  read -p "Enter the host name of your system: [arch] " hostname

  if [[ $hostname =~ $BLANK ]]; then
    hostname="arch"
  fi

  echo $hostname >> /etc/hostname

  echo "" >> /etc/hosts
  echo "127.0.0.1    localhost" >> /etc/hosts
  echo "::1          localhost" >> /etc/hosts
  echo "127.0.1.1    $hostname" >> /etc/hosts

  echo -e "Hostname and hosts have been set"

  echo -e "\nInstalling extra base packages..."

  echo -e "Refreshing the packages mirror list..."

  pacman -S reflector rsync
  reflector --age 8 --sort rate --save /etc/pacman.d/mirrorlist
  pacman -Syy

  echo -e "The mirror list is now up to date"

  pacman -S base-devel grub efibootmgr mtools dosfstools \
    bash-completion \
    cups bluez bluez-utils \
    terminus-font vim nano git

  echo -e "Installing power management utilities..."

  pacman -S acpi acpid acpi_call tlp

  echo -e "Installing network utility packages..."

  pacman -S networkmanager dialog wireless_tools netctl inetutils dnsutils \
    wpa_supplicant openssh nfs-utils openbsd-netcat iptables-nft \
    ipset firewalld

  echo -e "Installing audio drivers and packages..."

  pacman -S alsa-utils pipewire pipewire-alsa pipewire-pulse pipewire-jack

  echo -e "\nInstalling hardware drivers..."
  read -p "What proccessor is your system running? [AMD/intel] " cpu_vendor

  while [[ ! $cpu_vendor =~ $CPU && ! $cpu_vendor =~ $BLANK ]]; do
    echo -e "Invalid cpu vendor: '$cpu_vendor'"
    read -p "Please enter a valid cpu vendor: " cpu_vendor
  done

  if [[ $cpu_vendor =~ $INTEL ]]; then
    cpu_vendor="intel"
    cpu_pkg="intel-ucode"
  else
    cpu_vendor="amd"
    cpu_pkg="amd-ucode"
  fi

  echo -e "Installing $cpu_vendor cpu packages..."

  pacman -S $cpu_pkg

  read -p "What video card is your system using? [NVIDIA/amd/intel/virtual] " gpu_vendor

  while [[ ! $gpu_vendor =~ $GPU && ! $gpu_vendor =~ $BLANK ]]; do
    echo -e "Invalid gpu vendor: '$gpu_vendor'"
    read -p "Please enter a valid gpu vendor: " gpu_vendor
  done

  if [[ $gpu_vendor =~ $AMD ]]; then
    gpu_vendor="amd"
    gpu_pkg="xf86-video-ati" # or try messa
    gpu_module="amdgpu"
  elif [[ $gpu_vendor =~ $INTEL ]]; then
    gpu_vendor="intel"
    gpu_pkg="xf86-video-intel" # or try mesa
    gpu_module="i915"
  elif [[ $gpu_vendor =~ $VIRTUAL ]]; then
    gpu_vendor="virtual"
    gpu_pkg="xf86-video-vmware virtualbox-guest-utils"
    gpu_module=""
  else
    gpu_vendor="nvidia"
    gpu_pkg="nvidia nvidia-lts nvidia-utils nvidia-settings"
    gpu_module="nvidia"
  fi

  if [[ ! $gpu_pkg =~ $BLANK ]]; then
    echo -e "Installing $gpu_vendor gpu packages..."

    pacman -S $gpu_pkg

    sed -i "s/MODULES=(\(.*\))$/MODULES=(\1 $gpu_module)/" /etc/mkinitcpio.conf
    sed -i "s/MODULES=( \(.*\))$/MODULES=(\1)/" /etc/mkinitcpio.conf

    echo -e "Video card driver module added into the '/etc/mkinitcpio.conf/'"

    mkinitcpio -p linux
    mkinitcpio -p linux-lts

    echo -e "Initramfs has been re-genereated successfully"
  else
    echo -e "No gpu packages will be installed"
  fi

  echo -e "\nSetting up users and passwords..."
  echo -e "Adding password for the root user..."

  passwd

  echo -e "Creating a new sudoer user..."
  read -p "Enter the name of the sudoer user: [bob] " username

  if [[ $username =~ $BLANK ]]; then
    username="bob"
  fi

  useradd -m -g users -G wheel $username

  echo -e "Adding password for the user $username..."

  passwd $username

  echo -e "Adding user $username to the group of sudoers..."

  sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

  echo -e "User $username with sudo priviledges has been created"

  echo -e "\nInstalling the bootloader via GRUB..."

  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
  grub-mkconfig -o /boot/grub/grub.cfg

  sed -i '/#GRUB_SAVEDEFAULT=true/i GRUB_DEFAULT=saved' /etc/default/grub
  sed -i 's/#GRUB_SAVEDEFAULT=true/GRUB_SAVEDEFAULT=true/' /etc/default/grub
  sed -i 's/#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub

  grub-mkconfig -o /boot/grub/grub.cfg

  echo -e "Bootloader has been installed"

  echo -e "\nEnabling system services..."

  systemctl enable systemd-timesyncd
  systemctl enable NetworkManager
  systemctl enable bluetooth
  systemctl enable tlp
  systemctl enable acpid
  systemctl enable cups
  systemctl enable sshd
  systemctl enable reflector.timer
  systemctl enable fstrim.timer
  systemctl enable firewalld

  if [[ $gpu_vendor =~ $VIRTUAL ]]; then
    systemctl enable vboxservice
  fi

  echo -e "\nScript has been completed successfully!"
  echo -e "Exiting back to archiso..."
EOF

echo -e "Moving to the installation disk..."

arch-chroot /mnt \
  bash /install.sh &&
  echo -e "Removing installation files..." &&
  rm /mnt/install.sh &&
  echo -e "Unmounting the partitions..." &&
  umount -R /mnt &&
  echo -e "Rebooting the system in 10 secs (ctrl-c to cancel)..." &&
  sleep 10 &&
  reboot