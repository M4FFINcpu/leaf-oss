# Leaf OS 4.5 ISO

This repository builds `leafos-4.5-amd64.iso`, a bootable image for VirtualBox, USB sticks and real PCs.
It runs a small Debian 12 Linux underneath. Leaf OS opens full screen in a built-in Chromium browser,
so the internet features work: Chromium with real websites, YouTube, Weather, Chat, Mail sync and more.

## What's new in 4.5

* **Leaf OS 4.5 desktop:** Windows 10 style taskbar, Start menu with power options, Task View,
  window snapping, lock screen, Alarms & Clock, Sticky Notes, Weather, EXE Runner (DOS programs).
* **Chromium with tabs and real websites:** the Leaf OS Web Helper is built in, so sites that
  "refuse to connect" load inside Leaf OS. Logins that still fail open in a normal Chromium window.
* **Downloads app:** files you download appear in **Downloads** (on the desktop and in Start).
  Open pictures, videos, PDFs and web pages, run DOS programs and games, or delete files.
* **Download crash fixed:** Chromium no longer crashes when a download or "Save as" window opens.
* **More memory:** compressed memory (zram) so big downloads don't run the system out of RAM.
* **Crash log:** if Leaf OS ever restarts by itself, type `crashlog` in Command Prompt.

## Build it on GitHub (free)

Every change pushed to `main` builds a new ISO automatically. You can also open **Actions →
Build Leaf OS ISO → Run workflow**. After about 20–30 minutes, open **Releases** (right side of
the repository page) and download `leafos-4.5-amd64.iso`.

To build on your own computer instead, install Docker and run in this folder:

```
docker run --rm --privileged -v "$PWD":/build -w /build debian:bookworm bash ./build.sh
```

## Files

* `build.sh`: builds the ISO (Debian 12 live system + Chromium kiosk).
* `leafos/index.html`: the Leaf OS desktop.
* `leafos/iso-extra.js`: extras for the ISO (real shut down, Downloads app, Terminal commands).
* `leafos/server.py`: small local server the desktop talks to.
* `leafos/helper/`: the Leaf OS Web Helper browser extension (lets websites load inside Leaf OS).

## Set up VirtualBox

1. **New** → Name: `Leaf OS` → ISO Image: choose `leafos-4.5-amd64.iso`
   → Type: **Linux**, Version: **Debian (64-bit)**. Tick **Skip Unattended Installation**.
2. Memory: **4096 MB** (at least 2048 MB). Leaf OS runs from memory, and downloads are kept in memory too.
3. Processors: **2**. Hard disk: **Do Not Add a Virtual Hard Disk**.
4. Settings → Display: Graphics Controller **VMSVGA**, Video Memory **64 MB** or more.
5. Settings → Network: leave **NAT** on. Settings → Audio: on.
6. **Start**. Leaf OS appears about 20–40 seconds later.

## Good to know

* **Saving:** this is a live system, so files, settings and downloads reset when the VM restarts.
* **Command Prompt commands:** `netstatus`, `netfix`, `free`, `crashlog`, `downloads`, `chromium <site>`, `shutdown`, `reboot`.
* **Keyboard and time zone:** set at the top of `build.sh` (`KEYBOARD="gb"`, `TIMEZONE="Europe/Madrid"`).
* **Screen size:** 1280×800 by default (`SCREEN` in `build.sh`). In VirtualBox you can also pick
  View → Virtual Screen 1 → a bigger size.
