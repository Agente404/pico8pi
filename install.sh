#!/bin/bash
# pico8pi configuration utility.

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end
if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
}

get_config_var() {
  lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
  local val = line:match("^#?%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    break
  end
end
EOF
}

setup_wifi() {
    echo "net.ipv6.conf.all.disable_ipv6=1" > /etc/sysctl.d/local.conf
    wpa_passphrase $1 $2 > tee -a /etc/wpa_supplicant/wpa_supplicant.conf
    wpa_cli -i wlan0 reconfigure
}

#Welcome message
echo "Welcome to your new Raspberry Pi Zero Pico-8 console"
echo "Please wait while the script configure the system"
cd

#Variable definition
BLACKLIST=/etc/modprobe.d/raspi-blacklist.conf
CONFIG=/boot/config.txt
XCONFIG=/etc/X11/Xwrapper.config
HOSTNAME=pico8
GPU_MEM=256

#Change hostname
CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`

echo $HOSTNAME > /etc/hostname
sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$HOSTNAME/g" /etc/hosts

#Enable SSH
update-rc.d ssh enable && invoke-rc.d ssh start

#Enable SPI
set_config_var dtparam=spi "on" $CONFIG

#Set GPU memory split
CUR_GPU_MEM=$(get_config_var gpu_mem $CONFIG)
[ -z "$CUR_GPU_MEM" ] && CUR_GPU_MEM=64
set_config_var gpu_mem "$GPU_MEM" $CONFIG

#Boot to console
#TODO

#Configure WIFI

echo "In order to install some required packages you'll need an internet connection."

until [[ "$REPLY" =~ ^[YyNn] ]]; do
	read -p "Would you like to configure WIFI (y/n): " -n 1 -r
	echo

	case "$REPLY" in
	  y|Y )
		read -p "Enter network SSID: " SSID
		read -p "Enter passphrase: " PASSWORD
		setup_wifi $SSID $PASSWORD
		;;
	  n|N )
		echo "Skiping..."
		;;
	  * )
		echo "Invalid option, retrying..."
		;;
	esac
done

#Install dependencies
echo "Now we are going to install some dependencies. Please be patient."
#apt-get update && apt-get upgrade -y && apt-get install -y wiringpi hostapd dnsmasq plymouth cmake git && apt-get install -y --no-install-recommends xserver-xorg xinit
#systemctl disable hostapd && systemctl disable dnsmasq

#Configure X11
echo "Setting up X11 enviroment"
set_config_var allowed_users anybody $XCONFIG

if ! grep -qF "su -s /bin/bash -c startx pi> /dev/null 2>&1 &" /etc/rc.local; then
	sed -i '/^\(exit 0\)/ i su -s \/bin\/bash -c startx pi> \/dev\/null 2>&1 &' /etc/rc.local
fi

#Setting up auto AP mode

echo "Setting up auto AP mode"
VERSION1="$(dpkg -s dnsmasq | grep -oP '(?<=Version: )(.*)(?=\.)')"
VERSION2="$(dpkg -s dnsmasq | grep -oP '(?<=Version: [0-9].)(.*)(?=\-)')"

if [ $VERSION1 -le 1 ] && [$VERSION2 -le 77] ; then
        echo "There is a bug with dnsmasq versions lower than 1.77. So we need to uninstall dns-root-data package"
        apt-get purge -y dns-root-data
fi

echo "Downloading hostapd config file"
curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/wifi/hostapd.conf
mv hostapd.conf /etc/hostapd/hostapd.conf

echo "When no Wifi you could connect to the Pico8 AP".
echo "You need to set a password for the AP (default is 1234567890)".

read -p "Enter your new AP password (at least 8 characters): " PASSWORD

until [ ${#PASSWORD} -ge 8 ]; do
	echo "Password has to be at least 8 characters long"
	read -p "Enter your new AP password (at least 8 characters): " PASSWORD
done

set_config_var wpa_passphrase $PASSWORD /etc/hostapd/hostapd.conf
set_config_var DAEMON_CONF "/etc/hostapd/hostapd.conf" /etc/default/hostapd


if ! grep -qF "#AutoHotspot Config" /etc/dnsmasq.conf; then
	curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/wifi/dnsmasq.conf
	cat dnsmasq.conf >> /etc/dnsmasq.conf
	rm dnsmasq.conf
fi

#Autohotspot service
curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/wifi/autohotspot.service
mv autohotspot.service /etc/systemd/system/autohotspot.service
systemctl enable autohotspot.service

#Script autohotspot monitor
curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/wifi/autohotspot
mv autohotspot /usr/bin/autohotspot
chmod +x /usr/bin/autohotspot

#Cron job
crontab -l | { cat; echo "*/5 * * * * sudo /usr/bin/autohotspot"; } | crontab -

#FBTFT AND FBCOPY
echo "Now we are going to configure the screen"
echo "Lets install FBCP. This may take a while"

#git clone https://github.com/tasanakorn/rpi-fbcp && cd rpi-fbcp/
#mkdir build && cd build/
#cmake ..
#make
#install fbcp /usr/local/bin/fbcp
#cd
#rm -r /home/pi/rpi-fbcp

echo "Setting up FBTFT"
if ! grep -qF "spi-bcm2835" /etc/modules; then
	echo "spi-bcm2835" >> /etc/modules
fi

if ! grep -qF "fbtft_device" /etc/modules; then
	echo "fbtft_device" >> /etc/modules
fi

echo "options fbtft_device name=adafruit18_green gpios=reset:27,dc:25,cs:8,led:24 speed=40000000 bgr=1 fps=60 custom=1 height=128 width=128 rotate=90" > /etc/modprobe.d/fbtft.conf

#SCREEN SET UP
echo "Setting up screen"
set_config_var hdmi_force_hotplug 1 $CONFIG
set_config_var hdmi_cvt "128 128 60 1 0 0 0" $CONFIG
set_config_var hdmi_group 2 $CONFIG
set_config_var hdmi_mode 87 $CONFIG
set_config_var framebuffer_width 128 $CONFIG
set_config_var framebuffer_height 128 $CONFIG
set_config_var disable_splash 1 $CONFIG

if ! grep -qF "hdmi_mode=1" /boot/config.txt; then
        sed -i '/^\(hdmi_mode=87\)/ i hdmi_mode=1' /boot/config.txt
fi


if ! grep -qF "fbcp&" /etc/rc.local; then
        sed -i '/^\(su -s \/bin\/bash -c startx pi> \/dev\/null 2>&1 &\)/ i fbcp&' /etc/rc.local
fi

echo "Setting console font"
set_config_var FONTFACE "Terminus" /etc/default/console-setup
set_config_var FONTSIZE "6x12" /etc/default/console-setup

#CONFIGURING PICO-8
echo "Setting up Pico-8"

PICO8="/home/pi/pico-8/pico8 -splore && sudo shutdown now"

if ! grep -qF "$PICO8" /home/pi/.xinitrc; then
	echo "$PICO8" >> /home/pi/.xinitrc
fi

mkdir /home/pi/screenshots
mkdir /home/pi/carts

curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/config/pico8.cfg
mv pico8.cfg /home/pi/.lexaloffle/pico-8/config.txt

chown -R pi:pi /home/pi/carts/ /home/pi/screenshots/ /home/pi/pico-8/ /home/pi/.xinitrc /home/pi/.lexaloffle/pico-8/config.txt
chmod +x /home/pi/pico-8/pico8

#SETTING UP SPLASH SCREEN
echo "Setting up splash screen"
#Download theme

#Set theme
plymouth-set-default-theme pico-theme
update-initramfs -u

#Edit cmdline.txt
sed -i '1 s/$/ fsck.mode=skip fbcon=map:01 quiet splash logo.nologo plymouth.ignore-serial-consoles vt.global_cursor_default=0/' /boot/cmdline.txt

#SETTING UP CONTROLS
echo "Now we are going to make those buttons works"
#git clone https://github.com/adafruit/Adafruit-Retrogame
#cd Adafruit-Retrogame
#make install
#cd
#rm -r Adafruit-Retrogame
echo "SUBSYSTEM==\"input\", ATTRS{name}==\"retrogame\", ENV{ID_INPUT_KEYBOARD}=\"1\"" > /etc/udev/rules.d/10-retrogame.rules

if ! grep -qF "retrogame&" /etc/rc.local; then
	sed -i '/^\(exit 0\)/ i retrogame&' /etc/rc.local
fi

curl -O https://raw.githubusercontent.com/Agente404/pico8pi/master/config/retrogame.cfg
mv retrogame.cfg /boot/retrogame.cfg
