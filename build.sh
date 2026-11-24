#!/bin/bash
# =============================================================================
#  Leaf OS 4.5 ISO builder
#  Builds a bootable live ISO (Debian 12 + Chromium kiosk) that starts straight
#  into the Leaf OS desktop with working internet.
#
#  Run inside a Debian 12 container (works on Linux, Windows and macOS):
#     docker run --rm --privileged -v "$PWD":/build -w /build debian:bookworm bash ./build.sh
#  Result: out/leafos-4.5-amd64.iso
# =============================================================================
set -euo pipefail

# ---- settings you can change ------------------------------------------------
KEYBOARD="${KEYBOARD:-gb}"                 # keyboard layout: gb, us, es, fr, de, it, pt, latam...
TIMEZONE="${TIMEZONE:-Europe/Madrid}"      # time zone
LOCALE="${LOCALE:-en_US.UTF-8}"            # system language
SCREEN="${SCREEN:-1280x800}"               # preferred screen size inside the VM
VERSION="4.5"
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
for f in index.html server.py iso-extra.js manifest.json background.js content.js; do
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
  --archive-areas "main" \
  --binary-images iso-hybrid \
  --debian-installer none \
  --memtest none \
  --apt-recommends false \
  --firmware-binary false \
  --firmware-chroot false \
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
libpam-systemd
user-setup
sudo
dbus
dbus-x11
xserver-xorg-core
xserver-xorg-legacy
xserver-xorg-input-libinput
xserver-xorg-video-vmware
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xinit
x11-xserver-utils
xkb-data
openbox
chromium
fonts-dejavu-core
fonts-liberation2
fonts-noto-color-emoji
python3
network-manager
udev
kmod
iproute2
isc-dhcp-client
iputils-ping
curl
systemd-timesyncd
ca-certificates
pulseaudio
alsa-utils
locales
keyboard-configuration
console-setup
tzdata
librsvg2-common
adwaita-icon-theme
hicolor-icon-theme
shared-mime-info
gsettings-desktop-schemas
dconf-gsettings-backend
xdg-utils
xdg-user-dirs
zram-tools
procps
EOF
# librsvg2-common ... xdg-user-dirs: without these, Chromium's "Save as" and file windows crash the
#   whole browser (their icons can't be drawn). That was the "system crashes when downloading" bug.
# zram-tools: compressed memory, so big downloads don't run the live system out of RAM.

# ---- Leaf OS files ----------------------------------------------------------------
INC=config/includes.chroot
mkdir -p "$INC/opt/leafos/helper" "$INC/etc/skel/Downloads" "$INC/etc/skel/.config" \
         "$INC/etc/chromium/policies/managed" "$INC/etc/default"
cp "$(pick index.html)"   "$INC/opt/leafos/index.html"
cp "$(pick server.py)"    "$INC/opt/leafos/server.py"
cp "$(pick iso-extra.js)" "$INC/opt/leafos/iso-extra.js"
for f in manifest.json background.js content.js; do
    cp "$(pick "$f")" "$INC/opt/leafos/helper/$f"
done
chmod 755 "$INC/opt/leafos/server.py"
# (only the page's real closing tag, which is alone on its line; Leaf OS has "</body>" inside some texts too)
sed -i 's#^[[:space:]]*</body>[[:space:]]*$#<script src="iso-extra.js"></script>\n</body>#' "$INC/opt/leafos/index.html"
grep -q 'src="iso-extra.js"' "$INC/opt/leafos/index.html" || { echo "Could not add iso-extra.js to index.html" >&2; exit 1; }
touch "$INC/etc/skel/Downloads/.keep"
cat > "$INC/etc/skel/.config/user-dirs.dirs" <<'EOF'
XDG_DOWNLOAD_DIR="$HOME/Downloads"
EOF

# Compressed swap in memory
cat > "$INC/etc/default/zramswap" <<'EOF'
ALGO=zstd
PERCENT=60
PRIORITY=100
EOF

# ---- Networking: make sure the VM always gets online ----------------------------------
mkdir -p "$INC/etc/NetworkManager/conf.d" "$INC/etc/NetworkManager/system-connections" \
         "$INC/usr/local/sbin" "$INC/etc/systemd/system" config/hooks/normal

# NetworkManager manages every network card (ignore /etc/network/interfaces)
cat > "$INC/etc/NetworkManager/conf.d/10-leafos.conf" <<'EOF'
[main]
plugins=keyfile
dns=default

[ifupdown]
managed=true

[keyfile]
unmanaged-devices=none
EOF

# A wired connection that works on any network card (VirtualBox NAT, bridged, real PCs)
cat > "$INC/etc/NetworkManager/system-connections/Wired.nmconnection" <<'EOF'
[connection]
id=Wired
type=ethernet
autoconnect=true
autoconnect-priority=10

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "$INC/etc/NetworkManager/system-connections/Wired.nmconnection"

# Fallback: if there's still no connection after boot, use DHCP directly and fix DNS
cat > "$INC/usr/local/sbin/leafos-netfix" <<'EOF'
#!/bin/sh
# Leaf OS network fallback
[ "$1" = "now" ] || sleep 12
for attempt in 1 2 3; do
    if ip -4 route show default | grep -q default; then break; fi
    for dev in $(ls /sys/class/net); do
        [ "$dev" = "lo" ] && continue
        ip link set "$dev" up 2>/dev/null
        if ! ip -4 addr show dev "$dev" | grep -q "inet "; then
            timeout 25 dhclient -1 "$dev" >/dev/null 2>&1 || true
        fi
    done
    sleep 5
done
if ! grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
    rm -f /etc/resolv.conf
    printf 'nameserver 10.0.2.3\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
