#!/usr/bin/env bash

shopt -s nocasematch

device=$1
branch=${2:-"master"}
kernels=${3:-"all"}
country=${4:-"Greece"}

git_url="https://raw.githubusercontent.com/tzeikob/stack/$branch"
config_url="$git_url/config"
bin_url="$git_url/bin"
assets_url="$git_url/assets"

uefi=true

if [ ! -d "/sys/firmware/efi/efivars" ]; then
  uefi=false
fi

echo -e "Starting the stack installation process..."

echo -e "\nSetting console keyboard keymap..."

read -p "Enter the key map of your keyboard: [us] " keymap
keymap=${keymap:-"us"}

keymap_path=$(find /usr/share/kbd/keymaps/ -type f -name "$keymap.map.gz")

while [ -z "$keymap_path" ]; do
  echo -e "Invalid key map: '$keymap'"
  read -p "Please enter a valid keymap: [us] " keymap
  keymap=${keymap:-"us"}

  keymap_path=$(find /usr/share/kbd/keymaps/ -type f -name "$keymap.map.gz")
done

echo "KEYMAP=$keymap" > /etc/vconsole.conf
loadkeys $keymap

echo -e "Console keyboard keymap has been set to '$keymap'"

echo -e "\nSetting up the local timezone..."

read -p "What is your current timezone? [Europe/Athens]: " timezone
timezone=${timezone:-"Europe/Athens"}

while [ ! -f "/usr/share/zoneinfo/$timezone" ]; do
  echo -e "Invalid timezone: '$timezone'"
  read -p "Please enter a valid timezone: [Europe/Athens] " timezone
  timezone=${timezone:-"Europe/Athens"}
done

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

echo -e "Local timezone has been set to '$timezone'"

echo -e "\nEnabling NTP synchronization..."

timedatectl set-ntp true > /dev/null
sleep 5
timedatectl status

hwclock --systohc

echo -e "System clock synchronized to the hardware clock"

echo -e "\nSetting up system locales..."

read -p "Enter locales separated by spaces (e.g. en_US el_GR): [en_US] " locales
locales=${locales:-"en_US"}

for locale in $locales; do
  while [ -z "$locale" ] || ! grep -q "$locale" /etc/locale.gen; do
    echo -e "Invalid locale name: '$locale'"
    read -p "Re-enter the locale: " locale
  done

  sed -i "s/#\($locale.*\)/\1/" /etc/locale.gen
  echo -e "Locale '$locale' added for generation"
done

locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

echo -e "Locales have been genereated successfully"

echo -e "\nSetting up hostname and hosts..."

read -p "Enter the host name of your system: [arch] " hostname
hostname=${hostname:-"arch"}

echo $hostname >> /etc/hostname

echo "" >> /etc/hosts
echo "127.0.0.1    localhost" >> /etc/hosts
echo "::1          localhost" >> /etc/hosts
echo "127.0.1.1    $hostname" >> /etc/hosts

echo -e "Hostname and hosts have been set to '$hostname'"

echo -e "\nSetting up users and passwords..."

echo -e "Adding password for the root user..."

passwd

while [ ! $? -eq 0 ]; do
  echo -e "Failed to set the root password"
  echo -e "Please set the password again"

  passwd
done

echo -e "Creating the new sudoer user..."

read -p "Enter the name of the sudoer user: [bob] " username
username=${username:-"bob"}

useradd -m -G wheel,audio,video,optical,storage $username

echo -e "Adding password for the user '$username'..."

passwd $username

while [ ! $? -eq 0 ]; do
  echo -e "Failed to set the $username password"
  echo -e "Please set the password again"

  passwd $username
done

echo -e "Adding user '$username' to the group of sudoers..."

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo -e "User '$username' has now sudo priviledges"

echo -e "\nSetting up the swap file..."

read -p "Enter the size of the swap file in GB (0 to skip): [0] " swapsize
swapsize=${swapsize:-0}

