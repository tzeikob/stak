#!/usr/bin/env bash

set -Eeo pipefail

install_packages () {
  echo -e "\nInstalling various system packages..."

  yay -S --noconfirm --removemake digimend-kernel-drivers-dkms-git || exit 1
  
  echo "Packages have been installed"
}

install_compositor () {
  echo "Installing the picom compositor..."

  sudo pacman -S --noconfirm picom || exit 1

  local CONFIG_HOME=~/.config/picom
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/picom/picom.conf "$CONFIG_HOME"

  if [ "$VIRTUAL_VENDOR" = "oracle" ]; then
    echo "Virtual box machine detected"
 
    sed -i 's/\(vsync =\).*/\1 false;/' "$CONFIG_HOME/picom.conf"
    echo -e "Vsync has been disabled"
  fi

  echo "Configuration has been set under ~/.config/picom"
  echo "Compositor has been installed"
}

install_window_manager () {
  echo "Installing BSPWM as the window manager..."

  sudo pacman -S --noconfirm bspwm || exit 1

  local CONFIG_HOME=~/.config/bspwm
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/bspwm/bspwmrc "$CONFIG_HOME"
  chmod 755 "$CONFIG_HOME/bspwmrc"

  cp ~/stack/configs/bspwm/rules "$CONFIG_HOME"
  chmod 755 "$CONFIG_HOME/rules"

  cp ~/stack/configs/bspwm/resize "$CONFIG_HOME"
  chmod 755 "$CONFIG_HOME/resize"

  cp ~/stack/configs/bspwm/swap "$CONFIG_HOME"
  chmod 755 "$CONFIG_HOME/swap"

  cp ~/stack/configs/bspwm/scratchpad "$CONFIG_HOME"
  chmod 755 "$CONFIG_HOME/scratchpad"

  echo "Window manager has been installed"
}

install_terminals () {
  echo "Installing virtual terminals..."

  echo "Installing alacritty as the terminal..."

  sudo pacman -S --noconfirm alacritty || exit 1

  echo "export TERMINAL=alacritty" >> ~/.bashrc

  mkdir -p ~/.config/alacritty
  cp ~/stack/configs/alacritty/alacritty.yml ~/.config/alacritty

  sed -i '/PS1.*/d' ~/.bashrc
  cat ~/stack/configs/alacritty/user.prompt >> ~/.bashrc

  sudo cp /etc/skel/.bash_profile /root
  sudo cp /etc/skel/.bashrc /root

  sudo sed -i '/PS1.*/d' /root/.bashrc
  cat ~/stack/configs/alacritty/root.prompt | sudo tee -a /root/.bashrc > /dev/null

  echo "Terminal prompt hooks have been set"

  echo "Installing the cool retro terminal..."

  sudo pacman -S --noconfirm cool-retro-term || exit 1

  echo "Installing various terminal utilities..."

  yay -S --noconfirm --removemake smenu || exit 1

  echo "Virtual terminals have been installed"
}

install_file_manager () {
  echo "Installing the file manager..."

  sudo pacman -S --noconfirm nnn fzf || exit 1

  local CONFIG_HOME=~/.config/nnn
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/nnn/env "$CONFIG_HOME"

  echo 'source "$HOME/.config/nnn/env"' >> ~/.bashrc
  echo 'alias N="sudo -E nnn -dH"' >> ~/.bashrc
  echo 'export EDITOR=nano' >> ~/.bashrc

  echo "Installing extra nnn plugins..."

  local GETPLUGS_URL="https://raw.githubusercontent.com/jarun/nnn/master/plugins/getplugs"

  curl "$GETPLUGS_URL" -sSLo "$CONFIG_HOME/getplugs" \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60 || exit 1
  HOME=~/ sh "$CONFIG_HOME/getplugs" > /dev/null || exit 1

  sed -ri 's/(.*)# mocp$/\1\$TERMINAL -e mocp \&/' "$CONFIG_HOME/plugins/mocq"

  echo "Extra plugins have been installed"

  mkdir -p ~/downloads ~/documents ~/images ~/audios ~/videos ~/virtuals ~/sources ~/data ~/mounts
  cp ~/stack/configs/nnn/user.dirs ~/.config/user-dirs.dirs

  echo "User home directories have been created"

  printf '%s\n' \
    '[Default Applications]' \
    'inode/directory=nnn.desktop' > ~/.config/mimeapps.list

  chmod 644 ~/.config/mimeapps.list

  echo "Application mime types file has been created"
  echo "File manager has been installed"
}

