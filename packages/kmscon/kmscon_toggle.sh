#!/bin/sh
CONF=/etc/kmscon/kmscon.conf

if [ "$(id -u)" -ne 0 ]; then
  echo "Need root. Run with: su -c $0" >&2
  exit 1
fi

[ -f "$CONF" ] || {
  echo "Config not found: $CONF" >&2
  exit 1
}

# Remove any previous instances (avoid duplicates)
sed -i '/^xkb-layout=/d; /^xkb-options=/d; /^#xkb-layout=/d; /^#xkb-options=/d' "$CONF"

# Insert fresh lines after "### Input Options ###"
sed -i '/^### Input Options ###$/a\
xkb-options=grp:win_space_toggle\
xkb-layout=us,ru' "$CONF"

echo "Done. Restart kmscon or reboot to apply."
echo "Toggle layout with Win+Space."