while [[ ! $swapsize =~ ^[0-9]+$ ]]; do
  echo -e "Invalid swap file size: '$swapsize'"
  read -p "Please enter a valid size in GB (0 to skip): [0] " swapsize
  swapsize=${swapsize:-0}
done

if [[ $swapsize -gt 0 ]]; then
  echo -e "Swap file size set to '${swapsize}GB'"

  echo -e "Creating the swap file..."

  dd if=/dev/zero of=/swapfile bs=1M count=$(expr $swapsize \* 1024) status=progress
  chmod 0600 /swapfile
  mkswap -U clear /swapfile

  echo -e "Enabling swap..."

  swapon /swapfile && free -m

  cp /etc/fstab /etc/fstab.bak
  echo "/swapfile none swap defaults 0 0" | tee -a /etc/fstab

  echo -e "Swap file has been set successfully to '/swapfile'"
else
  echo -e "No swap file will be set"
fi

echo -e "\nRefreshing the mirror list from servers in '$country'..."

reflector --country $country --age 8 --sort age --save /etc/pacman.d/mirrorlist
pacman -Syy

echo -e "The mirror list is now up to date"

sed -i "s/# --country.*/--country $country/" /etc/xdg/reflector/reflector.conf

echo -e "Reflector mirror country set to '$country'"

echo -e "\nInstalling extra base packages..."

pacman -S base-devel pacman-contrib pkgstats grub mtools dosfstools gdisk parted \
  curl wget udisks2 udiskie gvfs gvfs-smb \
  bash-completion man-db man-pages texinfo \
  cups bluez bluez-utils unzip \
  terminus-font vim nano git htop tree arch-audit \
  atool zip xz unace p7zip gzip lzop bzip2 unrar \
  $([ $uefi == true ] && echo 'efibootmgr')

echo -e "\nInstalling the yay package..."

cd /home/$username
git clone https://aur.archlinux.org/yay.git

chown -R $username:$username yay && cd yay
sudo -u $username makepkg -si

cd / && rm -rf /home/$username/yay

echo -e "Yay has been installed"

echo -e "\nInstalling power management utilities..."

pacman -S acpi acpid acpi_call

echo -e "\nInstalling network utility packages..."

pacman -S networkmanager dialog wireless_tools netctl inetutils dnsutils \
  wpa_supplicant openssh nfs-utils openbsd-netcat nftables iptables-nft ipset

echo -e "\nInstalling audio drivers and packages..."

pacman -S alsa-utils pipewire pipewire-alsa pipewire-pulse pipewire-jack pavucontrol

echo -e "\nInstalling the CPU microcode firmware..."

read -p "What proccessor is your system running on? [AMD/intel] " cpu_vendor
cpu_vendor=${cpu_vendor:-"amd"}

while [[ ! $cpu_vendor =~ ^(amd|intel)$ ]]; do
  echo -e "Invalid CPU vendor: '$cpu_vendor'"
  read -p "Please enter a valid CPU vendor: [AMD/intel] " cpu_vendor
  cpu_vendor=${cpu_vendor:-"amd"}
done

if [[ $cpu_vendor =~ ^intel$ ]]; then
  cpu_vendor="intel"
  cpu_pkg="intel-ucode"
else
  cpu_vendor="amd"
  cpu_pkg="amd-ucode"
fi

echo -e "CPU vendor set to '$cpu_vendor'"

pacman -S $cpu_pkg

echo -e "Microcode firmware has been installed"

echo -e "\nInstalling video drivers..."

video_pkgs="xorg xorg-xinit xorg-xrandr arandr"

read -p "Which vendor video drivers to install? [nvidia/amd/intel/nouveau/qxl/vmware/none] " video_vendor

while [[ ! $video_vendor =~ ^(nvidia|amd|intel|nouveau|qxl|vmware|none)$ ]]; do
  echo -e "Invalid video driver vendor: '$video_vendor'"
  read -p "Please enter a valid video driver vendor: [nvidia/amd/intel/nouveau/qxl/vmware/none] " video_vendor
