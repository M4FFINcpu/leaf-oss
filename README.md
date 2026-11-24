# Leaf OS 5.0

A full desktop Linux you can install on a drive: **Debian 12 + KDE Plasma**, with gaming built in.
This repository builds the ISO automatically on GitHub.

## What's inside

* **Desktop:** KDE Plasma with a Windows-style taskbar and Start menu, Leaf OS wallpaper and dark theme.
* **Games:** Steam (with 32-bit support for older games), Lutris, Vulkan and OpenGL drivers.
* **Windows programs:** Wine. Double-click an `.exe` to run it.
* **Apps:** Firefox, Chromium, LibreOffice (Writer, Calc, Impress), VLC, GIMP, Dolphin files, Konsole terminal,
  Kate, Okular, Gwenview, Ark archives, Partition Manager.
* **App store:** Discover with Flathub (thousands of apps, Bambu Studio included).
* **Run Linux files:** right-click a download → **Run with Leaf OS**. It handles `.tar.gz`, `.tar.xz`, `.zip`,
  `.7z`, `.AppImage`, `.deb`, `.flatpak`, `.sh`, `.run` and `.exe`. Archives are unpacked into the **Apps**
  folder and the program inside is started; source code opens a terminal with the build commands
  (compilers are included).
* **Leaf OS web desktop:** as an app (**Leaf OS** in the Start menu) or as a full login session
  (**Leaf OS (classic)**, chosen on the login screen).
* **Installer:** **Install Leaf OS** on the desktop puts it on a hard drive, so games and files stay.

## Get the ISO

Every change pushed to `main` builds it (about 60–90 minutes). Then open **Releases** on the right of the
repository page. GitHub allows 2 GB per file, so a big ISO comes in parts (`.part0`, `.part1`, ...):
download all parts and `join-iso-windows.bat`, put them in one folder, and double-click the `.bat`.
It creates `leafos-5.0-amd64.iso`.

## Install it in VirtualBox

1. **New** → Name `Leaf OS`, ISO image `leafos-5.0-amd64.iso`, Type **Linux**, Version **Debian (64-bit)**,
   tick **Skip Unattended Installation**.
2. Memory **8192 MB** (at least 4096), Processors **4** (at least 2).
3. Hard disk: **Create a virtual hard disk**, **80 GB** or more (Steam games are big).
4. Settings → Display: **VMSVGA**, Video Memory **128 MB**, tick **Enable 3D Acceleration** (needed for games).
5. Settings → Network: **NAT**. Audio: on.
6. Start it. Leaf OS starts as a live system (the live user's password is `live`).
7. Double-click **Install Leaf OS**, follow the steps (erase disk is fine: it's the empty virtual disk),
   then restart and remove the ISO (Devices → Optical Drives → Remove disk).

## Play a Steam game

Open **Steam**, let it update itself, sign in, install a game and press Play. In VirtualBox the graphics
are slow, so pick light games and low settings. On a real PC (installed from a USB stick made with
balenaEtcher or Rufus) games run at normal speed.

## Settings for the build

At the top of `build.sh`: `KEYBOARD="gb"`, `TIMEZONE="Europe/Madrid"`, `LOCALE="en_GB.UTF-8"`.
To build on your own computer with Docker:

```
docker run --rm --privileged -v "$PWD":/build -w /build debian:bookworm bash ./build.sh
```
