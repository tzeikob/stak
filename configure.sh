#!/usr/bin/env bash

BLANK="^(""|[ *])$"
YES="^([Yy][Ee][Ss]|[Yy])$"

AMD="^(amd|a)$"
INTEL="^(intel|i)$"

CPU="($AMD|$INTEL)"

echo -e "\nSetting up the local timezone..."
read -p "Enter your timezone in slash form (e.g. Europe/Athens): " timezone

while [ ! -f "/usr/share/zoneinfo/$timezone" ]; do
  echo -e "Invalid timezone: '$timezone'"
  read -p "Please enter a valid timezone: " timezone
done

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

echo -e "System clock synchronized to the hardware clock"
echo -e "Local timezone has been set successfully"

echo -e "\nSetting up the system locales..."

echo "LANG=en_US.UTF-8" >> /etc/locale.conf

echo "" >> /etc/locale.gen
echo "el_GR.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
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

pacman -S base-devel grub os-prober efibootmgr mtools dosfstools wpa_supplicant openssh \
  bash-completion nfs-utils networkmanager dialog wireless_tools netctl inetutils dnsutils reflector rsync \
  cups bluez bluez-utils \
  terminus-font vim nano git

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