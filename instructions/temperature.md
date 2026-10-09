for dev in /dev/sd[a-z]; do
  [ -b "$dev" ] || continue
  # Query using SAT protocol for USB bridge adapters with fallback for direct drives
  temp=$(smartctl -d sat -A "$dev" 2>/dev/null | awk '/^(194|190) / {print $10; exit}')
  [ -z "$temp" ] && temp=$(smartctl -A "$dev" 2>/dev/null | awk '/^(194|190) / {print $10; exit}')
  echo "$dev: ${temp:-Unavailable} °C"
done
