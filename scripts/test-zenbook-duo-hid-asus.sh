#!/usr/bin/env bash
# Build and live-test the patched ASUS Zenbook Duo hid-asus module.

set -euo pipefail

expected_kernel_prefix="6.19.10-300.fc44"
monitor_seconds=20
build_only=0
restore_only=0
force_kernel=0
no_monitor=0
kver="${KERNELRELEASE:-$(uname -r)}"

usage() {
	cat <<'EOF'
Usage: scripts/test-zenbook-duo-hid-asus.sh [options]

Builds the patched hid-asus.ko from this checkout against the running Fedora
kernel headers, loads it for a live test, then prints device/backlight status.

Options:
  --build-only          Build hid-asus.ko but do not load it.
  --restore             Unload the test module and reload the stock hid_asus.
  --kernel VERSION      Build against /lib/modules/VERSION/build.
  --force-kernel        Allow kernels other than 6.19.10-300.fc44*.
  --monitor-seconds N   Run the interactive key-event monitor for N seconds.
  --no-monitor          Skip the interactive key-event monitor.
  -h, --help            Show this help.

Environment:
  KERNEL_BUILD_DIR      Override the kernel build directory.
  ZENBOOK_DUO_BUILD_ROOT
                        Override the module build output directory.

Required Fedora packages:
  sudo dnf install "kernel-devel-$(uname -r)" gcc make kmod

Restore stock module after testing:
  scripts/test-zenbook-duo-hid-asus.sh --restore
EOF
}

log() {
	printf '[zenbook-duo-hid] %s\n' "$*"
}

warn() {
	printf '[zenbook-duo-hid] warning: %s\n' "$*" >&2
}

die() {
	printf '[zenbook-duo-hid] error: %s\n' "$*" >&2
	exit 1
}

run_root() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--build-only)
			build_only=1
			;;
		--restore)
			restore_only=1
			;;
		--kernel)
			[[ $# -ge 2 ]] || die "--kernel requires a version"
			kver="$2"
			shift
			;;
		--force-kernel)
			force_kernel=1
			;;
		--monitor-seconds)
			[[ $# -ge 2 ]] || die "--monitor-seconds requires a number"
			monitor_seconds="$2"
			shift
			;;
		--no-monitor)
			no_monitor=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown option: $1"
			;;
	esac
	shift
done

case "$monitor_seconds" in
	''|*[!0-9]*)
		die "--monitor-seconds must be a positive integer"
		;;
esac

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
kernel_build="${KERNEL_BUILD_DIR:-/lib/modules/$kver/build}"
build_root="${ZENBOOK_DUO_BUILD_ROOT:-$repo_root/.zenbook-duo-hid-build/$kver}"
module_build_dir="$build_root/module"
ko_path="$module_build_dir/hid-asus.ko"

restore_stock_module() {
	log "Restoring stock hid_asus for kernel $kver"
	if lsmod | awk '$1 == "hid_asus" { found = 1 } END { exit !found }'; then
		run_root modprobe -r hid_asus
	fi
	run_root modprobe hid_asus
	log "Stock hid_asus loaded through modprobe."
}

if [[ $restore_only -eq 1 ]]; then
	restore_stock_module
	exit 0
fi

if [[ "$kver" != "$expected_kernel_prefix"* && $force_kernel -ne 1 ]]; then
	die "running kernel is '$kver'; expected ${expected_kernel_prefix}*. Use --force-kernel to override."
fi

for cmd in awk cp grep lsmod make modinfo modprobe sed timeout; do
	command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done

[[ -f "$repo_root/drivers/hid/hid-asus.c" ]] || die "missing drivers/hid/hid-asus.c; run from the linux checkout"
[[ -f "$repo_root/drivers/hid/hid-ids.h" ]] || die "missing drivers/hid/hid-ids.h; run from the linux checkout"
[[ -f "$kernel_build/Makefile" ]] || die "missing kernel build tree: $kernel_build. Install kernel-devel-$kver."

if [[ -d /sys/module/hid_asus ]] &&
   ! lsmod | awk '$1 == "hid_asus" { found = 1 } END { exit !found }'; then
	die "hid_asus appears to be built into this kernel; it cannot be replaced live."
fi

config_file=""
for candidate in "$kernel_build/.config" "/boot/config-$kver"; do
	if [[ -r "$candidate" ]]; then
		config_file="$candidate"
		break
	fi
done

if [[ -n "$config_file" ]]; then
	if grep -q '^CONFIG_HID_ASUS=y' "$config_file"; then
		die "CONFIG_HID_ASUS=y in $config_file; live module replacement is not possible."
	elif ! grep -q '^CONFIG_HID_ASUS=m' "$config_file"; then
		warn "CONFIG_HID_ASUS is not set to m in $config_file; build/load may fail."
	fi
else
	warn "could not find a kernel config to confirm CONFIG_HID_ASUS=m."
fi

if command -v mokutil >/dev/null 2>&1; then
	sb_state="$(mokutil --sb-state 2>/dev/null || true)"
	if printf '%s\n' "$sb_state" | grep -qi 'SecureBoot enabled'; then
		warn "Secure Boot is enabled. An unsigned test module may be rejected by the kernel."
	fi
fi

rm -rf -- "$module_build_dir"
mkdir -p -- "$module_build_dir"
cp -- "$repo_root/drivers/hid/hid-asus.c" "$module_build_dir/hid-asus.c"
cp -- "$repo_root/drivers/hid/hid-ids.h" "$module_build_dir/hid-ids.h"

cat > "$module_build_dir/Makefile" <<'EOF'
obj-m += hid-asus.o
EOF

