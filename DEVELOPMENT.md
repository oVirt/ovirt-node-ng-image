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
dnf install -y $(cat automation/build-artifacts.req.el8)

# check lorax version, you'll need lorax >= 28.14.57-2.el8
rpm -qv lorax

# run automated build
export STD_CI_STAGE="build-artifacts"
./automation/build-artifacts.sh
```

## Testing a change locally

Automated testing implies an oVirt Node build, an execution of the oVirt Node within a VM and a check of the health status of the oVirt Node.
The whole process can be triggered as `root` user with the same recommendations as for building oVirt Node.

```bash
# install test dependencies
dnf install -y $(cat automation/check-patch.req.el8)

# check lorax version, you'll need lorax >= 28.14.57-2.el8
rpm -qv lorax

# run automated tests
export STD_CI_STAGE="check-patch"
./automation/check-patch.sh
```
