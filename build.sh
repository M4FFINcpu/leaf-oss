#!/bin/bash
# =============================================================================
#  Leaf OS 5.0 "big distro" ISO builder
#  A full desktop Linux (Debian 12 + KDE Plasma) that you can install on a
#  hard drive: Steam, Wine, Lutris, Firefox, LibreOffice, VLC, GIMP, an app
#  store with Flatpak, and the Leaf OS web desktop as an app and a session.
#
#  Run inside a Debian 12 container (Linux, Windows or macOS with Docker):
#     docker run --rm --privileged -v "$PWD":/build -w /build debian:bookworm bash ./build.sh
#  Result: out/leafos-5.0-amd64.iso
# =============================================================================
set -euo pipefail

# ---- settings you can change ------------------------------------------------
KEYBOARD="${KEYBOARD:-gb}"                 # keyboard layout: gb, us, es, fr, de, it, pt, latam...
TIMEZONE="${TIMEZONE:-Europe/Madrid}"      # time zone
LOCALE="${LOCALE:-en_GB.UTF-8}"            # system language
VERSION="5.0"
# -----------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

# Finds a Leaf OS file whether it was uploaded into leafos/ or next to build.sh
pick() {
    for f in "$ROOT/$1" "$ROOT/leafos/$1" "$ROOT/leafos/helper/$1" "$ROOT/helper/$1"; do
        if [ -e "$f" ]; then echo "$f"; return 0; fi
    done
    echo "Missing file: $1 (put it in the leafos folder)" >&2
    return 1
}
for f in index.html server.py iso-extra.js manifest.json background.js content.js leafos-run wallpaper.png leafos.png; do
    pick "$f" >/dev/null
done

echo "==> Installing live-build"
apt-get update
apt-get install -y --no-install-recommends live-build debootstrap ca-certificates cpio xz-utils

rm -rf "$ROOT/work" "$ROOT/out"
mkdir -p "$ROOT/work" "$ROOT/out"
cd "$ROOT/work"

echo "==> Configuring the live system"
lb config \
  --mode debian \
  --distribution bookworm \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-images iso-hybrid \
  --debian-installer none \
  --memtest none \
  --apt-recommends true \
  --firmware-binary false \
  --firmware-chroot false \
  --chroot-squashfs-compression-type xz \
  --iso-application "Leaf OS ${VERSION}" \
  --iso-publisher "Leaf OS" \
  --iso-volume "LEAFOS_${VERSION/./_}" \
  --bootappend-live "boot=live components quiet splash hostname=leafos username=leaf user-fullname=Leaf locales=${LOCALE} keyboard-layouts=${KEYBOARD} timezone=${TIMEZONE}"

# ---- packages -----------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/leafos.list.chroot <<'EOF'
live-boot
live-config
live-config-systemd
systemd-sysv
sudo
user-setup
locales
keyboard-configuration
console-setup
tzdata
systemd-timesyncd
zram-tools

kde-plasma-desktop
sddm
plasma-nm
plasma-pa
plasma-discover
plasma-discover-backend-flatpak
flatpak
xserver-xorg
xserver-xorg-video-vmware
mesa-utils
mesa-vulkan-drivers
vulkan-tools
pipewire-audio
dolphin
konsole
kate
ark
okular
gwenview
kcalc
partitionmanager
fonts-noto-core
fonts-noto-color-emoji
fonts-liberation2

firefox-esr
chromium
libreoffice-writer
libreoffice-calc
libreoffice-impress
vlc
gimp

p7zip-full
unzip
zip
unar
xz-utils
zstd
file
libfuse2
libnotify-bin
gdebi
build-essential
cmake
git
python3
python3-pip
curl
wget
htop
neofetch

network-manager
isc-dhcp-client
iproute2
iputils-ping
ca-certificates

calamares
calamares-settings-debian
grub-pc-bin
grub-efi-amd64-bin
efibootmgr
os-prober
dosfstools

openbox

firmware-misc-nonfree
firmware-realtek
firmware-iwlwifi
firmware-amd-graphics
EOF

