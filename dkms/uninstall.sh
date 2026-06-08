#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo ./uninstall.sh [--reload-stock]

Remove the Zenbook Duo patched hid-asus DKMS module.

Options:
  --reload-stock  Reload the distro hid_asus module after removing DKMS.
  -h, --help      Show this help.
EOF
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
reload_stock=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--reload-stock)
			reload_stock=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [[ ${EUID} -ne 0 ]]; then
	args=()
	if [[ ${reload_stock} -eq 1 ]]; then
		args+=(--reload-stock)
	fi
	exec sudo -- "$0" "${args[@]}"
fi

# shellcheck source=dkms.conf
kernelver="$(uname -r)"
source "${script_dir}/dkms.conf"
target="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"

if dkms status -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" 2>/dev/null | grep -q .; then
	dkms remove -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" --all
fi

rm -rf "${target}"
depmod "$(uname -r)"

if [[ ${reload_stock} -eq 1 ]]; then
	echo "Reloading distro hid_asus"
	modprobe -r hid_asus 2>/dev/null || modprobe -r hid-asus 2>/dev/null || true
	modprobe hid_asus 2>/dev/null || modprobe hid-asus
fi

echo "Removed ${PACKAGE_NAME}/${PACKAGE_VERSION}"