done

if [[ $video_vendor =~ ^nvidia$ ]]; then
  video_vendor="nvidia"

  if [[ $kernels =~ ^stable$ ]]; then
    video_pkgs="$video_pkgs nvidia"
  elif [[ $kernels =~ ^lts$ ]]; then
    video_pkgs="$video_pkgs nvidia-lts"
  else
    video_pkgs="$video_pkgs nvidia nvidia-lts"
  fi

  video_pkgs="$video_pkgs nvidia-utils nvidia-settings"
elif [[ $video_vendor =~ ^amd$ ]]; then
  video_vendor="amd"
  video_pkgs="$video_pkgs xf86-video-amdgpu mesa"
elif [[ $video_vendor =~ ^intel$ ]]; then
  video_vendor="intel"
  video_pkgs="$video_pkgs xf86-video-intel mesa"
elif [[ $video_vendor =~ ^nouveau$ ]]; then
  video_pkgs="$video_pkgs xf86-video-nouveau mesa"
elif [[ $video_vendor =~ ^qxl$ ]]; then
  video_vendor="qxl"
  video_pkgs="$video_pkgs xf86-video-qxl mesa"
elif [[ $video_vendor =~ ^vmware$ ]]; then
  video_vendor="vmware"
  video_pkgs="$video_pkgs xf86-video-vmware mesa"
else
  video_pkgs="$video_pkgs mesa"
fi

echo -e "Video drivers vendor set to '$video_vendor'"

read -p "Is this a virtual box machine? [y/N] " virtual_box
virtual_box=${virtual_box:-"no"}

if [[ $virtual_box =~ ^(yes|y)$ ]]; then
  video_pkgs="$video_pkgs virtualbox-guest-utils"
fi

pacman -S $video_pkgs

echo -e "Video drivers have been installed\n"

read -p "Do you want to install a desktop environment? [Y/n] " answer
answer=${answer:-"yes"}

if [[ $answer =~ ^(yes|y)$ ]]; then
  echo -e "Installing the BSPWM window manager..."

  pacman -S picom bspwm sxhkd rofi rofi-emoji rofi-calc xsel polybar feh firefox sxiv mpv

  echo -e "Setting up the desktop environment configuration..."

  mkdir -p /home/$username/.config/{picom,bspwm,sxhkd,polybar,rofi}

  curl $config_url/picom -sSo /home/$username/.config/picom/picom.conf \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.config/picom/picom.conf

  curl $config_url/bspwm -sSo /home/$username/.config/bspwm/bspwmrc \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /home/$username/.config/bspwm/bspwmrc

  curl $bin_url/bspwm -sSo /home/$username/.config/bspwm/rules \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /home/$username/.config/bspwm/rules

  curl $config_url/sxhkd -sSo /home/$username/.config/sxhkd/sxhkdrc \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.config/sxhkd/sxhkdrc

  curl $config_url/polybar -sSo /home/$username/.config/polybar/config.ini \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.config/polybar/config.ini

  curl $config_url/rofi -sSo /home/$username/.config/rofi/config.rasi \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.config/rofi/config.rasi

  curl $config_url/mime -sSo /home/$username/.config/mimeapps.list \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.config/mimeapps.list

  chown -R $username:$username /home/$username/.config

  if [[ $virtual_box =~ ^(yes|y)$ ]]; then
    sed -i 's/vsync = true;/vsync = false;/' /home/$username/.config/picom/picom.conf

    echo -e "Vsync setting in picom has been disabled"
  fi

  echo -e "\nSetting up the polybar launcher..."

  cat << 'EOF' > /home/$username/.config/polybar/launch.sh
  #!/usr/bin/env bash

  # Terminate already running bar instances
  # If all your bars have ipc enabled, you can use 
  polybar-msg cmd quit
  # Otherwise you can use the nuclear option:
  # killall -q polybar

  # Launch bar
  echo "---" | tee -a /tmp/polybar.log
  polybar main 2>&1 | tee -a /tmp/polybar.log & disown

  echo "Bars launched..."
