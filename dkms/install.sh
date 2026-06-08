#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo ./install.sh [--kernel VERSION] [--reload]

Build and install the Zenbook Duo patched hid-asus module with DKMS.

Options:
  --kernel VERSION  Build for VERSION instead of the running kernel.
  --reload          Reload hid_asus after installing.
  -h, --help        Show this help.
EOF
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
kernelver="$(uname -r)"
reload_module=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--kernel)
			[[ $# -ge 2 ]] || { echo "missing value for --kernel" >&2; exit 2; }
			kernelver="$2"
			shift 2
			;;
		--reload)
			reload_module=1
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
	args=(--kernel "$kernelver")
	if [[ ${reload_module} -eq 1 ]]; then
		args+=(--reload)
	fi
	exec sudo -- "$0" "${args[@]}"
fi

# shellcheck source=dkms.conf
source "${script_dir}/dkms.conf"
target="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"
build_dir="/lib/modules/${kernelver}/build"

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "missing required command: $1" >&2
		exit 1
	fi
}

need_cmd dkms
need_cmd make
need_cmd modinfo
need_cmd depmod

if [[ ! -d "${build_dir}" ]]; then
	cat >&2 <<EOF
Missing kernel build directory:
  ${build_dir}

Install the matching kernel-devel package first, for example:
  sudo dnf install "kernel-devel-${kernelver}" gcc make elfutils-libelf-devel dkms
EOF
	exit 1
fi

echo "Installing DKMS source to ${target}"
rm -rf "${target}"
mkdir -p "${target}"
if command -v rsync >/dev/null 2>&1; then
	rsync -a --delete --exclude='.git' "${script_dir}/" "${target}/"
else
	cp -a "${script_dir}/." "${target}/"
fi

if dkms status -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" 2>/dev/null | grep -q .; then
	echo "Removing existing DKMS registration for ${PACKAGE_NAME}/${PACKAGE_VERSION}"
	dkms remove -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" --all || true
fi

echo "Adding ${PACKAGE_NAME}/${PACKAGE_VERSION} to DKMS"
dkms add -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}"

echo "Building ${PACKAGE_NAME}/${PACKAGE_VERSION} for ${kernelver}"
dkms build -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" -k "${kernelver}"

echo "Installing ${PACKAGE_NAME}/${PACKAGE_VERSION} for ${kernelver}"
dkms install -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" -k "${kernelver}" --force
depmod "${kernelver}"

module_path="$(modinfo -k "${kernelver}" -n hid-asus 2>/dev/null || modinfo -k "${kernelver}" -n hid_asus 2>/dev/null || true)"
if [[ -n "${module_path}" ]]; then
	echo "modinfo resolves hid_asus to: ${module_path}"
	case "${module_path}" in
		*/updates/dkms/*) ;;
		*) echo "warning: hid_asus is not resolving from updates/dkms yet" >&2 ;;
	esac
fi

if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
	cat >&2 <<'EOF'
Secure Boot appears to be enabled. Fedora may refuse to load unsigned DKMS
modules unless you sign this module with an enrolled MOK key.
EOF
fi

if [[ ${reload_module} -eq 1 ]]; then
	"${target}/reload.sh"
else
	echo "Install complete. To load it now, run:"
	echo "  sudo ${target}/reload.sh"
fi