# ---- hooks that run inside the new system while it is built ---------------------------
mkdir -p config/hooks/normal

# 32-bit support, Steam, Wine (Windows programs) and Lutris (game launcher)
cat > config/hooks/normal/0050-leafos-games.hook.chroot <<'EOF'
#!/bin/sh
set -e
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update
# Accept Steam's license automatically (the user still sees Steam's own terms when it first starts)
for owner in steam steam-installer; do
    echo "$owner steam/question select I AGREE" | debconf-set-selections
    echo "$owner steam/license note " | debconf-set-selections
    echo "$owner steam/purge note " | debconf-set-selections
done
apt-get install -y steam-installer steam-devices \
    libgl1-mesa-dri:i386 libglx-mesa0:i386 libgl1:i386 mesa-vulkan-drivers:i386 libvulkan1:i386
apt-get install -y wine wine64 wine32:i386 fonts-wine
apt-get install -y wine-binfmt || true
apt-get install -y lutris || true
apt-get clean
EOF

# Services, branding and defaults
cat > config/hooks/normal/0100-leafos-setup.hook.chroot <<'EOF'
#!/bin/sh
systemctl enable NetworkManager.service || true
systemctl enable sddm.service || true
systemctl enable zramswap.service || true
systemctl enable systemd-timesyncd.service || true
# Flathub app store (thousands of apps in Discover)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
# Installer says "Leaf OS" instead of "Debian"
for f in /etc/calamares/branding/*/branding.desc; do
    [ -f "$f" ] || continue
    sed -i -e 's/^\(\s*productName:\).*/\1 Leaf OS/' -e 's/^\(\s*shortProductName:\).*/\1 Leaf OS/' \
           -e 's/^\(\s*versionedName:\).*/\1 Leaf OS 5.0/' -e 's/^\(\s*shortVersionedName:\).*/\1 Leaf OS 5.0/' \
           -e 's/^\(\s*bootloaderEntryName:\).*/\1 LeafOS/' "$f" || true
done
# Desktop shortcuts for new users (installer, Steam, Leaf OS, files)
mkdir -p /etc/skel/Desktop
for app in install-debian calamares steam leafos org.kde.dolphin firefox-esr; do
    if [ -f "/usr/share/applications/$app.desktop" ]; then
        cp "/usr/share/applications/$app.desktop" /etc/skel/Desktop/
        chmod +x "/etc/skel/Desktop/$app.desktop"
    fi
