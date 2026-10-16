#!/usr/bin/env bash
# WordBlocker for Linux installer. Run from this folder: ./install.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/.local/share/wordblocker"
echo "==> Installing dependencies (needs sudo)"
if command -v apt-get >/dev/null; then sudo apt-get install -y python3-evdev libnotify-bin
elif command -v dnf >/dev/null; then sudo dnf install -y python3-evdev libnotify
elif command -v pacman >/dev/null; then sudo pacman -S --needed --noconfirm python-evdev libnotify
else echo "Install python3-evdev and notify-send with your package manager, then rerun."; fi
echo "==> Allowing your user to read keyboards and send backspaces"
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/99-wordblocker.rules >/dev/null
echo uinput | sudo tee /etc/modules-load.d/wordblocker.conf >/dev/null
sudo modprobe uinput || true
sudo udevadm control --reload-rules && sudo udevadm trigger || true
sudo usermod -aG input "$USER"
echo "==> Copying files"
rm -rf "$PREFIX" && mkdir -p "$PREFIX" "$HOME/.local/bin" "$HOME/.config/systemd/user"
cp -R "$DIR/wordblocker" "$PREFIX/"
cat > "$HOME/.local/bin/wordblocker" <<SH
#!/usr/bin/env bash
PYTHONPATH="$PREFIX" exec python3 -m wordblocker "\$@"
SH
chmod +x "$HOME/.local/bin/wordblocker"
cp "$DIR/wordblocker.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable wordblocker.service
echo
echo "✅ Installed. Log out and back in once (for keyboard access), then it starts automatically."
echo "   Add words:   wordblocker add <word> [--note \"reminder\"]"
echo "   Status:      systemctl --user status wordblocker"