fi
exit 0
EOF
chmod 755 "$INC/usr/local/sbin/leafos-netfix"

cat > "$INC/etc/systemd/system/leafos-netfix.service" <<'EOF'
[Unit]
Description=Leaf OS network fallback
After=NetworkManager.service network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/leafos-netfix

[Install]
WantedBy=multi-user.target
EOF

cat > config/hooks/normal/0100-leafos-services.hook.chroot <<'EOF'
#!/bin/sh
systemctl enable NetworkManager.service || true
systemctl enable leafos-netfix.service || true
systemctl enable systemd-timesyncd.service || true
systemctl enable zramswap.service || true
EOF
chmod 755 config/hooks/normal/0100-leafos-services.hook.chroot

# Log in automatically on the first console and start the graphical session
cat > "$INC/etc/skel/.bash_profile" <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx -- -nolisten tcp > "$HOME/.leafos-x.log" 2>&1
fi
EOF

# The graphical session: Leaf OS full screen, restarted automatically if it ever stops.
# Chromium's messages go to ~/.leafos-chromium.log, and crashes are noted for the "crashlog" command.
cat > "$INC/etc/skel/.xinitrc" <<EOF
#!/bin/sh
xset s off -dpms s noblank 2>/dev/null
OUT=\$(xrandr 2>/dev/null | awk '/ connected/{print \$1; exit}')
[ -n "\$OUT" ] && xrandr --output "\$OUT" --mode ${SCREEN} 2>/dev/null
mkdir -p "\$HOME/Downloads"
openbox &
python3 /opt/leafos/server.py >> "\$HOME/.leafos-server.log" 2>&1 &
sleep 1
LOG="\$HOME/.leafos-chromium.log"
while true; do
    [ -f "\$LOG" ] && [ "\$(stat -c %s "\$LOG")" -gt 2000000 ] && mv -f "\$LOG" "\$LOG.old"
    echo "=== Leaf OS started \$(date '+%F %T') ===" >> "\$LOG"
    chromium --kiosk --app=http://127.0.0.1:8080/index.html \\
        --user-data-dir="\$HOME/.leafos-browser" \\
        --no-first-run --noerrdialogs --disable-infobars \\
        --disable-session-crashed-bubble --disable-translate \\
        --password-store=basic --autoplay-policy=no-user-gesture-required \\
        --check-for-update-interval=31536000 --overscroll-history-navigation=0 \\
        --disable-pinch --disable-gpu --disk-cache-size=33554432 \\
        --load-extension=/opt/leafos/helper \\
        --disable-features=Translate,MediaRouter,DisableLoadExtensionCommandLineSwitch \\
        >> "\$LOG" 2>&1
    CODE=\$?
    echo "=== Leaf OS stopped (code \$CODE) \$(date '+%F %T') ===" >> "\$LOG"
    [ "\$CODE" -ne 0 ] && date +%s >> "\$HOME/.leafos-crashes"
    sleep 1
done
EOF
chmod 755 "$INC/etc/skel/.xinitrc"

# Browser rules: downloads go straight to ~/Downloads (no "Save as" window), no blocking
# warnings for programs and archives, and quiet, private defaults.
cat > "$INC/etc/chromium/policies/managed/leafos.json" <<'EOF'
{
  "BrowserSignin": 0,
  "SyncDisabled": true,
  "PasswordManagerEnabled": false,
  "TranslateEnabled": false,
  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "BackgroundModeEnabled": false,
  "CommandLineFlagSecurityWarningsEnabled": false,
  "DownloadDirectory": "/home/leaf/Downloads",
  "PromptForDownloadLocation": false,
  "DownloadRestrictions": 0,
  "ExemptDomainFileTypePairsFromFileTypeDownloadWarnings": [
    { "file_extension": "exe", "domains": ["*"] },
    { "file_extension": "msi", "domains": ["*"] },
    { "file_extension": "zip", "domains": ["*"] },
    { "file_extension": "7z", "domains": ["*"] },
    { "file_extension": "rar", "domains": ["*"] },
    { "file_extension": "jar", "domains": ["*"] },
    { "file_extension": "apk", "domains": ["*"] },
    { "file_extension": "bat", "domains": ["*"] },
    { "file_extension": "com", "domains": ["*"] },
    { "file_extension": "dmg", "domains": ["*"] },
    { "file_extension": "deb", "domains": ["*"] },
    { "file_extension": "iso", "domains": ["*"] },
    { "file_extension": "jsdos", "domains": ["*"] }
  ]
}
EOF

# ---- boot menu: Leaf OS branding and a 5 second auto-start ----------------------------
if [ -d /usr/share/live/build/bootloaders/isolinux ]; then
    mkdir -p config/bootloaders
    cp -r /usr/share/live/build/bootloaders/isolinux config/bootloaders/
    grep -rl "Live system" config/bootloaders 2>/dev/null | xargs -r sed -i "s/Live system/Leaf OS ${VERSION}/g" || true
    grep -rl "^timeout" config/bootloaders 2>/dev/null | xargs -r sed -i 's/^timeout .*/timeout 50/' || true
fi

echo "==> Building the ISO (this takes 15-30 minutes)"
lb build

ISO=$(ls -1 ./*.iso | head -n1)
mv "$ISO" "$ROOT/out/leafos-${VERSION}-amd64.iso"
# Same file under the old name too, so an older copy of the GitHub workflow still finds it
ln -f "$ROOT/out/leafos-${VERSION}-amd64.iso" "$ROOT/out/leafos-3.0-amd64.iso"
ls -lh "$ROOT/out/"
echo "==> Done: out/leafos-${VERSION}-amd64.iso"
