# KRUU Print Server DNP - Complete Setup Guide

Full rebuild instructions for the DNP QW410 print server on a fresh Raspberry Pi (Debian Trixie, ARM64).

The fast way is `sudo bash install.sh` (see README). This file is the manual version, for when you want to do a step by hand or understand what the installer does.

Two things the installer figures out on its own that are written literally below:
- The username. Steps here say `/home/pi` and `User=pi`. The installer uses whatever user you flashed the card with instead.
- The printer serial. The URI below has a specific serial. The installer reads it off the plugged-in printer with `lpinfo -v`.

This folder contains:
- `app.py` - the web interface (drag and drop printing + reset button)
- `print-watcher.sh` - watches hot folders and prints dropped photos
- `print-watcher.service` / `kruu-print-web.service` - unit templates the installer fills in
- `install.sh` / `uninstall.sh` - automated install and removal
- `SETUP-GUIDE.md` - this file

---

## Printer USB URI

The DNP QW410 URI used throughout is:
`gutenprint53+usb://dnp-qw410/QW4C3A014429`

The serial (`QW4C3A014429`) is specific to your printer. If you swap printers, get the new URI with:
```
lpstat -v | grep -i nippon
```
Then substitute it wherever it appears below and in any lpadmin commands.

---

## STEP 1 - Install CUPS

```
sudo apt update
sudo apt install cups cups-client libusb-1.0-0-dev libcups2-dev -y
sudo service cups restart
sudo apt remove ipp-usb -y
```

## STEP 2 - Configure CUPS

```
sudo usermod -a -G lpadmin pi
sudo nano /etc/cups/cupsd.conf
```

Make these changes:
- Comment out: `# Listen localhost:631`
- Add: `Port 631`
- In each `<Location>` block add: `Allow @local`

Then:
```
sudo /etc/init.d/cups restart
sudo cupsctl WebInterface=yes
```

## STEP 3 - Install Gutenprint from source

```
sudo service cups stop
sudo apt remove gutenprint* -y
sudo rm -f /usr/lib/cups/backend/gutenprint*
sudo rm -f /usr/lib/cups/filter/rastertogutenprint*
sudo rm -f /usr/lib/cups/driver/gutenprint*

cd ~
wget https://www.shaftnet.org/~pizza/gutenprint-5.3.4-20230113102352.tar.xz
tar -xJf gutenprint-5.3.4-*.tar.xz
cd gutenprint-5.3.4-*
./configure --without-doc
make clean && make
sudo make install
cd ~
rm -rf gutenprint-5.3.4-*
```

## STEP 4 - Finish Gutenprint config

```
echo '/usr/local/lib' | sudo tee -a /etc/ld.so.conf.d/usr-local.conf
sudo ldconfig
sudo service cups restart
sudo touch /var/log/cups/page_log
```

## STEP 5 - Generate the PPD

```
sudo /usr/sbin/cups-genppd.5.3 -p /etc/cups/ppd dnp-qw410
sudo gunzip /etc/cups/ppd/stp-dnp-qw410.5.3.ppd.gz
```

## STEP 6 - Create the four print queues

```
sudo lpadmin -p "Dai_Nippon_Printing_DP-QW410_4x4" -v "gutenprint53+usb://dnp-qw410/QW4C3A014429" -E -P /etc/cups/ppd/stp-dnp-qw410.5.3.ppd -D "DNP QW410 - 4x4"
sudo lpadmin -p "Dai_Nippon_Printing_DP-QW410_4x6" -v "gutenprint53+usb://dnp-qw410/QW4C3A014429" -E -P /etc/cups/ppd/stp-dnp-qw410.5.3.ppd -D "DNP QW410 - 4x6"
sudo lpadmin -p "Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes" -v "gutenprint53+usb://dnp-qw410/QW4C3A014429" -E -P /etc/cups/ppd/stp-dnp-qw410.5.3.ppd -D "DNP QW410 - 4x6 2 Stripes"
sudo lpadmin -p "Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes" -v "gutenprint53+usb://dnp-qw410/QW4C3A014429" -E -P /etc/cups/ppd/stp-dnp-qw410.5.3.ppd -D "DNP QW410 - 4x6 3 Stripes"
```

## STEP 7 - Set the correct page size per queue

```
sudo lpadmin -p Dai_Nippon_Printing_DP-QW410_4x4 -o PageSize=w288h288
sudo lpadmin -p Dai_Nippon_Printing_DP-QW410_4x6 -o PageSize=w288h432
sudo lpadmin -p Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes -o PageSize=w288h432-div2
sudo lpadmin -p Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes -o PageSize=w288h432-div3
```

