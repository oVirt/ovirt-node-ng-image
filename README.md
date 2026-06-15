# oVirt Node NG Image

Welcome to the oVirt Node NG Image source repository.
This repository is hosted on [GitHub:oVirt Node NG Image](https://github.com/oVirt/ovirt-node-ng-image).

oVirt Node NG is a minimal operating system based on CentOS Stream (but can be based on any derivative)
that is designed to provide a simple method for setting up a physical machine to act as a hypervisor in an oVirt environment.
The minimal operating system contains only the packages required for the machine to act as a hypervisor
and features a Cockpit user interface for monitoring the host and performing administrative tasks.

Due to this minimalistic approach, oVirt Node NG is not recommended if you need to customize the configuration of
your virtualization hosts with multiple additional packages or third party software.

Built images of oVirt Node NG are available on [oVirt website](https://ovirt.org/download/node.html)

## 1. Build host requirements

- **CentOS Stream 9** or **AlmaLinux 9** (physical or VM with nested-virt enabled)
- root access, KVM, ≥4 GB RAM, ≥40 GB free disk
- Ubuntu/Debian are **not supported**

## 2. Install dependencies

```bash
sudo dnf install -y \
    autoconf automake expect kernel-modules libguestfs-tools libosinfo \
    libvirt-client lorax make openssh openssh-clients pigz \
    python3-jinja2 python3-pyyaml rpm-build squashfs-tools \
    virt-install wget xorriso
```

Check lorax version (needs ≥ `28.14.57-2.el8`):

```bash
rpm -qv lorax
```

## 3. Build

You can build the image using the provided `build.sh` script or manually via `make`.  
**Important:** You must use the `direct` backend for libguestfs to avoid SELinux/libvirt permission issues, and you must use `sudo` because the ISO creation script requires root privileges to mount loop devices.

### Option A – Using the wrapper script (recommended for beginners)

```bash
cd /path/to/ovirt-node-ng-image
export SUPERMIN_MODULES="/usr/lib/modules/$(uname -r)"
export LIBGUESTFS_BACKEND=direct
sudo -E ./build.sh
```

### Option B – Manual build step‑by‑step

```bash
cd /path/to/ovirt-node-ng-image

# 1. Generate the Makefile (autotools)
./autogen.sh --with-distro=c9s     # or --with-distro=alma9

# 2. Set required environment variables
export SUPERMIN_MODULES="/usr/lib/modules/$(uname -r)"
export LIBGUESTFS_BACKEND=direct

# Build the final ISO (this will also build the squashfs, product.img, etc. if missing)
# Use -E with sudo to preserve the exported environment variables
sudo -E make iso
```

**Artifacts** (in repo root and in `./exported-artifacts/`):

- `ovirt-node-ng-installer-<ver>-<YYYYMMDDHH>.<distro>.iso` — final installation ISO
- `ovirt-node-ng-image.squashfs.img` — root filesystem
- `product.img` — overlay for oVirt Engine in-place updates
- `*.manifest-rpm`, `*.unsigned-rpms` — package lists
- `tmp.repos/RPMS/noarch/*.rpm` — built update RPM

The build takes 30–90 minutes.

## 4. Build options

| Variable | Effect |
|----------|--------|
| `CHECK_ISO=True` | After build, deploy the ISO into a VM and run a smoke test (`setup-node-appliance.sh`) |
| `EXTRACT_INSTALL_LOGS=1` | Extract anaconda logs from the squashfs into `exported-artifacts/image-logs/` |
| `FINALBUILD=1` | Release build – removes the `IsAlpha` flag from `.buildstamp` |
| `SUPERMIN_KERNEL=…` | Use a custom kernel |

## 5. Development pipeline

What `build.sh` does internally:

1. `autogen.sh --with-distro=alma9|c9s` — autotools configure
2. `make squashfs` — kickstart → squashfs via `livemedia-creator`
3. `make product.img` — installer overlay
4. `make rpm` — build the update RPM
5. `make iso` — final ISO via `derive-boot-iso.sh`

Debug the kickstart interactively:

```bash
make debug-squashfs
```

## How to contribute

All contributions are welcome - patches, bug reports, and documentation issues.

You can find more details about how to develop and build oVirt Node NG in [Development](DEVELOPMENT.md) documentation.

### Submitting patches

Please submit patches to [GitHub:oVirt Node NG Image](https://github.com/oVirt/ovirt-node-ng-image).
If you are not familiar with the process, you can read about
[collaborating with pull requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests)
on the GitHub website.

### Found a bug or documentation issue?

To submit a bug or suggest an enhancement for oVirt Node NG Image please use
[oVirt Bugzilla](https://bugzilla.redhat.com/enter_bug.cgi?product=ovirt-node).

If you don't have a Bugzilla account, you can still report [issues](https://github.com/oVirt/ovirt-node-ng-image/issues).
If you find a documentation issue on the oVirt website, please navigate to the page footer and click "Report an issue on GitHub".

## Still need help?

If you have any other questions or suggestions, you can join and contact us on the [oVirt Users forum / mailing list](https://lists.ovirt.org/admin/lists/users.ovirt.org/).
