#!/usr/bin/env bash
systemctl --user disable --now wordblocker.service 2>/dev/null || true
rm -rf "$HOME/.local/share/wordblocker" "$HOME/.local/bin/wordblocker" "$HOME/.config/systemd/user/wordblocker.service"
sudo rm -f /etc/udev/rules.d/99-wordblocker.rules /etc/modules-load.d/wordblocker.conf
echo "Removed. Your word list is kept in ~/.config/wordblocker (delete it to wipe)."
