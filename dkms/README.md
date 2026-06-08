# Zenbook Duo hid-asus DKMS Package

This directory contains a DKMS package for the patched `hid-asus` module used
to test ASUS Zenbook Duo 2024 keyboard support.

It installs the module source into `/usr/src/zenbook-duo-hid-asus-0.1.0`,
builds `hid-asus.ko` against the target kernel, and installs it under
`/lib/modules/<kernel>/updates/dkms/` so it overrides Fedora's stock
`hid-asus` module after `depmod`.

## Install

Install the build dependencies for the running kernel:

```bash
sudo dnf install dkms "kernel-devel-$(uname -r)" gcc make elfutils-libelf-devel
```

From this directory:

```bash
sudo ./install.sh --reload
```

To build for a kernel that is installed but not currently running:

```bash
sudo ./install.sh --kernel 6.19.10-300.fc44.x86_64
```

## Verify

```bash
dkms status zenbook-duo-hid-asus
modinfo -n hid_asus
```

The module path should normally include `updates/dkms`.

## Kernel Updates

DKMS should rebuild automatically when a new kernel is installed, provided the
matching `kernel-devel-<version>` package is present. To force a rebuild for
the running kernel:

```bash
sudo dkms autoinstall -k "$(uname -r)"
```

## Uninstall

From this directory or from `/usr/src/zenbook-duo-hid-asus-0.1.0`:

```bash
sudo ./uninstall.sh --reload-stock
```

## Secure Boot

If Secure Boot is enabled, Fedora may refuse to load unsigned DKMS-built
modules. Either disable Secure Boot or sign the DKMS module with a key enrolled
through MOK.