done
# Don't show the installer icon twice
[ -f /etc/skel/Desktop/install-debian.desktop ] && rm -f /etc/skel/Desktop/calamares.desktop
sed -i 's/^Name=.*/Name=Install Leaf OS/' /etc/skel/Desktop/install-debian.desktop 2>/dev/null || true
sed -i 's/^Name=.*/Name=Install Leaf OS/' /etc/skel/Desktop/calamares.desktop 2>/dev/null || true
update-desktop-database /usr/share/applications 2>/dev/null || true
exit 0
EOF
chmod 755 config/hooks/normal/*.hook.chroot

# ---- files copied into the new system ---------------------------------------------
INC=config/includes.chroot
mkdir -p "$INC/opt/leafos/helper" "$INC/usr/local/bin" "$INC/usr/share/applications" "$INC/usr/share/xsessions" \
         "$INC/usr/share/wallpapers" "$INC/usr/share/icons/hicolor/256x256/apps" "$INC/usr/share/kio/servicemenus" \
         "$INC/etc/xdg/autostart" "$INC/etc/chromium/policies/managed" "$INC/etc/default" "$INC/etc/skel/Apps" \
         "$INC/usr/lib/live/config" "$INC/etc/NetworkManager/conf.d"

# Leaf OS web desktop (as an app and as a login session)
cp "$(pick index.html)"   "$INC/opt/leafos/index.html"
cp "$(pick server.py)"    "$INC/opt/leafos/server.py"
cp "$(pick iso-extra.js)" "$INC/opt/leafos/iso-extra.js"
for f in manifest.json background.js content.js; do cp "$(pick "$f")" "$INC/opt/leafos/helper/$f"; done
chmod 755 "$INC/opt/leafos/server.py"
sed -i 's#^[[:space:]]*</body>[[:space:]]*$#<script src="iso-extra.js"></script>\n</body>#' "$INC/opt/leafos/index.html"
cp "$(pick wallpaper.png)" "$INC/usr/share/wallpapers/LeafOS.png"
cp "$(pick leafos.png)"    "$INC/usr/share/icons/hicolor/256x256/apps/leafos.png"
cp "$(pick leafos-run)"    "$INC/usr/local/bin/leafos-run"
chmod 755 "$INC/usr/local/bin/leafos-run"

cat > "$INC/usr/local/bin/leafos-app" <<'EOF'
#!/bin/sh
# Leaf OS web desktop in its own window
if ! curl -s -o /dev/null --max-time 1 http://127.0.0.1:8080/index.html; then
    python3 /opt/leafos/server.py >> "$HOME/.leafos-server.log" 2>&1 &
    sleep 1
fi
exec chromium --app=http://127.0.0.1:8080/index.html --user-data-dir="$HOME/.leafos-browser" \
    --start-maximized --no-first-run --password-store=basic \
    --load-extension=/opt/leafos/helper --disable-features=DisableLoadExtensionCommandLineSwitch "$@"
EOF
cat > "$INC/usr/local/bin/leafos-session" <<'EOF'
#!/bin/sh
# "Leaf OS (classic)" login session: the web desktop full screen
xset s off -dpms s noblank 2>/dev/null
mkdir -p "$HOME/Downloads"
openbox &
python3 /opt/leafos/server.py >> "$HOME/.leafos-server.log" 2>&1 &
sleep 1
while true; do
    chromium --kiosk --app=http://127.0.0.1:8080/index.html --user-data-dir="$HOME/.leafos-browser" \
        --no-first-run --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
        --password-store=basic --autoplay-policy=no-user-gesture-required \
        --load-extension=/opt/leafos/helper --disable-features=Translate,DisableLoadExtensionCommandLineSwitch \
        >> "$HOME/.leafos-chromium.log" 2>&1 || date +%s >> "$HOME/.leafos-crashes"
    [ -f "$HOME/.leafos-logout" ] && { rm -f "$HOME/.leafos-logout"; break; }
    sleep 1
done
EOF
chmod 755 "$INC/usr/local/bin/leafos-app" "$INC/usr/local/bin/leafos-session"

cat > "$INC/usr/share/applications/leafos.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Leaf OS
Comment=The Leaf OS web desktop
Exec=leafos-app
Icon=leafos
Categories=System;
EOF
cat > "$INC/usr/share/xsessions/leafos.desktop" <<'EOF'
[Desktop Entry]
Type=XSession
Name=Leaf OS (classic)
Comment=The Leaf OS web desktop, full screen
Exec=/usr/local/bin/leafos-session
EOF

# Leaf OS Runner: double-click AppImages and scripts, right-click "Run with Leaf OS" on archives
cat > "$INC/usr/share/applications/leafos-run.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Leaf OS Runner
Comment=Run or install a downloaded program (AppImage, .deb, .tar.gz, .zip, .exe, .sh)
Exec=leafos-run %f
Icon=system-run
NoDisplay=true
MimeType=application/vnd.appimage;application/x-iso9660-appimage;application/x-shellscript;application/x-executable;application/x-compressed-tar;application/x-xz-compressed-tar;application/x-bzip-compressed-tar;application/x-zstd-compressed-tar;application/x-tar;application/vnd.debian.binary-package;
EOF
cat > "$INC/usr/share/kio/servicemenus/leafos-run.desktop" <<'EOF'
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=application/vnd.appimage;application/x-iso9660-appimage;application/x-shellscript;application/x-executable;application/x-compressed-tar;application/x-xz-compressed-tar;application/x-bzip-compressed-tar;application/x-zstd-compressed-tar;application/x-tar;application/zip;application/x-7z-compressed;application/vnd.rar;application/vnd.debian.binary-package;application/x-ms-dos-executable;application/x-msi;
Actions=leafosRun
X-KDE-Priority=TopLevel

[Desktop Action leafosRun]
Name=Run with Leaf OS
Icon=system-run
Exec=leafos-run %f
EOF
cat > "$INC/etc/xdg/mimeapps.list" <<'EOF'
[Default Applications]
application/vnd.appimage=leafos-run.desktop
application/x-iso9660-appimage=leafos-run.desktop
application/x-shellscript=leafos-run.desktop
application/vnd.debian.binary-package=gdebi.desktop
EOF

# First login: Leaf OS wallpaper and dark theme
cat > "$INC/usr/local/bin/leafos-firstrun" <<'EOF'
#!/bin/sh
MARK="$HOME/.config/leafos-firstrun-done"
[ -f "$MARK" ] && exit 0
sleep 4
plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
plasma-apply-wallpaperimage /usr/share/wallpapers/LeafOS.png >/dev/null 2>&1 || true
chmod +x "$HOME"/Desktop/*.desktop 2>/dev/null || true
mkdir -p "$HOME/.config" "$HOME/Apps" && touch "$MARK"
EOF
chmod 755 "$INC/usr/local/bin/leafos-firstrun"
cat > "$INC/etc/xdg/autostart/leafos-firstrun.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Leaf OS first start
Exec=/usr/local/bin/leafos-firstrun
OnlyShowIn=KDE;
NoDisplay=true
EOF

# Live session only: log straight in (the installed system asks for your own password)
cat > "$INC/usr/lib/live/config/2000-leafos-autologin" <<'EOF'
#!/bin/sh
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/leafos-live.conf <<CONF
[Autologin]
User=leaf
Session=plasma
CONF
EOF
chmod 755 "$INC/usr/lib/live/config/2000-leafos-autologin"

# Name shown by the system
cat > "$INC/etc/issue" <<'EOF'
Leaf OS 5.0 (based on Debian 12) \n \l

EOF

# Compressed memory
cat > "$INC/etc/default/zramswap" <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

# NetworkManager looks after every network card
cat > "$INC/etc/NetworkManager/conf.d/10-leafos.conf" <<'EOF'
[main]
plugins=keyfile
dns=default

[ifupdown]
managed=true

[keyfile]
unmanaged-devices=none
EOF

# Chromium: downloads go straight to Downloads, no blocking warnings for programs and archives
cat > "$INC/etc/chromium/policies/managed/leafos.json" <<'EOF'
{
  "PromptForDownloadLocation": false,
  "DownloadRestrictions": 0,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "CommandLineFlagSecurityWarningsEnabled": false,
  "ExemptDomainFileTypePairsFromFileTypeDownloadWarnings": [
    { "file_extension": "exe", "domains": ["*"] },
    { "file_extension": "msi", "domains": ["*"] },
    { "file_extension": "zip", "domains": ["*"] },
    { "file_extension": "7z", "domains": ["*"] },
    { "file_extension": "rar", "domains": ["*"] },
    { "file_extension": "deb", "domains": ["*"] },
    { "file_extension": "appimage", "domains": ["*"] },
    { "file_extension": "sh", "domains": ["*"] },
    { "file_extension": "jar", "domains": ["*"] },
    { "file_extension": "iso", "domains": ["*"] }
  ]
}
EOF

# ---- boot menu --------------------------------------------------------------------
if [ -d /usr/share/live/build/bootloaders/isolinux ]; then
    mkdir -p config/bootloaders
    cp -r /usr/share/live/build/bootloaders/isolinux config/bootloaders/
    grep -rl "Live system" config/bootloaders 2>/dev/null | xargs -r sed -i "s/Live system/Leaf OS ${VERSION}/g" || true
    grep -rl "^timeout" config/bootloaders 2>/dev/null | xargs -r sed -i 's/^timeout .*/timeout 50/' || true
fi

echo "==> Building the ISO (this takes 40-90 minutes)"
lb build

ISO=$(ls -1 ./*.iso | head -n1)
mv "$ISO" "$ROOT/out/leafos-${VERSION}-amd64.iso"
ls -lh "$ROOT/out/"
echo "==> Done: out/leafos-${VERSION}-amd64.iso"
