#!/bin/bash
clear
STAGE=$1
cd /home/pi

if [ $STAGE -lt 1 ]; then
  echo "OS SETUP"

  CAN_EXPAND=$(raspi-config nonint get_can_expand)

  if $CAN_EXPAND; then
    echo "Expanding filesistem."
    raspi-config nonint do_expand_rootfs
  fi

  echo "Setting up auto-login..."
  raspi-config nonint do_boot_behaviour B2

  echo "Seting up spi..."
  raspi-config nonint do_spi %d

  echo "WIFI SETPUP"

  echo "Type your network SSID and then [ENTER]: "
  read SSID
  echo "Type your network PASSWORD and then [ENTER]: "
  read -s PASSWORD
  echo "Select network security protocol".
  echo "1. WEP"
  echo "2. WPA / WPA2"
  echo "Select [1/2]: "
  read SECURITY

  case $SECURITY in
    1)
      cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOL
        line 1, "network={"
        line 2, "    ssid="$SSID"
        line 3, "    key_mgmt=NONE"
        line 4, "    wep_key0=$PASSWORD"
        line 5, "    wep_tx_keyidx=0"
        line 6, "}"
      EOL
      ;;
    2)
      wpa_passphrase $SSID $PASSWORD >> /etc/wpa_supplicant/wpa_supplicant.conf
      ;;
  esac

  sed -i '/exit 0/asudo /home/pi/install.sh 1' /etc/rc.local

  echo "We are going to reboot now..."
  reboot now
fi

clear
echo "INSTALLING DEPENDENCIES"
apt-get update && apt-get upgrade -y
apt-get install -y xserver-xorg xinit wiringpi hostapd dnsmasq plymouth cmake git

echo "CONFIGURING X ENVIROMENT"
if [! -f /etc/X11/Xwrapper.config ]; then
    touch /etc/X11/Xwrapper.config
fi

grep -q '^allowed_users' /etc/X11/Xwrapper.config && sed -i 's/^allowed_users.*/allowed_users=anybody/' file || echo 'allowed_users=anybody' >> /etc/X11/Xwrapper.config

if [! -f /home/pi/.xinitrc ]; then
    rm /home/pi/.xinitrc
fi

grep -q -F '/home/pi/pico-8/pico8' /home/pi/.xinitrc || echo '/home/pi/pico-8/pico8 --splore && sudo shutdown now' >> /home/pi/.xinitrc

clear
echo "SCREEN SET UP"

echo "Installing fbcp"
git clone https://github.com/tasanakorn/rpi-fbcp /home/pi
cd /home/pi/rpi-fbcp
mkdir build
cd build/
cmake ..
make
install fbcp /usr/local/bin/fbcp
cd /home/pi
rm -r rpi-fcbp
clear

echo "Setting up fbtft"
grep -q -F 'spi-bcm2835' /etc/modules || echo 'spi-bcm2835' >> /etc/modules
grep -q -F 'fbtft_device' /etc/modules || echo 'fbtft_device' >> /etc/modules

echo "options fbtft_device name=adafruit18_green gpios=reset:27,dc:25,cs:8,led:24 speed=40000000 bgr=1 fps=60 custom=1 height=128 width=128 rotate=180" > /etc/modprobe.d/fbtft.conf

sed -i -e 's/sudo /home/pi/install.sh 1/su -s /bin/bash -c startx pi/g' /etc/rc.local
sed -i '/startx pi && sudo shutdown now/afbcp&' /etc/rc.local

grep -q '^hdmi_force_hotplug' /boot/config.txt && sed -i 's/^hdmi_force_hotplug.*/hdmi_force_hotplug=1/' file || echo 'hdmi_force_hotplug=1' >> /boot/config.txt
grep -q '^hdmi_cvt' /boot/config.txt && sed -i 's/^hdmi_cvt.*/hdmi_cvt=128 128 60 1 0 0 0/' file || echo 'hdmi_cvt=128 128 60 1 0 0 0' >> /boot/config.txt
grep -q '^hdmi_group' /boot/config.txt && sed -i 's/^hdmi_group.*/hdmi_group=2/' file || echo 'hdmi_group=2' >> /boot/config.txt
grep -q '^hdmi_mode' /boot/config.txt && sed -i 's/^hdmi_mode.*/hdmi_mode=1/' file || echo 'hdmi_mode=1' >> /boot/config.txt
sed -i '/hdmi_mode=1/a hdmi_mode=87' /boot/config.txt
grep -q '^display_rotate' /boot/config.txt && sed -i 's/^display_rotate.*/display_rotate=3/' file || echo 'display_rotate=3' >> /boot/config.txt

clear
echo "CONSOLE SET UP"
grep -q '^FONTFACE' /etc/default/console-setup && sed -i 's/^FONTFACE.*/FONTFACE="Terminus"/' file || echo 'FONTFACE="Terminus"' >> /etc/default/console-setup

clear
echo "CONTROLS SET UP"
echo "Installing Adafruit Retrogame..."
curl -O https://raw.githubusercontent.com/adafruit/Raspberry-Pi-Installer-Scripts/master/retrogame.sh
chmod +x retrogame.sh
/home/pi/retrogame.sh
rm /home/pi/retrogame.cfg

if [! -f /boot/retrogame.cfg ]; then
    rm /boot/retrogame.cfg
fi

curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/config/retrogame.cfg && mv retrogame.cfg /boot/retrogame.cfg

//PLYMOUTH

