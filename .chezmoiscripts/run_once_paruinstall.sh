#!/bin/bash
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    BLUE=$'\033[34m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
else
    RESET=''
    BOLD=''
    BLUE=''
    GREEN=''
    YELLOW=''
    RED=''
fi


info() { printf '%s\n' "${BLUE}ℹ${RESET}  $*"; }
success() { printf '%s\n' "${GREEN}✓${RESET}  $*"; }
warn() { printf '%s\n' "${YELLOW}⚠${RESET}  $*" >&2; }
fail() { printf '%s\n' "${RED}✗${RESET}  $*" >&2; }



if command -v paru >/dev/null 2>&1; then
    info "paru is installed"
	exit 0
fi
info "Install paru?"
read -r -p "[y/N] " answer
if [[ "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
	warn "Paru installation cancelled"
	exit 0
fi

info "Installing Paru"
cd /tmp
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si