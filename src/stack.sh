#!/bin/bash
# A bash script to setup a development stack environment

# Read command line options
yesToAll=false

while getopts y OPT; do
  case "$OPT" in
    y) yesToAll=true
  esac
done

# Set current relative path
dir=$(dirname $0)

# Load global goodies
source $dir"/global.sh"

# Initiate local variables
now=$(date)
distro=$(lsb_release -si)
version=$(lsb_release -sr)

# Print welcome screen
log "Scriptbox v1.0.0\n"
log "Date: $(d "$now")"
log "System: $(d "$distro $version")"
log "Host: $(d $HOSTNAME)"
log "User: $(d $USER)\n"

# Create temporary files folder
temp="/tmp/scriptbox/stack"

log "Creating temporary files folder."

mkdir -p $temp

info "Temporary files folder $temp has been created.\n"

# Rename default home folders
if [[ $yesToAll = false ]]; then
  read -p "Do you want to rename the default home folders?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Renaming the default home folders to lower case."

  mv /home/$USER/Desktop /home/$USER/desktop
  mv /home/$USER/Downloads /home/$USER/downloads
  mv /home/$USER/Templates /home/$USER/templates
  mv /home/$USER/Public /home/$USER/public
  mv /home/$USER/Documents /home/$USER/documents
  mv /home/$USER/Music /home/$USER/music
  mv /home/$USER/Pictures /home/$USER/pictures
  mv /home/$USER/Videos /home/$USER/videos

  # Update the user dirs file
  userdirs="/home/$USER/.config/user-dirs.dirs"

  log "Updating the user dirs file $userdirs."

  cp $userdirs $userdirs.bak

  log "The user dirs file has been backed up to $userdirs.bak file."

  log "Replacing the contents of the user dirs file."

  > $userdirs
  echo "XDG_DESKTOP_DIR=\"$HOME/desktop\"" >> $userdirs
  echo "XDG_DOWNLOAD_DIR=\"$HOME/downloads\"" >> $userdirs
  echo "XDG_TEMPLATES_DIR=\"$HOME/templates\"" >> $userdirs
  echo "XDG_PUBLICSHARE_DIR=\"$HOME/public\"" >> $userdirs
  echo "XDG_DOCUMENTS_DIR=\"$HOME/documents\"" >> $userdirs
  echo "XDG_MUSIC_DIR=\"$HOME/music\"" >> $userdirs
  echo "XDG_PICTURES_DIR=\"$HOME/pictures\"" >> $userdirs
  echo "XDG_VIDEOS_DIR=\"$HOME/videos\"" >> $userdirs

  log "User dirs file has been updated successfully."

  # Update the nautilus bookmarks file
  bookmarks_file="/home/$USER/.config/gtk-3.0/bookmarks"

  log "Updating the nautilus bookmarks file $bookmarks_file."

  cp $bookmarks_file $bookmarks_file.bak

  log "The nautilus bookmarks has been backed up to $bookmarks_file.bak. file"

  > $bookmarks_file
  echo "file:///home/"$USER"/downloads Downloads" | tee -a $bookmarks_file
  echo "file:///home/"$USER"/documents Documents" | tee -a $bookmarks_file
  echo "file:///home/"$USER"/music Music" | tee -a $bookmarks_file
  echo "file:///home/"$USER"/pictures Pictures" | tee -a $bookmarks_file
  echo "file:///home/"$USER"/videos Videos" | tee -a $bookmarks_file

  info "The default home folders have been renamed successfully.\n"
fi

# Upgrade the system
if [[ $yesToAll = false ]]; then
  read -p "Do you want to upgrade your system?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Upgrading the base system with the latest updates."

  sudo apt -q update
  sudo apt -y -q upgrade

  log "Removing any not used packages."

  sudo apt -y -q autoremove

  log "Installing third-party software dependencies."

  packages=(tree curl unzip htop gconf-service gconf-service-backend gconf2
            gconf2-common libappindicator1 libgconf-2-4 libindicator7
            libpython-stdlib python python-minimal python2.7 python2.7-minimal libatomic1
            gimp vlc)

  sudo apt install -y -q ${packages[@]}

  info "System has been updated successfully.\n"
fi

# Install system languages
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install more languages [Greek]?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing the greek language packages."

  sudo apt install -y -q `check-language-support -l el`

  log "Adding greek layout into the keyboard input sources."

  gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'gr')]"

  log "Set regional formats back to US."

  sudo update-locale LANG=en_US.UTF-8
  sudo update-locale LANGUAGE=
  sudo update-locale LC_CTYPE="en_US.UTF-8"
  sudo update-locale LC_NUMERIC=en_US.UTF-8
  sudo update-locale LC_TIME=en_US.UTF-8
  sudo update-locale LC_COLLATE="en_US.UTF-8"
  sudo update-locale LC_MONETARY=en_US.UTF-8
  sudo update-locale LC_MESSAGES="en_US.UTF-8"
  sudo update-locale LC_PAPER=en_US.UTF-8
  sudo update-locale LC_NAME=en_US.UTF-8
  sudo update-locale LC_ADDRESS=en_US.UTF-8
  sudo update-locale LC_TELEPHONE=en_US.UTF-8
  sudo update-locale LC_MEASUREMENT=en_US.UTF-8
  sudo update-locale LC_IDENTIFICATION=en_US.UTF-8
  sudo update-locale LC_ALL=
  locale

  info "System languages have been updated successfully.\n"
