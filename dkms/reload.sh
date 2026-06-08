#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
	exec sudo -- "$0" "$@"
fi

echo "Reloading hid_asus"
modprobe -r hid_asus 2>/dev/null || modprobe -r hid-asus 2>/dev/null || true
modprobe hid_asus 2>/dev/null || modprobe hid-asus

module_path="$(modinfo -n hid-asus 2>/dev/null || modinfo -n hid_asus 2>/dev/null || true)"
if [[ -n "${module_path}" ]]; then
	echo "Loaded module path: ${module_path}"
fi
