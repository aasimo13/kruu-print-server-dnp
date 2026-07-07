# KRUU Print Server (DNP QW410)

Photo print station for the DNP QW410 running on a Raspberry Pi. Drag photos into a web page or a Samba folder, they print. Handles 4x6, 4x4, and 4x6 cut into 2 or 3 strips.

## Install on a fresh Pi

Flash the SD card (Raspberry Pi OS, 64-bit), boot it, plug in and power on the QW410, then:

```
git clone https://github.com/aasimo13/kruu-print-server-dnp.git
```

```
cd kruu-print-server-dnp && sudo bash install.sh
```

The installer detects the Pi's username and the plugged-in printer on its own, so it works no matter what you named the user or which QW410 you're using. Building Gutenprint from source takes a while on a Pi, that part is normal.

When it finishes it prints the web address. Open `http://<pi-ip>:8080`.

## Using it

- Web interface at `http://<pi-ip>:8080`. Pick a size, drop photos, hit Send to Printer.
- Or drop photos into the Samba folders (`KRUU-Print-4x6`, etc.) from Finder.
- Clear Queue & Reset Printer cancels stuck jobs and restarts CUPS.
- Photos delete themselves once they hit the print queue.

## Checking it

```
systemctl status kruu-print-web --no-pager
```

```
systemctl status print-watcher --no-pager
```

## If prints stop

Ran out of ribbon mid-job, so a queue got disabled. Hit the reset button in the web UI, or:

```
cancel -a && sudo cupsenable Dai_Nippon_Printing_DP-QW410_4x6 Dai_Nippon_Printing_DP-QW410_4x4 Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes
```

Then power cycle the printer.

Printer not detected:

```
lsusb | grep -i nippon && sudo service cups restart
```

Swapped in a different QW410 and nothing prints (jobs pile up, no error): the queues were pointed at the old printer's serial. This now fixes itself on boot and whenever you plug the printer in. To force it:

```
sudo bash ~/print-hotfolder/sync-printer.sh
```

## Reinstall / update

Pull the latest and re-run the installer. It's safe to run again, it skips the Gutenprint build if it's already there.

```
cd kruu-print-server-dnp && git pull && sudo bash install.sh
```

## What's in here

- `app.py` - the web interface
- `print-watcher.sh` - watches the hot folders and sends photos to the printer
- `sync-printer.sh` - re-points the queues at the connected QW410 (runs on boot and USB plug-in)
- `install.sh` - sets up everything on a fresh Pi
- `uninstall.sh` - removes the services and queues
- `SETUP-GUIDE.md` - the manual step-by-step, if you ever need to do it by hand

KRUU US INC