fi

# Set local RTC time
if [[ $yesToAll = false ]]; then
  read -p "Do you want to use local RTC time?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Setting the system to use local time instead of UTC."

  timedatectl set-local-rtc 1 --adjust-system-clock
  gsettings set org.gnome.desktop.interface clock-show-date true

  info "System has been set to use local time successfully.\n"
fi

# Disable screen lock
if [[ $yesToAll = false ]]; then
  read -p "Do you want to disable screen lock?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Disabling screen lock."

  gsettings set org.gnome.desktop.screensaver lock-enabled false
  gsettings set org.gnome.desktop.session idle-delay 0
  gsettings set org.gnome.settings-daemon.plugins.power idle-dim false

  info "Screen lock has been disabled successfully.\n"
fi

# Install dropbox
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install dropbox?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing the latest verion of dropbox."

  dropbox_list=/etc/apt/sources.list.d/dropbox.list
  sudo touch $dropbox_list
  sudo echo "deb [arch=i386,amd64] http://linux.dropbox.com/ubuntu $(lsb_release -cs) main" | sudo tee -a $dropbox_list
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1C61A2656FB57B7E4DE0F4C1FC918B335044912E

  sudo apt update -q
  sudo apt install -y -q python3-gpg dropbox

  info "Dropbox has been installed successfully.\n"

  log "Starting the dropbox daemon."

  dropbox start -i &>/dev/null

  info "Dropbox has been installed successfully.\n"
fi

# Install chrome
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install chrome?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Downloading the latest version of chrome."

  wget -q --show-progress -P $temp https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

  log "Installing chrome using deb packaging."

  sudo dpkg -i $temp/google-chrome-stable_current_amd64.deb

  info "Chrome has been installed successfully.\n"
fi

# Install skype
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install skype?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Downloading the latest version of skype."

  wget -q --show-progress -P $temp https://repo.skype.com/latest/skypeforlinux-64.deb

  log "Installing skype using deb packaging."

  sudo dpkg -i $temp/skypeforlinux-64.deb

  info "Skype has been installed successfully.\n"
fi

# Install slack
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install slack?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing the slack."

  sudo apt install -y -q slack

  info "Slack has been installed successfully.\n"
fi

# Install virtualbox
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install virtual box?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing the virtual box."

  sudo add-apt-repository -y multiverse

  sudo apt update -q
  sudo apt install -y -q virtualbox

  info "Virtual box has been installed successfully.\n"
fi

# Install git
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install git?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing the git."

  ppa="git-core/ppa"

  if ! grep -q "^deb .*$ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
   sudo add-apt-repository -y ppa:$ppa
   sudo apt update -q
  fi

  sudo apt install -y -q git

  read -p "Enter your git username:($USER) " username

  if [[ $username == "" ]]; then
   username = $USER
  fi

  git config --global user.name "$username"

  log "Git username has been set to $(git config --global user.name)."

  read -p "Enter your git email:($USER@$HOSTNAME) " email

  if [[ $email == "" ]]; then
   email = $USER@$HOSTNAME
  fi

  git config --global user.email "$email"

  log "Git email has been set to $(git config --global user.email)."

  info "Git has been installed successfully.\n"
fi

# Install node
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install node?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing node via nvm."

  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash

  source /home/$USER/.bashrc
  source /home/$USER/.nvm/nvm.sh

  nvm install --lts
  nvm install node
  nvm use --lts

  log "Currently installed node versions:"
  nvm ls

  info "Node has been installed successfully in /home/$USER/.nvm/versions/node.\n"
fi

# Install java
if [[ $yesToAll = false ]]; then
  read -p "Do you want to install java [openjdk-8, openjdk-13, maven]?(Y/n) " answer
else
  answer="yes"
fi

if [[ $answer =~ $yes ]]; then
  log "Installing open JDK 8."

  sudo apt install -y -q openjdk-8-jdk openjdk-8-doc openjdk-8-source

  log "Open JDK 8 has been installed successfully."

  log "Installing open JDK 11 (LTS)."

  sudo apt install -y -q openjdk-11-jdk openjdk-11-doc openjdk-11-source

  log "Open JDK 11 (LTS) has been installed successfully."

  log "Configuring update alternatives."

  sudo update-alternatives --config java

  log "Installing the maven."

  sudo apt install -y -q maven

  info "Java has been installed successfully."
fi

log "Cleaning up the temporary files."

rm -rf $temp
