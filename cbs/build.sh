#!/bin/bash -xe
sed \
	-e "s|@VERSION@|4.5.0|" \
    -e "s|@RELEASE@|$(date -u +%Y%m%d%H%M%S).1|" \
    <build.cfg.in >build.cfg

pushd ..
./autogen.sh \
    --with-distro=cbs9s \
    --with-bootisourl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-boot.iso
make data/ovirt-node-ng-image.ks
make ovirt-node-ng.spec PLACEHOLDER_RPM_VERSION=4.5.0 PLACEHOLDER_RPM_RELEASE=0.0
cp data/ovirt-node-ng-image.ks ovirt-node-ng.spec cbs/
popd

cbs image-build --config build.cfg