EOF

  chmod +x /home/$username/.config/polybar/launch.sh
  chown $username:$username /home/$username/.config/polybar/launch.sh

  echo -e "Polybar launcher has been set"

  echo -e "\nInstalling the screen locker..."

  curl https://dl.suckless.org/tools/slock-1.4.tar.gz -sSLo ./slock-1.4.tar.gz \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  tar -xzvf ./slock-1.4.tar.gz

  cd /slock-1.4

  curl https://tools.suckless.org/slock/patches/control-clear/slock-git-20161012-control-clear.diff -sSLo ./control-clear.diff \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  patch -p1 < ./control-clear.diff

  sed -ri 's/(.*)nogroup(.*)/\1nobody\2/' ./config.def.h
  sed -ri 's/.*INIT.*/  [INIT] = "#1a1b26",/' ./config.def.h
  sed -ri 's/.*INPUT.*/  [INPUT] = "#383c4a",/' ./config.def.h
  sed -ri 's/.*FAILED.*/  [FAILED] = "#ff2369"/' ./config.def.h
  sed -ri 's/(.*)controlkeyclear.*/\1controlkeyclear = 1;/' ./config.def.h
  make install
  cd / && rm -rf /slock-1.4 /slock-1.4.tar.gz

  echo -e "Screen lock has been set"

  echo -e "Installing the power launcher via rofi script..."

  curl $bin_url/power -sSo /usr/local/bin/power \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /usr/local/bin/power

  echo -e "\n$username $hostname =NOPASSWD: /sbin/shutdown now,/sbin/reboot" >> /etc/sudoers

  echo -e "User '$username' has granted to trigger power events"

  echo -e "Power launcher has been installed"

  echo -e "\nSetting the keyboard layouts..."

  read -p "Enter the default keyboard layout: [us] " kb_layout
  kb_layout=${kb_layout:-"us"}

  localectl list-x11-keymap-layouts | grep "^$kb_layout$" > /dev/null 2>&1

  while [ ! $? -eq 0 ]; do
    echo -e "Invalid keyboard layout: '$kb_layout'"
    read -p "Please re-type the keyboard layout: [us] " kb_layout
    kb_layout=${kb_layout:-"us"}

    localectl list-x11-keymap-layouts | grep "^$kb_layout$" > /dev/null 2>&1
  done

  kb_layouts="$kb_layout"

  read -p "Do you want to set additional layouts? [y/N] " answer
  answer=${answer:-"no"}

  while [[ $answer =~ ^(yes|y)$ ]]; do
    read -p "Enter a keyboard layout: " kb_layout

    localectl list-x11-keymap-layouts | grep "^$kb_layout$" > /dev/null 2>&1

    while [ ! $? -eq 0 ]; do
      echo -e "Invalid keyboard layout: '$kb_layout'"
      read -p "Please re-type the keyboard layout: " kb_layout

      localectl list-x11-keymap-layouts | grep "^$kb_layout$" > /dev/null 2>&1
    done

    kb_layouts="$kb_layouts,$kb_layout"

    read -p "Do you want to add another layout? [y/N] " answer
    answer=${answer:-"no"}
  done

  cat << EOF > /etc/X11/xorg.conf.d/00-keyboard.conf
  # Written by systemd-localed(8), read by systemd-localed and Xorg. It's
  # probably wise not to edit this file manually. Use localectl(1) to
  # instruct systemd-localed to update it.
  Section "InputClass"
          Identifier "system-keyboard"
          MatchIsKeyboard "on"
          Option "XkbLayout" "$kb_layouts"
          Option "XkbModel" "pc105"
          Option "XkbOptions" "grp:alt_shift_toggle"
  EndSection
