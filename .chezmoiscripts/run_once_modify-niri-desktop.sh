#!/bin/sh

set -eu

read -r -p "Modify niri-desktop? [y/N] " answer
if [[ "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
	echo "Installation cancelled"
	exit 0
fi

FILE="/usr/share/wayland-sessions/niri.desktop"
BACKUP="${FILE}.bak"

sudo sh -c '
set -eu

FILE="/usr/share/wayland-sessions/niri.desktop"
BACKUP="${FILE}.bak"

[ -f "$FILE" ] || {
    echo "Error: $FILE does not exist" >&2
    exit 1
}

# Only modify it if it has not already been modified.
if grep -q "^Exec=sh -lc" "$FILE"; then
    echo "niri.desktop already configured."
    exit 0
fi

cp "$FILE" "$BACKUP"

sed -i "s|^Exec=.*|Exec=/home/fred/.local/bin/niri-session|" "$FILE"

echo "Updated $FILE"
'