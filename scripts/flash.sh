#!/bin/zsh
# Flash the mactouch firmware, taking a full flash backup first (skip with --no-backup).
#
# The running firmware owns the USB port, so esptool cannot reset the chip into
# download mode by itself. Either run `mactouch bootloader` first (mactouch
# firmware), or hold the BOOT button while plugging the board in (any firmware).
# In download mode the board shows up as a new /dev/cu.usbmodem* device.
set -euo pipefail

here="${0:A:h}"
firmware="$here/../firmware"
backups="$here/../backups"
backup_wanted=true
if [[ "${1:-}" == "--no-backup" ]]; then backup_wanted=false; shift; fi
port="${1:-}"

if [[ -z "$port" ]]; then
  ports=(/dev/cu.usbmodem*(N))
  (( ${#ports} == 1 )) || { print -u2 "Pass the port: found ${#ports} usbmodem devices."; exit 2 }
  port="${ports[1]}"
fi

print "Port: $port"
esptool.py --chip esp32s3 --port "$port" --before default_reset --after no_reset --connect-attempts 5 flash_id | grep -E "Detected flash size|Chip is|MAC"

if $backup_wanted; then
  mkdir -p "$backups"
  backup="$backups/flash-$(date +%Y%m%d-%H%M%S).bin"
  print "Backing up the whole flash to $backup"
  esptool.py --chip esp32s3 --port "$port" -b 921600 --before no_reset --after no_reset read_flash 0 ALL "$backup"
fi

print "Flashing $firmware/build/mactouch.bin"
cd "$firmware/build"
esptool.py --chip esp32s3 --port "$port" -b 921600 --before default_reset --after watchdog_reset write_flash "@flash_args"

print
print "Done. The board has been reset into the new firmware."
if $backup_wanted; then
  print "Restore the old firmware with:"
  print "  esptool.py --chip esp32s3 --port <port> write_flash 0 $backup"
fi
