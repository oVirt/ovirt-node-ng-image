#!/bin/bash -xe

# podman run -v /lib/modules/$(uname -r):/host/modules --privileged quay.io/ovirt/buildcontainer:el8stream
echo custom modules: ${SUPERMIN_MODULES}
echo custom kernel: ${SUPERMIN_KERNEL}
echo extract install logs: ${EXTRACT_INSTALL_LOGS}
echo final build: ${FINALBUILD}

export EXPORTED_ARTIFACTS=${EXPORTED_ARTIFACTS:-$PWD/exported-artifacts}

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_TMPDIR=/var/tmp
export LIBGUESTFS_CACHEDIR=$LIBGUESTFS_TMPDIR

on_exit() {
  ln -fv data/ovirt-node*.ks *.log "$EXPORTED_ARTIFACTS/"
  cleanup
}

trap on_exit EXIT

prepare() {
    mkdir -p "$EXPORTED_ARTIFACTS"

    mknod /dev/kvm c 10 232 || :
    mknod /dev/vhost-net c 10 238 || :
    mkdir /dev/net || :
    mknod /dev/net/tun c 10 200 || :
    seq 0 9 | xargs -I {} mknod /dev/loop{} b 7 {} || :

    virsh list --name | xargs -rn1 virsh destroy || :
    virsh list --all --name | xargs -rn1 virsh undefine --remove-all-storage || :
    losetup -O BACK-FILE | grep -v BACK-FILE | grep iso$ | xargs -r umount -dvf ||:

    virt-host-validate ||:

    [ -f ${SUPERMIN_MODULES}/kernel/fs/squashfs/squashfs* ] || { echo missing squashfs module in ${SUPERMIN_MODULES}; exit 1; }
}

prepare_osinfo_db() {
    local osinfo_dir="/usr/share/osinfo/os/ovirt.org"
    mkdir -p ${osinfo_dir}
    cp data/ovirt-osinfo.xml ${osinfo_dir}/ovirt-4.xml
}

build() {
    dist="$(rpm --eval %{dist})"
    dist=${dist##.}

    case ${dist} in
        el8)
            prepare_osinfo_db
            export SSG_TARGET_XML=/usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml
            export SHIP_OVIRT_CONF=1
            ./autogen.sh
            ;;
        el9)
            prepare_osinfo_db
            export SSG_TARGET_XML=/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
            export SHIP_OVIRT_CONF=1
            ./autogen.sh \
                --with-distro=c9s \
                --with-bootisourl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-boot.iso
            ;;
    esac

    make squashfs &
    tail -f virt-install.log --pid=$! --retry ||:

    # move out anaconda build logs and export them for debugging
    [[ -n "$EXTRACT_INSTALL_LOGS" ]] && {
        tmpdir=$(mktemp -d)
        mkdir $EXPORTED_ARTIFACTS/image-logs
        mv ovirt-node-ng-image.squashfs.img{,.orig}
        unsquashfs ovirt-node-ng-image.squashfs.img.orig
        mount squashfs-root/LiveOS/rootfs.img $tmpdir
        mv $tmpdir/var/log/anaconda $EXPORTED_ARTIFACTS/image-logs/var_log_anaconda || :
        mv $tmpdir/root/*ks* $EXPORTED_ARTIFACTS/image-logs || :
        umount $tmpdir
        rmdir $tmpdir
        mksquashfs squashfs-root ovirt-node-ng-image.squashfs.img -noappend -comp xz
    }

# don't push squashfs to exported-artifacts,
#        ovirt-node*.squashfs.img \
    ln -fv \
        *manifest* \
        *unsigned* \
        "$EXPORTED_ARTIFACTS/"


    make product.img rpm

# don't push rpms to exported-artifacts, uploaded separately
#        tmp.repos/SRPMS/*.rpm \
#        tmp.repos/RPMS/noarch/*.rpm \
    ln -fv \
        product.img \
        "$EXPORTED_ARTIFACTS/"

# skip old iso target relying on jenkins and skip the squashfs
#    make offline-installation-iso
#    mv -fv ovirt-node-ng-image.squashfs.img \
#           ovirt-node-ng-image-$(date +%Y%m%d).squashfs.img

    make iso
# do not push iso to exported-artifacts, uploaded separately
#    ln -fv \
#        ovirt-node*.iso \
#        "$EXPORTED_ARTIFACTS/"

}

cleanup() {
    # Kill qemu-kvm in case it has been left around.
    killall qemu-kvm ||:
    # Remove device-mapper files that were created by kpartx in LMC
    dmsetup ls | \
        grep ^loop | \
        awk '{print $1}' | \
        xargs -r -I {} dmsetup remove -f --retry /dev/mapper/{} ||:

    # umount and detach
    losetup -O BACK-FILE | grep -v BACK-FILE | xargs -r umount -vdf ||:
    losetup -v -D ||:
}

fetch_remote() {
    local sshkey=$1
    local addr=$2
    local path=$3
    local dest=$4
    local compress=$5

    scp -o "UserKnownHostsFile /dev/null" \
        -o "StrictHostKeyChecking no" \
        -i $sshkey -r root@$addr:$path $dest ||:

    [[ -n $compress ]] && {
        tar czf $dest.tgz $dest && mv $dest.tgz $EXPORTED_ARTIFACTS
    }||:
}

check_iso() {
    LOGDIR="${EXPORTED_ARTIFACTS}" ISO_INSTALL_TIMEOUT=40 ./scripts/node-setup/setup-node-appliance.sh \
        -i ovirt-node*.iso \
        -p ovirt > setup-iso.log 2>&1 || setup_rc=$?

    local name=$(grep available setup-iso.log | cut -d: -f1)
    local addr=$(grep -Po "(?<=at ).*" setup-iso.log)
    local wrkdir=$(grep -Po "(?<=WORKDIR: ).*" setup-iso.log)
    local sshkey="$wrkdir/sshkey-${name}"

    fetch_remote "$sshkey" "$addr" "/tmp" "init_tmp" "1"
    fetch_remote "$sshkey" "$addr" "/var/log" "init_var_log" "1"

    [[ $setup_rc -ne 0 ]] && {
        mv ovirt-node*.iso *.tgz $EXPORTED_ARTIFACTS
        echo "ISO install failed, exiting"
        exit 1
    }

    cat *nodectl-check*.log

    status1=$(grep -Po "(?<=Status: ).*" *nodectl-check*.log)
    status2=$(grep Status network-check.log |cut -d' ' -f2)
    status3=$(test $(grep ansible_distribution_major_version *node-ansible-check.log |cut -d\" -f4) -eq "8" && echo "OK")

    [[ "$status1" == *OK* && "$status2" == *OK* && "$status3" == *OK* ]] || {
        echo "Invalid node status"
        exit 1
    }
}

prepare
build
# check_iso not working

echo "Done."