grep -q 'USB_DEVICE_ID_ASUSTEK_ZENBOOK_DUO_KEYBOARD' "$module_build_dir/hid-ids.h" ||
	die "Zenbook Duo HID IDs are missing from hid-ids.h"
grep -q 'case 0x86:.*Zenbook Duo MyASUS' "$module_build_dir/hid-asus.c" ||
	die "Zenbook Duo MyASUS key mapping is missing from hid-asus.c"
grep -q 'QUIRK_ZENBOOK_DUO_KEYBOARD' "$module_build_dir/hid-asus.c" ||
	die "Zenbook Duo descriptor quirk is missing from hid-asus.c"
grep -q 'Injecting virtual Zenbook Duo keyboard usage page' "$module_build_dir/hid-asus.c" ||
	die "Zenbook Duo USB vendor-interface input fixup is missing from hid-asus.c"

log "Building hid-asus.ko for $kver"
make -C "$kernel_build" M="$module_build_dir" modules
[[ -f "$ko_path" ]] || die "module build did not produce $ko_path"

vermagic="$(modinfo -F vermagic "$ko_path")"
log "Built $ko_path"
log "Module vermagic: $vermagic"
if [[ "$vermagic" != "$kver "* ]]; then
	die "module vermagic does not match running kernel '$kver'"
fi

aliases="$(modinfo -F alias "$ko_path" || true)"
for product in 00001B2C 00001B2D 00001BF2 00001BF3; do
	if ! printf '%s\n' "$aliases" | grep -qi "v00000B05p$product"; then
		die "built module alias table is missing ASUS product $product"
	fi
done
log "Module aliases include Zenbook Duo USB/Bluetooth keyboard IDs."

if [[ $build_only -eq 1 ]]; then
	log "Build-only mode complete."
	exit 0
fi

depends="$(modinfo -F depends "$ko_path" | tr ',' ' ')"
for dep in $depends; do
	[[ -n "$dep" ]] || continue
	run_root modprobe "$dep" || warn "could not preload dependency '$dep'"
done

log "Unloading stock hid_asus if present"
if lsmod | awk '$1 == "hid_asus" { found = 1 } END { exit !found }'; then
	run_root modprobe -r hid_asus
fi

log "Loading patched hid_asus with insmod"
run_root insmod "$ko_path"
[[ -d /sys/module/hid_asus ]] || die "hid_asus did not appear in /sys/module after insmod"
log "Patched hid_asus is loaded."

print_matching_devices() {
	local found=0
	local dev modalias upper driver name

	log "Matching ASUS Zenbook Duo HID devices:"
	shopt -s nullglob
	for dev in /sys/bus/hid/devices/*; do
		modalias="$(cat "$dev/modalias" 2>/dev/null || true)"
		upper="${modalias^^}"
		case "$upper" in
			*V00000B05P00001B2C*|*V00000B05P00001B2D*|*V00000B05P00001BF2*|*V00000B05P00001BF3*)
				found=1
				name="$(cat "$dev/name" 2>/dev/null || true)"
				if [[ -L "$dev/driver" ]]; then
					driver="$(basename -- "$(readlink -- "$dev/driver")")"
				else
					driver="unbound"
				fi
				printf '  %s driver=%s name=%s modalias=%s\n' \
					"$(basename -- "$dev")" "$driver" "$name" "$modalias"
				for event in "$dev"/input/input*/event*; do
					[[ -e "$event" ]] || continue
					printf '    event node: /dev/input/%s\n' "$(basename -- "$event")"
				done
				;;
		esac
	done
	shopt -u nullglob

	if [[ $found -eq 0 ]]; then
		warn "no Zenbook Duo keyboard HID device is currently visible. Reattach the keyboard or toggle Bluetooth, then rerun this script."
	fi
}

print_backlight_status() {
	local led found=0 brightness max_brightness

	log "Keyboard backlight LED devices:"
	shopt -s nullglob
	for led in /sys/class/leds/*kbd_backlight*; do
		found=1
		brightness="$(cat "$led/brightness" 2>/dev/null || printf '?')"
		max_brightness="$(cat "$led/max_brightness" 2>/dev/null || printf '?')"
		printf '  %s brightness=%s max=%s\n' \
			"$(basename -- "$led")" "$brightness" "$max_brightness"
	done
	shopt -u nullglob

	if [[ $found -eq 0 ]]; then
		warn "no *kbd_backlight* LED is currently visible."
	fi
}

print_matching_devices
print_backlight_status

if [[ $no_monitor -eq 0 && -t 0 && -t 1 ]]; then
	printf '\nPress Enter, then press volume, screen-brightness, and keyboard-backlight keys for %s seconds.\n' "$monitor_seconds"
	printf 'The monitor is only a smoke test; also verify the keys in your desktop session.\n'
	read -r -p 'Start monitor now? [Enter/Ctrl-C] ' _
	if command -v libinput >/dev/null 2>&1; then
		run_root timeout "$monitor_seconds" libinput debug-events --show-keycodes || true
	elif command -v evtest >/dev/null 2>&1; then
		printf 'Select the Zenbook Duo keyboard event device if prompted.\n'
		run_root timeout "$monitor_seconds" evtest || true
	else
		warn "install libinput-utils or evtest for interactive key-event monitoring."
	fi
else
	log "Skipping interactive key monitor."
fi

cat <<EOF

Patched module is loaded from:
  $ko_path

Manual checks:
  - Reattach the detachable keyboard if it was already connected.
  - Press volume up/down/mute, screen brightness, and keyboard backlight keys.
  - Try direct keyboard backlight control: brightnessctl -d 'asus::kbd_backlight' set 1+
  - Check kernel logs with: dmesg -Tw | tail -80

Restore stock module:
  $repo_root/scripts/test-zenbook-duo-hid-asus.sh --restore
EOF
