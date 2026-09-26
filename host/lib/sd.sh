# shellcheck shell=bash
# shellcheck disable=SC2034  # SD_* are read by the scripts that source this
# Shared SD-card helpers for sd-list (user) and sd-write (root).
# Keep this macOS bash 3.2 compatible.

# Refuse anything bigger than this: SD cards for sensors are small, and a
# larger "removable" disk is far more likely to be a backup drive.
SD_MAX_BYTES=137438953472 # 128 GiB

plist_get() { # <plist-xml> <keypath>
  plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null
}

# Whole disk that holds the running system (e.g. disk0), best effort.
boot_whole_disk() {
  local info store
  info=$(diskutil info -plist / 2>/dev/null) || return 0
  store=$(plist_get "$info" APFSPhysicalStores.0.APFSPhysicalStore) ||
    store=$(plist_get "$info" ParentWholeDisk) || return 0
  echo "${store%s[0-9]*}"
}

# sd_eligible <diskN>
# Returns 0 if the disk is a safe write target and fills SD_SIZE / SD_MEDIA /
# SD_PROTO. Otherwise returns 1 with the reason in SD_REASON.
sd_eligible() {
  local d=$1 info
  SD_REASON='' SD_SIZE='' SD_MEDIA='' SD_PROTO=''
  case "$d" in
    disk[0-9] | disk[0-9][0-9]) ;;
    *) SD_REASON="invalid disk identifier: $d (expected diskN)"; return 1 ;;
  esac
  info=$(diskutil info -plist "/dev/$d" 2>/dev/null) || { SD_REASON="no such disk: $d"; return 1; }

  [ "$(plist_get "$info" WholeDisk)" = true ] || { SD_REASON="$d is not a whole disk"; return 1; }
  [ "$(plist_get "$info" VirtualOrPhysical)" = Physical ] || { SD_REASON="$d is not a physical disk"; return 1; }
  [ "$(plist_get "$info" RemovableMediaOrExternalDevice)" = true ] ||
    { SD_REASON="$d is not removable/external media"; return 1; }
  [ "$d" != "$(boot_whole_disk)" ] || { SD_REASON="$d holds the running system"; return 1; }

  SD_SIZE=$(plist_get "$info" TotalSize) || SD_SIZE=$(plist_get "$info" Size) ||
    { SD_REASON="cannot read size of $d"; return 1; }
  [ "$SD_SIZE" -gt 0 ] || { SD_REASON="$d has no media inserted"; return 1; }
  [ "$SD_SIZE" -le "$SD_MAX_BYTES" ] || { SD_REASON="$d is larger than 128 GiB"; return 1; }

  SD_MEDIA=$(plist_get "$info" MediaName) || SD_MEDIA='?'
  SD_PROTO=$(plist_get "$info" BusProtocol) || SD_PROTO='?'
  return 0
}

human_size() { awk -v b="$1" 'BEGIN { printf "%.1fGB", b / 1e9 }'; }