Size reference:
- 4x6 = `w288h432` (full 4x6 photo)
- 4x4 = `w288h288` (square)
- 2 Strips = `w288h432-div2` (4x6 cut in half = two 4x3 strips)
- 3 Strips = `w288h432-div3` (4x6 cut in thirds = three 4x2 strips)

## STEP 8 - Zero out the 4x6 border in every PPD

The generated PPD has a 17.04pt side margin on 4x6 that causes a border. Zero it:

```
for ppd in /etc/cups/ppd/Dai_Nippon_Printing_DP-QW410*.ppd; do
  sudo sed -i 's/\*ImageableArea w288h432\/4x6:\t"17.040 0.000 320.880 440.640"/\*ImageableArea w288h432\/4x6:\t"0.000 0.000 288.000 432.000"/' "$ppd"
done
sudo systemctl restart cups
```

## STEP 9 - Create the hot folders

```
mkdir -p /home/pi/print-hotfolder/4x6
mkdir -p /home/pi/print-hotfolder/4x4
mkdir -p /home/pi/print-hotfolder/4x6_2stripes
mkdir -p /home/pi/print-hotfolder/4x6_3stripes
chmod -R 777 /home/pi/print-hotfolder
```

## STEP 10 - Install the watcher and web app

```
sudo apt install inotify-tools python3-flask samba -y

# Copy app.py and print-watcher.sh into /home/pi/print-hotfolder/
# (transfer them from this folder via scp or a USB stick)

sudo chmod +x /home/pi/print-hotfolder/print-watcher.sh
```

## STEP 11 - Install the two services

```
# Copy print-watcher.service and kruu-print-web.service into /etc/systemd/system/
sudo cp print-watcher.service /etc/systemd/system/
sudo cp kruu-print-web.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable print-watcher kruu-print-web
sudo systemctl start print-watcher kruu-print-web
```

## STEP 12 - Allow the reset button to run without a password

```
echo 'pi ALL=(ALL) NOPASSWD: /usr/sbin/cupsenable, /usr/bin/systemctl restart cups, /usr/bin/cancel' | sudo tee /etc/sudoers.d/kruu-print
```

## STEP 13 - Samba shares (optional, for drag-and-drop from Finder)

```
sudo nano /etc/samba/smb.conf
```

Add at the bottom:
```
[KRUU-Print-4x6]
   path = /home/pi/print-hotfolder/4x6
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x4]
   path = /home/pi/print-hotfolder/4x4
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x6-2Stripes]
   path = /home/pi/print-hotfolder/4x6_2stripes
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x6-3Stripes]
   path = /home/pi/print-hotfolder/4x6_3stripes
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777
```

Then:
```
sudo systemctl restart smbd
sudo systemctl enable smbd
```

## STEP 14 - WiFi power saving off (prevents dropouts)

```
sudo nano /etc/rc.local
```

Paste:
```
#!/bin/sh -e
/sbin/iwconfig wlan0 power off
exit 0
```

Then:
```
sudo chmod +x /etc/rc.local
```

## STEP 15 - Friendly hostname (optional)

```
sudo hostnamectl set-hostname print
sudo nano /etc/hosts
```
Change `127.0.1.1 printserver-dnp` to `127.0.1.1 print`, then:
```
sudo systemctl restart avahi-daemon
```

---

## USING IT

- Web interface: `http://<pi-ip>:8080` (or `http://print.local:8080` if you set the hostname)
- Pick a size, drag photos in, hit Send to Printer
- The Clear Queue & Reset Printer button cancels stuck jobs and restarts CUPS
- Photos are auto-deleted after printing

## TROUBLESHOOTING

Printer not detected:
```
lsusb | grep -i nippon
sudo service cups restart
```

Clear stuck jobs:
```
cancel -a
sudo cupsenable Dai_Nippon_Printing_DP-QW410_4x6
```

Ran out of ribbon mid-job (queue disabled):
```
cancel -a
sudo cupsenable Dai_Nippon_Printing_DP-QW410_4x6 Dai_Nippon_Printing_DP-QW410_4x4 Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes
```
Then power cycle the printer.

Check services:
```
sudo systemctl status print-watcher
sudo systemctl status kruu-print-web
```

Border appears on 4x6 when printing from a Mac's Preview app:
That's macOS wrapping the image in a PDF with margins - not a server problem. Use the web interface or hot folders instead, which bypass it.