EOF

  echo -e "Keyboard layouts have been set"

  echo -e "\nInstalling extra fonts..."

  fonts_path="/usr/share/fonts/extra-fonts"
  mkdir -p $fonts_path

  fonts=(
    "FiraCode https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    "FantasqueSansMono https://github.com/belluzj/fantasque-sans/releases/download/v1.8.0/FantasqueSansMono-Normal.zip"
    "Hack https://github.com/source-foundry/Hack/releases/download/v3.003/Hack-v3.003-ttf.zip"
    "Hasklig https://github.com/i-tu/Hasklig/releases/download/v1.2/Hasklig-1.2.zip"
    "JetBrainsMono https://github.com/JetBrains/JetBrainsMono/releases/download/v2.242/JetBrainsMono-2.242.zip"
    "Mononoki https://github.com/madmalik/mononoki/releases/download/1.3/mononoki.zip"
    "VictorMono https://rubjo.github.io/victor-mono/VictorMonoAll.zip"
    "Cousine https://fonts.google.com/download?family=Cousine"
    "RobotoMono https://fonts.google.com/download?family=Roboto%20Mono"
    "ShareTechMono https://fonts.google.com/download?family=Share%20Tech%20Mono"
    "SpaceMono https://fonts.google.com/download?family=Space%20Mono"
  )

  for font in "${fonts[@]}"; do
    font_name=$(echo $font | cut -d " " -f 1)
    font_url=$(echo $font | cut -d " " -f 2)

    curl $font_url -sSLo $fonts_path/$font_name.zip \
      --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
    unzip -q $fonts_path/$font_name.zip -d $fonts_path/$font_name

    find $fonts_path/$font_name/ -depth -mindepth 1 -iname "*windows*" -exec rm -r {} +
    find $fonts_path/$font_name/ -depth -mindepth 1 -iname "*macosx*" -exec rm -r {} +
    find $fonts_path/$font_name/ -depth -type f -not -iname "*ttf*" -delete
    find $fonts_path/$font_name/ -empty -type d -delete
    rm -f $fonts_path/$font_name.zip

    echo -e "Font '$font_name' has been installed"
  done

  fc-cache -f

  echo -e "Fonts have been installed under '/usr/share/fonts/nerd-fonts'"

  echo -e "Installing some extra font glyphs..."

  pacman -S ttf-font-awesome noto-fonts-emoji

  echo -e "Extra font glyphs have been installed"

  cp /etc/X11/xinit/xinitrc /home/$username/.xinitrc

  sed -i '/twm &/d' /home/$username/.xinitrc
  sed -i '/xclock -geometry 50x50-1+1 &/d' /home/$username/.xinitrc
  sed -i '/xterm -geometry 80x50+494+51 &/d' /home/$username/.xinitrc
  sed -i '/xterm -geometry 80x20+494-0 &/d' /home/$username/.xinitrc
  sed -i '/exec xterm -geometry 80x66+0+0 -name login/d' /home/$username/.xinitrc

  echo "xsetroot -cursor_name left_ptr" >> /home/$username/.xinitrc
  echo "picom --fade-in-step=1 --fade-out-step=1 --fade-delta=0 &" >> /home/$username/.xinitrc
  echo "~/.fehbg &" >> /home/$username/.xinitrc
  echo "udiskie --notify-command \"ln -s /run/media/$USER $HOME/media/local\" &" >> /home/$username/.xinitrc
  echo "exec bspwm" >> /home/$username/.xinitrc

  chown -R $username:$username /home/$username/.xinitrc

  echo '' >> /home/$username/.bash_profile
  echo '[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx' >> /home/$username/.bash_profile

  echo -e "Setting up the wallpaper..."

  mkdir -p /home/$username/images/wallpapers
  curl https://images.hdqwalls.com/wallpapers/arch-liinux-4k-t0.jpg -sSLo /home/$username/images/wallpapers/arch-liinux-4k-t0.jpg \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60

  chown -R $username:$username /home/$username/images/

  cat << EOF > /home/$username/.fehbg
  #!/bin/sh
  feh --no-fehbg --bg-fill '/home/$username/images/wallpapers/arch-liinux-4k-t0.jpg'
