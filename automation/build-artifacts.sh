#!/bin/bash -xe

export BRANCH=${GERRIT_BRANCH#*/}
export ARTIFACTSDIR=$PWD/exported-artifacts

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_TMPDIR=/var/tmp
export LIBGUESTFS_CACHEDIR=$LIBGUESTFS_TMPDIR

on_exit() {
  ln -fv data/ovirt-node*.ks *.log "$ARTIFACTSDIR/"
  cleanup
}

trap on_exit EXIT

prepare() {
    mkdir -p "$ARTIFACTSDIR"

    mknod /dev/kvm c 10 232 || :
    mknod /dev/vhost-net c 10 238 || :
    mkdir /dev/net || :
    mknod /dev/net/tun c 10 200 || :
    seq 0 9 | xargs -I {} mknod /dev/loop{} b 7 {} || :

    virsh list --name | xargs -rn1 virsh destroy || :
    virsh list --all --name | xargs -rn1 virsh undefine --remove-all-storage || :
    losetup -O BACK-FILE | grep -v BACK-FILE | grep iso$ | xargs -r umount -dvf ||:

    virt-host-validate ||:
}

build() {
    dist="$(rpm --eval %{dist})"
    dist=${dist##.}

    if [[ ${dist} = fc* ]]; then
        export SHIP_OVIRT_INSTALLCLASS=1
        ./autogen.sh --with-tmpdir=/var/tmp --with-distro=${dist}
    else
        export SSG_TARGET_XML=/usr/share/xml/scap/ssg/content/ssg-centos7-ds.xml
        ./autogen.sh --with-tmpdir=/var/tmp
    fi

    make squashfs &
    tail -f virt-install.log --pid=$! --retry ||:

    # move out anaconda build logs and export them for debugging
    [[ $STD_CI_STAGE = "build-artifacts" ]] && {
        tmpdir=$(mktemp -d)
        mkdir $ARTIFACTSDIR/image-logs
        mv ovirt-node-ng-image.squashfs.img{,.orig}
        unsquashfs ovirt-node-ng-image.squashfs.img.orig
        mount squashfs-root/LiveOS/rootfs.img $tmpdir
        mv $tmpdir/var/log/anaconda $ARTIFACTSDIR/image-logs/var_log_anaconda || :
        mv $tmpdir/root/*ks* $ARTIFACTSDIR/image-logs || :
        umount $tmpdir
        rmdir $tmpdir
        mksquashfs squashfs-root ovirt-node-ng-image.squashfs.img -noappend -comp xz
    }

    make product.img rpm
    make offline-installation-iso
    mv -fv ovirt-node-ng-image.squashfs.img \
           ovirt-node-ng-image-$(date +%Y%m%d).squashfs.img

    ln -fv \
        *manifest* \
        *unsigned* \
        tmp.repos/SRPMS/*.rpm \
        tmp.repos/RPMS/noarch/*.rpm \
        ovirt-node*.squashfs.img \
        product.img \
        ovirt-node*.iso \
        "$ARTIFACTSDIR/"
}

cleanup() {
    # Remove device-mapper files that were created by kpartx in LMC
    dmsetup ls | \
        grep ^loop | \
        awk '{print $1}' | \
        xargs -r -I {} dmsetup remove -f --retry /dev/mapper/{} ||:

    # umount and detach
    losetup -O BACK-FILE | grep -v BACK-FILE | xargs -r umount -vdf ||:
    losetup -v -D ||:
}

check_iso() {
  ./scripts/node-setup/setup-node-appliance.sh -i ovirt-node*.iso -p ovirt
  cat *nodectl-check*.log

  status1=$(grep -Po "(?<=Status: ).*" *nodectl-check*.log)
  status2=$(grep Status network-check.log |cut -d' ' -f2)

  [[ "$status1" == *OK* || "$status2" == *OK* ]] || {
    echo "Invalid node status"
    exit 1
  }
}

checksum() {
    pushd "$ARTIFACTSDIR/"
    sha256sum * > CHECKSUMS.sha256 || :

    # Helper to redirect to latest installation iso
    INSTALLATIONISO=$(ls *.iso)

    cat << EOF > latest-installation-iso.html
<html>
  <head>
    <meta http-equiv='refresh' content='0; url="$INSTALLATIONISO"'/>
  </head>
  <body>
    If the download doesn't start, <a href="$INSTALLATIONISO">click here</a>
  </body>
</html>
EOF
    popd
}

prepare
build
[[ $STD_CI_STAGE = "build-artifacts" ]] && checksum || check_iso

echo "Done."
