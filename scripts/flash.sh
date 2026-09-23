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

# The daemon holds the device; give esptool the port and bring it back after.
label="dev.mactouch.daemon"
daemon_was_loaded=false
if launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
  daemon_was_loaded=true
  launchctl bootout "gui/$UID/$label"
fi
pkill -f "debug/mactouchd" 2>/dev/null || true

print "Port: $port"
esptool.py --chip esp32s3 --port "$port" --before default_reset --after no_reset --connect-attempts 5 flash_id | grep -E "Detected flash size|Chip is|MAC"

# Once the bootloader has enabled flash encryption (SPI_BOOT_CRYPT_CNT set),
# plain writes would leave unreadable garbage; the ROM encrypts on the way in
# when asked. Before that first boot the plain write is what enables it.
encrypt=()
if espefuse.py --chip esp32s3 --port "$port" --before no_reset summary 2>/dev/null | grep -E "^SPI_BOOT_CRYPT_CNT" | grep -qE "0b0*1|= [1-7] "; then
  encrypt=(--encrypt)
  print "Flash encryption is on; writing encrypted."
fi

if $backup_wanted; then
  mkdir -p "$backups"
  backup="$backups/flash-$(date +%Y%m%d-%H%M%S).bin"
  print "Backing up the whole flash to $backup"
  esptool.py --chip esp32s3 --port "$port" -b 921600 --before no_reset --after no_reset read_flash 0 ALL "$backup"
fi

print "Flashing $firmware/build/mactouch.bin"
cd "$firmware/build"
esptool.py --chip esp32s3 --port "$port" -b 921600 --before default_reset --after watchdog_reset write_flash "${encrypt[@]}" "@flash_args"

print
print "Done. The board has been reset into the new firmware."
if $daemon_was_loaded; then
  sleep 2
  "$here/daemon.sh" start
  print "mactouchd restarted."
fi
if $backup_wanted; then
  print "Restore the old firmware with (the dump of an encrypted chip is ciphertext; it restores to the same chip as is):"
  print "  esptool.py --chip esp32s3 --port <port> write_flash 0 $backup"
fi