install_trash () {
  echo "Installing the trash via the trash-cli..."

  sudo pacman -S --noconfirm trash-cli || exit 1

  sed -ri "/alias ls=.*/a alias sudo='sudo '" ~/.bashrc
  sed -ri "/alias ls=.*/a alias tt='trash-put -i'" ~/.bashrc
  sed -ri "/alias ls=.*/a alias rm='rm -i'" ~/.bashrc
  
  sudo sed -ri "/alias ls=.*/a alias sudo='sudo '" /root/.bashrc
  sudo sed -ri "/alias ls=.*/a alias tt='trash-put -i'" /root/.bashrc
  sudo sed -ri "/alias ls=.*/a alias rm='rm -i'" /root/.bashrc

  echo "Trash has been installed"
}

install_bars () {
  echo "Setting up the status bar via polybar..."

  sudo pacman -S --noconfirm polybar || exit 1

  local CONFIG_HOME=~/.config/polybar
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/polybar/config.ini "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/config.ini"
  
  cp ~/stack/configs/polybar/modules.ini "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/modules.ini"
  
  cp ~/stack/configs/polybar/theme.ini "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/theme.ini"

  local SCRIPTS_HOME="${CONFIG_HOME}/scripts"
  mkdir -p "${SCRIPTS_HOME}"

  cp ~/stack/configs/polybar/scripts/time "${SCRIPTS_HOME}"
  chmod +x "${SCRIPTS_HOME}/time"

  cp ~/stack/configs/polybar/scripts/speakers "${SCRIPTS_HOME}"
  chmod +x "${SCRIPTS_HOME}/speakers"
  
  cp ~/stack/configs/polybar/scripts/microphone "${SCRIPTS_HOME}"
  chmod +x "${SCRIPTS_HOME}/microphone"

  echo "Status bars have been installed"
}

install_sounds () {
  echo 'Installing extra system sounds...'

  local sounds_home='/usr/share/sounds/stack'
  
  sudo mkdir -p "${sounds_home}"
  
  sudo cp ~/stack/resources/sounds/normal.wav "${sounds_home}"
  sudo cp ~/stack/resources/sounds/critical.wav "${sounds_home}"

  echo 'System sounds have been installed'
}

install_notifier () {
  echo "Installing notifications server..."

  sudo pacman -S --noconfirm dunst || exit 1

  mkdir -p ~/.config/dunst
  cp ~/stack/configs/dunst/dunstrc ~/.config/dunst
  cp ~/stack/configs/dunst/hook ~/.config/dunst

  echo "Notifications server has been installed"
}

install_launchers () {
  echo "Setting up the launchers via rofi..."

  sudo pacman -S --noconfirm rofi || exit 1

  local CONFIG_HOME=~/.config/rofi
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/rofi/config.rasi "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/config.rasi"

  cp ~/stack/configs/rofi/launch "$CONFIG_HOME"
  chmod +x "${CONFIG_HOME}/launch"

  echo "Launchers has been installed"
}

install_login_screen () {
  echo "Setting up the getty login screen..."

  sudo pacman -S --noconfirm figlet || exit 1
  yay -S --noconfirm --removemake figlet-fonts figlet-fonts-extra || exit 1

  sudo mv /etc/issue /etc/issue.bak
  mkdir -p ~/.config/getty
  sudo cp ~/stack/configs/getty/update-issue ~/.config/getty

  echo "Welcome screen theme has been set"

  sudo cp ~/stack/configs/getty/login-issue.service /etc/systemd/system
  sudo systemctl enable login-issue || exit 1

  sudo sed -ri "s;(ExecStart=-/sbin/agetty)(.*);\1 --nohostname\2;" /lib/systemd/system/getty@.service
  sudo sed -ri "s;(ExecStart=-/sbin/agetty)(.*);\1 --nohostname\2;" /lib/systemd/system/serial-getty@.service

  echo "Login issue service has been enabled"
  echo "Login screen has been set"
}

install_monitors () {
  echo "Installing monitoring tools..."

  sudo pacman -S --noconfirm htop glances || exit 1

  mkdir -p ~/.local/share/applications
  cp ~/stack/configs/glances/desktop ~/.local/share/applications/glances.desktop

  echo "Monitoring tools have been installed"
}

