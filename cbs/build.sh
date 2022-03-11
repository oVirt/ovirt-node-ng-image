#!/bin/bash -xe
sed \
	-e "s|@VERSION@|4.5.1|" \
    -e "s|@RELEASE@|$(date -u +%Y%m%d%H%M%S).1|" \
    <build.cfg.in >build.cfg

pushd ..
./autogen.sh \
    --with-distro=cbs8s \
    --with-bootisourl=http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/images/boot.iso
make data/ovirt-node-ng-image.ks
make ovirt-node-ng.spec PLACEHOLDER_RPM_VERSION=4.5.1 PLACEHOLDER_RPM_RELEASE=0.0
cp data/ovirt-node-ng-image.ks ovirt-node-ng.spec cbs/
popd

# cbs image-build --config build.cfg