EOF

  chown $username:$username /home/$username/.fehbg
  chmod 754 /home/$username/.fehbg

  echo -e "Wallpaper has been set successfully"

  echo -e "Installing the virtual terminal..."

  pacman -S alacritty

  mkdir -p /home/$username/.config/alacritty

  curl $config_url/alacritty -sSo /home/$username/.config/alacritty/alacritty.yml \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chown -R $username:$username /home/$username/.config/alacritty

  sed -i '/PS1.*/d' /home/$username/.bashrc
  echo -e "\nbranch () {" >> /home/$username/.bashrc
  echo ' git branch 2> /dev/null | sed -e "/^[^*]/d" -e "s/* \(.*\)/  [\\1]/"' >> /home/$username/.bashrc
  echo -e "}\n" >> /home/$username/.bashrc
  echo "PS1='\W\[\e[0;35m\]\$(branch)\[\e[m\]  '" >> /home/$username/.bashrc

  echo -e '\nexport EDITOR="nano"' >> /home/$username/.bashrc

  cp /etc/skel/.bash_profile /root
  cp /etc/skel/.bashrc /root
  sed -i '/PS1.*/d' /root/.bashrc
  echo -e "PS1='\[\e[1;31m\]\u\[\e[m\] \W  '" >> /root/.bashrc

  echo -e "Virtual terminal has been installed"

  echo -e "Installing the theme, icons and cursors..."

  theme_url="https://github.com/dracula/gtk/archive/master.zip"
  curl $theme_url -sSLo /usr/share/themes/Dracula.zip \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  unzip -q /usr/share/themes/Dracula.zip -d /usr/share/themes
  mv /usr/share/themes/gtk-master /usr/share/themes/Dracula
  rm -f /usr/share/themes/Dracula.zip

  echo -e "Theme files have been installed under '/usr/share/themes'"

  icons_url="https://github.com/dracula/gtk/files/5214870/Dracula.zip"
  curl $icons_url -sSLo /usr/share/icons/Dracula.zip \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  unzip -q /usr/share/icons/Dracula.zip -d /usr/share/icons
  rm -f /usr/share/icons/Dracula.zip

  echo -e "Icon files have been installed under '/usr/share/icons'"

  cursors_url="https://www.dropbox.com/s/mqt8s1pjfgpmy66/Breeze-Snow.tgz?dl=0"
  curl $cursors_url -sSLo /usr/share/icons/breeze-snow.tgz \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  tar -xzf /usr/share/icons/breeze-snow.tgz -C /usr/share/icons
  rm -f /usr/share/icons/breeze-snow.tgz

  sed -ri 's/Inherits=.*/Inherits=Breeze-Snow/' /usr/share/icons/default/index.theme

  echo -e "Cursor files have been installed under '/usr/share/icons'"

  mkdir -p /home/$username/.config/gtk-3.0
  curl $config_url/gtk -sSo /home/$username/.config/gtk-3.0/settings.ini \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60

  chown -R $username:$username /home/$username/.config/gtk-3.0

  echo -e "Theme, icons and cursors have been installed"

  echo -e "Installing the file manager..."

  pacman -S nnn fzf

  mkdir -p /home/$username/.config/nnn
  curl $config_url/nnn -sSo /home/$username/.config/nnn/.env_vars \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chown -R $username:$username /home/$username/.config/nnn/
  echo -e '\nsource $HOME/.config/nnn/.env_vars' >> /home/$username/.bashrc

  sed -i 's/Exec=nnn/Exec=alacritty -e nnn/' /usr/share/applications/nnn.desktop

  echo -e "File manager set to get open via terminal in xdg-open calls"

  echo -e "Installing extra nnn plugins..."

  curl https://raw.githubusercontent.com/jarun/nnn/master/plugins/getplugs -sSLo ./nnn-getplugs \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  HOME=/home/$username sh ./nnn-getplugs > /dev/null
  rm -f ./nnn-getplugs

  cp /home/$username/.config/nnn/plugins/mocq /home/$username/.config/nnn/plugins/mocq.bak
  sed -ri 's/(.*)# mocp$/\1alacritty -e mocp \&/' /home/$username/.config/nnn/plugins/mocq

  curl $bin_url/remove-plugin -sSo /home/$username/.config/nnn/plugins/remove \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /home/$username/.config/nnn/plugins/remove

  curl $bin_url/trash-plugin -sSo /home/$username/.config/nnn/plugins/trash \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /home/$username/.config/nnn/plugins/trash

  curl $bin_url/mount-plugin -sSo /home/$username/.config/nnn/plugins/mount \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /home/$username/.config/nnn/plugins/mount

  chown -R $username:$username /home/$username/.config/nnn/plugins

  echo -e "Creating user home directories..."

  mkdir -p /home/$username/downloads \
    /home/$username/documents \
    /home/$username/images \
    /home/$username/audios \
    /home/$username/videos \
    /home/$username/virtuals \
    /home/$username/sources \
    /home/$username/data \
    /home/$username/media

  chown -R $username:$username /home/$username/downloads \
    /home/$username/documents \
    /home/$username/images \
    /home/$username/audios \
    /home/$username/videos \
    /home/$username/virtuals \
    /home/$username/sources \
    /home/$username/data \
    /home/$username/media

  echo -e "Main user home forders have been created"
  echo -e "File manager has been installed"

  echo -e "Installing the music player..."

  sudo pacman -S moc

  echo -e "Installing codecs and various dependecies..."

  sudo pacman -S --asdeps --needed faad2 ffmpeg4.4 libmodplug libmpcdec speex taglib wavpack

  mkdir -p /home/$username/.moc/
  curl $config_url/moc.config -sSo /home/$username/.moc/config \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.moc/config

  mkdir -p /home/$username/.moc/themes
  curl $config_url/moc.theme -sSo /home/$username/.moc/themes/dark \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 644 /home/$username/.moc/themes/dark

  chown -R $username:$username /home/$username/.moc/

  cat << EOF > /usr/share/applications/moc.desktop