install_break_timer () {
  echo "Installing the break timer tool..."

  yay -S --noconfirm --removemake breaktimer-bin || exit 1

  cp ~/stack/configs/break/config.json ~/.config/BreakTimer/config.json

  echo "Break timer tool has been installed"
}

install_screenlocker () {
  echo 'Installing the screen locker...'

  pip3 install python-pam screeninfo || exit 1

  local prev_wd="$(echo ${PWD})}"
  cd ~
  git clone https://github.com/tzeikob/xsecurelock.git || exit 1
  cd xsecurelock
  sh autogen.sh || exit 1
  ./configure --with-pam-service-name=system-auth || exit 1
  make || exit 1
  sudo make install || exit 1
  cd "${prev_wd}"
  rm -rf ~/xsecurelock

  sudo cp ~/stack/configs/xsecurelock/hook /usr/lib/systemd/system-sleep/locker

  local user_id="$(id -u "${USERNAME}")"
  sudo cp ~/stack/configs/xsecurelock/service /etc/systemd/system/lock@.service
  sudo sed -i "s/#USER_ID/${user_id}/g" /etc/systemd/system/lock@.service
  sudo systemctl enable lock@${USERNAME}.service

  echo 'Screen locker has been install'
}

install_screencasters () {
  echo "Installing screen casting tools..."

  sudo pacman -S --noconfirm scrot || exit 1

  yay -S --noconfirm --removemake --mflags --nocheck slop screencast || exit 1

  echo "Screen casting tools have been installed"
}

install_calculator () {
  echo "Installing calculator..."

  yay -S --noconfirm --removemake libqalculate kalker || exit 1

  mkdir -p ~/.local/share/applications
  cp ~/stack/configs/kalker/desktop ~/.local/share/applications/kalker.desktop
  cp ~/stack/configs/qalculate/desktop ~/.local/share/applications/qalculate.desktop

  echo "Calculator has been installed"
}

install_media_apps () {
  echo "Installing media applications..."

  sudo pacman -S --noconfirm moc mpv sxiv || exit 1

  echo "Installing codecs and various dependecies..."

  sudo pacman -S --noconfirm --asdeps --needed \
    faad2 ffmpeg4.4 libmodplug libmpcdec speex taglib wavpack || exit 1

  local CONFIG_HOME=~/.moc
  mkdir -p "$CONFIG_HOME" "$CONFIG_HOME/themes"

  cp ~/stack/configs/moc/config "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/config"

  cp ~/stack/configs/moc/dark "$CONFIG_HOME/themes"
  chmod 644 "$CONFIG_HOME/themes/dark"

  mkdir -p ~/.local/share/applications
  cp ~/stack/configs/moc/desktop ~/.local/share/applications/moc.desktop

  printf '%s\n' \
    'image/jpeg=sxiv.desktop' \
    'image/jpg=sxiv.desktop' \
    'image/png=sxiv.desktop' \
    'image/tiff=sxiv.desktop' \
    'audio/mpeg=moc.desktop' \
    'audio/mp3=moc.desktop' \
    'audio/flac=moc.desktop' \
    'audio/midi=moc.desktop' \
    'video/mp4=mpv.desktop' \
    'video/mkv=mpv.desktop' \
    'video/mov=mpv.desktop' \
    'video/mpeg=mpv.desktop' \
    'video/avi=mpv.desktop' >> ~/.config/mimeapps.list
  
  echo "Mime types have been added"
  echo -e "Media applications have been installed"
}

