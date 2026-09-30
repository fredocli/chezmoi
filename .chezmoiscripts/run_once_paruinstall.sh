#!/bin/bash
set -euo pipefail

if command -v paru >/dev/null 2>&1; then
    echo "paru is installed"
	exit 0
fi

cd /tmp
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si