[Desktop Entry]
Type=Application
Name=moc
comment=Console music player
Exec=alacritty -e mocp
Terminal=true
Icon=moc
MimeType=audio/mpeg
Catogories=Music;Player;ConsoleOnly
Keywords=Music;Player;Audio
EOF

  echo -e "Music player has been installed"

  echo -e "Installing various document viewers..."

  pacman -S xournalpp poppler foliate

  sudo -u $username yay -S --useask --removemake --nodiffmenu evince-no-gnome > /dev/null

  echo -e "Document viewers have been installed"

  echo -e "Installing the trash..."

  pacman -S trash-cli

  curl $bin_url/trash -sSo /usr/local/bin/trash \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60
  chmod 755 /usr/local/bin/trash

  echo -e '\nalias rr="rm"' >> /home/$username/.bashrc
  echo -e 'alias tt="trash"\n' >> /home/$username/.bashrc

  echo -e "Trash has been installed successfully"

  echo -e "Desktop environment configuration is done"
else
  echo -e "Desktop environment has been skipped"
fi

echo -e "\nInstalling the bootloader via GRUB..."

if [[ $uefi == true ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc $device
fi

sed -i '/#GRUB_SAVEDEFAULT=true/i GRUB_DEFAULT=saved' /etc/default/grub
sed -i 's/#GRUB_SAVEDEFAULT=true/GRUB_SAVEDEFAULT=true/' /etc/default/grub
sed -i 's/#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

if [[ $virtual_box =~ ^(yes|y)$ && $uefi == true ]]; then
  mkdir -p /boot/EFI/BOOT
  cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI
fi

echo -e "Bootloader has been installed"

echo -e "\nHardening system's security..."

sed -i 's;# dir = /var/run/faillock;dir = /var/lib/faillock;' /etc/security/faillock.conf

echo -e "Faillocks set to be persistent after system reboot"

sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config

echo -e "Disable permission for SSH with the root user"

echo -e "Setting up a simple stateful firewall..."

nft flush ruleset
nft add table inet my_table
nft add chain inet my_table my_input '{ type filter hook input priority 0 ; policy drop ; }'
nft add chain inet my_table my_forward '{ type filter hook forward priority 0 ; policy drop ; }'
nft add chain inet my_table my_output '{ type filter hook output priority 0 ; policy accept ; }'
nft add chain inet my_table my_tcp_chain
nft add chain inet my_table my_udp_chain
nft add rule inet my_table my_input ct state related,established accept
nft add rule inet my_table my_input iif lo accept
nft add rule inet my_table my_input ct state invalid drop
nft add rule inet my_table my_input meta l4proto ipv6-icmp accept
nft add rule inet my_table my_input meta l4proto icmp accept
nft add rule inet my_table my_input ip protocol igmp accept
nft add rule inet my_table my_input meta l4proto udp ct state new jump my_udp_chain
nft add rule inet my_table my_input 'meta l4proto tcp tcp flags & (fin|syn|rst|ack) == syn ct state new jump my_tcp_chain'
nft add rule inet my_table my_input meta l4proto udp reject
nft add rule inet my_table my_input meta l4proto tcp reject with tcp reset
nft add rule inet my_table my_input counter reject with icmpx port-unreachable

mv /etc/nftables.conf /etc/nftables.conf.bak
nft -s list ruleset > /etc/nftables.conf

echo -e "Firewall ruleset has been saved to '/etc/nftables.conf'"

cat << EOF > /etc/X11/xorg.conf.d/01-screenlock.conf
# Prevents to overpass screen locker by killing xorg or switching vt
Section "ServerFlags"
    Option "DontVTSwitch" "True"
    Option "DontZap"      "True"
EndSection
EOF

echo -e "Security configuration has been completed"

echo -e "\nConfiguring pacman..."

cat << 'EOF' > /usr/share/libalpm/hooks/orphan-packages.hook
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Search for any left over orphan packages
When = PostTransaction
Exec = /usr/bin/bash -c "/usr/bin/pacman -Qtd || /usr/bin/echo 'No orphan packages found'"
EOF

echo -e "Orphan packages post installation hook has been set"

echo -e "Pacman has been configured"

echo -e "Settin up the login screen"

mv /etc/issue /etc/issue.bak
curl $assets_url/issue -sSo /etc/issue \
  --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60

cat << 'EOF' > /etc/systemd/system/login-issue.service
[Unit]
Description=Set login prompt via /etc/issue
Before=getty@tty1.service getty@tty2.service getty@tty3.service getty@tty4.service getty@tty5.service getty@tty6.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sed -i "5s/.*/  $(date)/" /etc/issue'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable login-issue

sed -ri "s;(ExecStart=-/sbin/agetty)(.*);\1 --nohostname\2;" /lib/systemd/system/getty@.service
sed -ri "s;(ExecStart=-/sbin/agetty)(.*);\1 --nohostname\2;" /lib/systemd/system/serial-getty@.service

echo -e "Login screen has been set"

echo -e "\nEnabling system services..."

systemctl enable systemd-timesyncd
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable acpid
systemctl enable cups
systemctl enable sshd
systemctl enable fstrim.timer
systemctl enable nftables
systemctl enable reflector.timer
systemctl enable paccache.timer

if [[ $virtual_box =~ ^(yes|y)$ ]]; then
  systemctl enable vboxservice
fi

echo -e "\nThe stack script has been completed"
echo -e "Exiting the script and prepare for reboot..."