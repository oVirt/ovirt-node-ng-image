# oVirt Node development guide

## Building oVirt Node

This project is usually built within an el8 mock environment within an automation environment
which can be destroyed after the build.
It is not recommended to try to build on a system which contains valuable data since the system
can be corrupted by the build process.

It's higly recommended to run the build in an CentOS Stream 8 virtual machine with nested virtualization enabled.

as `root` user:

```bash
# install build dependencies
dnf install -y \
    autoconf \
    automake \
    expect \
    kernel-modules \
    libguestfs-tools \
    libosinfo \
    libvirt-client \
    lorax \
    make \
    openssh \
    openssh-clients \
    pigz \
    python3-jinja2 \
    python3-pyyaml \
    rpm-build \
    squashfs-tools \
    virt-install \
    wget \
    xorriso

# check lorax version, you'll need lorax >= 28.14.57-2.el8
rpm -qv lorax

# run automated build
export SUPERMIN_MODULES="/usr/lib/modules/$(uname -r)"
./build.sh
```



## Testing a change locally

Automated testing implies an oVirt Node build, an execution of the oVirt Node within a VM and a check of the health status of the oVirt Node.
The whole process can be triggered as `root` user with the same recommendations as for building oVirt Node.

```bash
export SUPERMIN_MODULES="/usr/lib/modules/$(uname -r)"
export CHECK_ISO="True"
./build.sh
```

## Testing a change locally using vscode devcontainers

Note: The devcontainer itself needs to run on a RHEL-like system (eg. AlmaLinux 9 etc). The build cannot be (currently) performed on an Ubuntu system. Ubuntu users should use the remote-ssh vscode extension and 
connect to an EL9 type VM for development purposes.

The devcontainer allows you to select the system you want to build. Currently AlmaLinux 9 or Centos 9 Stream. This is currently required due to the way the build.sh script determines the environment type and
is subject to change in the future to simplify things.

From vscode, if you have the devcontainer extension installed you will be prompted to reopen in a dev container - select almalinux9 if that's what you want to build or one of the other options. You should select this option or press <F1> and search for devcontainer and reopen in container.
Once the container has been built and running you should create a bash shell via the '+' on the lower right hand side of the screen.

Once bash is open you can :

```bash
./build.sh
```

Note: vscode will tell you that the VM has opened a remote access port (eg 5900). You can use something like vncviewer to connect to that port and watch the build in real-time. 