install_theme () {
  echo "Installing theme, icons and cursors..."

  local THEME_URL="https://github.com/dracula/gtk/archive/master.zip"

  sudo curl "$THEME_URL" -sSLo /usr/share/themes/Dracula.zip \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60 || exit 1
  sudo unzip -q /usr/share/themes/Dracula.zip -d /usr/share/themes || exit 1
  
  sudo mv /usr/share/themes/gtk-master /usr/share/themes/Dracula
  sudo rm -f /usr/share/themes/Dracula.zip

  echo "Theme has been installed"

  local ICONS_URL="https://github.com/dracula/gtk/files/5214870/Dracula.zip"

  sudo curl "$ICONS_URL" -sSLo /usr/share/icons/Dracula.zip \
    --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60 || exit 1

  sudo unzip -q /usr/share/icons/Dracula.zip -d /usr/share/icons || exit 1
  sudo rm -f /usr/share/icons/Dracula.zip

  echo "Theme icons have been installed"

  local CURSORS_URL="https://www.dropbox.com/s/mqt8s1pjfgpmy66/Breeze-Snow.tgz?dl=1"

  sudo wget "$CURSORS_URL" -qO /usr/share/icons/breeze-snow.tgz \
    --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 3 || exit 1

  sudo tar -xzf /usr/share/icons/breeze-snow.tgz -C /usr/share/icons || exit 1
  sudo sed -ri 's/Inherits=.*/Inherits=Breeze-Snow/' /usr/share/icons/default/index.theme
  sudo rm -f /usr/share/icons/breeze-snow.tgz

  echo "Cursors have been installed"

  local GTK_HOME=~/.config/gtk-3.0
  mkdir -p "$GTK_HOME"

  cp ~/stack/configs/gtk/settings.ini "$GTK_HOME"

  local WALLPAPERS=~/.local/share/wallpapers
  mkdir -p "$WALLPAPERS"
  cp ~/stack/configs/feh/wallpaper.jpeg "$WALLPAPERS/default.jpeg"

  local CONFIG_HOME=~/.config/stack
  mkdir -p "$CONFIG_HOME"
  echo '{"theme": {"wallpaper": {"file": "default.jpeg", "mode": "fill"}}}' > "$CONFIG_HOME/.settings"

  echo "Default wallpaper has been set"
  echo "Theme has been setup"
}

install_fonts () {
  echo -e "\nInstalling extra fonts..."

  local FONTS_HOME="/usr/share/fonts/extra-fonts"
  sudo mkdir -p "$FONTS_HOME"

  local FONTS=(
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
    "PixelMix https://dl.dafont.com/dl/?f=pixelmix"
  )

  for FONT in "${FONTS[@]}"; do
    local NAME=$(echo "$FONT" | cut -d " " -f 1)
    local URL=$(echo "$FONT" | cut -d " " -f 2)

    sudo curl "$URL" -sSLo "$FONTS_HOME/$NAME.zip" \
      --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 0 --retry-max-time 60 || exit 1
    sudo unzip -q "$FONTS_HOME/$NAME.zip" -d "$FONTS_HOME/$NAME" || exit 1

    sudo find "$FONTS_HOME/$NAME/" -depth -mindepth 1 -iname "*windows*" -exec rm -r {} +
    sudo find "$FONTS_HOME/$NAME/" -depth -mindepth 1 -iname "*macosx*" -exec rm -r {} +
    sudo find "$FONTS_HOME/$NAME/" -depth -type f -not -iname "*ttf*" -delete
    sudo find "$FONTS_HOME/$NAME/" -empty -type d -delete
    sudo rm -f "$FONTS_HOME/$NAME.zip"

    echo "Font $NAME has been installed"
  done

  fc-cache -f

  echo "Fonts have been installed under $FONTS_HOME"

  echo -e "\nInstalling some extra font glyphs..."

  sudo pacman -S --noconfirm \
    ttf-font-awesome noto-fonts-emoji || exit 1

  echo "Extra font glyphs have been installed"
}

setup_bindings () {
  echo "Setting up key bindings via sxhkd..."

  sudo pacman -S --noconfirm sxhkd || exit 1

  local CONFIG_HOME=~/.config/sxhkd
  mkdir -p "$CONFIG_HOME"

  cp ~/stack/configs/sxhkd/sxhkdrc "$CONFIG_HOME"
  chmod 644 "$CONFIG_HOME/sxhkdrc"

  echo "Key bindings have been set"
}

echo -e "\nStarting the desktop installation process..."

if [[ "$(id -u)" == "0" ]]; then
  echo -e "\nError: process must be run as non root user"
  echo "Process exiting with code 1..."
  exit 1
fi

source ~/stack/.options

install_packages &&
  install_compositor &&
  install_window_manager &&
  install_terminals &&
  install_file_manager &&
  install_trash &&
  install_bars &&
  install_sounds &&
  install_notifier &&
  install_launchers &&
  install_login_screen &&
  install_monitors &&
  install_break_timer &&
  install_screenlocker &&
  install_screencasters &&
  install_calculator &&
  install_media_apps &&
  install_theme &&
  install_fonts &&
  setup_bindings

echo -e "\nSetting up the desktop has been completed"
echo "Moving to the next process..."
sleep 5
