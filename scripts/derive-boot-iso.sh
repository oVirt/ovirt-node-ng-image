#!/bin/bash

# Usage: bash derive-boot-iso.sh boot.iso ovirt-node-ng-image.squashfs.img

set -e

BOOTISO=$(realpath $1)
SQUASHFS=$(realpath $2)
NEWBOOTISO=$(realpath ${3:-$(dirname $BOOTISO)/new-$(basename $BOOTISO)})
PRODUCTIMG=$(realpath ./product.img)

TMPDIR=$(realpath bootiso.d)

die() { echo "ERROR: $@" >&2 ; exit 2 ; }
cond_out() { "$@" > .tmp.log 2>&1 || { cat .tmp.log >&2 ; die "Failed to run $@" ; } && rm .tmp.log || : ; return $? ; }
in_squashfs() { TMPDIR=/var/tmp guestfish --ro -a ${SQUASHFS} run : mount /dev/sda / : mount-loop /LiveOS/rootfs.img / : sh "$1" ; }

extract_iso() {
  echo "[1/4] Extracting ISO"
  cond_out checkisomd5 --verbose $BOOTISO
  local ISOFILES=$(isoinfo -i $BOOTISO -RJ -f | sort -r | egrep "/.*/")
  for F in $ISOFILES
  do
    mkdir -p ./$(dirname $F)
    [[ -d .$F ]] || { isoinfo -i $BOOTISO -RJ -x $F > .$F ; }
  done
}

add_payload() {
  echo "[2/4] Adding image to ISO"
  cond_out unsquashfs -ll $SQUASHFS
  local DST=$(basename $SQUASHFS)
  # Add squashfs
  cp $SQUASHFS $DST
  cat > interactive-defaults.ks <<EOK
timezone --utc Etc/UTC

liveimg --url=file:///run/install/repo/$DST

%post --erroronfail
imgbase layout --init
%end
EOK
  # Add branding
  local os_release=$(mktemp -p /var/tmp)
  in_squashfs "cat /etc/os-release" > ${os_release}

  # Which install image should we use as stage2
  local install_img="LiveOS/squashfs.img"
  if [[ ! -f ${install_img} ]]; then
      install_img="images/install.img" # Fedora-based isos
  fi
  install_img=$(realpath ${install_img})

  # Process stage2 image in a different dir
  local stage2_dir=$(mktemp -dp /var/tmp)
  pushd ${stage2_dir}
    mkdir mntroot
    unsquashfs ${install_img} && rm -f ${install_img}
    mount squashfs-root/LiveOS/rootfs.img mntroot
    mv -vf ${os_release} mntroot/etc/os-release
    umount -dvf mntroot
    mksquashfs squashfs-root install.squashfs.img -noappend -comp xz
  popd
  mv -vf ${stage2_dir}/install.squashfs.img ${install_img}
  rm -rf ${stage2_dir}

  # and the kickstart
  if [[ -e "$PRODUCTIMG" ]]; then
    cp "$PRODUCTIMG" images/product.img
  fi
}

modify_bootloader() {
  echo "[3/4] Updating bootloader"
  # grep -rn stage2 *
  local EFIMNT=$(mktemp -d)
  mount -o rw images/efiboot.img $EFIMNT
  local CFGS="EFI/BOOT/grub.cfg isolinux/isolinux.cfg isolinux/grub.conf $EFIMNT/EFI/BOOT/grub.cfg"
  local LABEL=$(egrep -h -o "hd:LABEL[^ :]*" $CFGS  | sort -u)
  local ORIG_NAME=$(grep -Po "(?<=^menu title ).*" isolinux/isolinux.cfg)
  local INNER_PRETTY_NAME=$(in_squashfs "grep PRETTY_NAME /etc/os-release" | cut -d "=" -f2 | tr -d \")
  sed -i \
	-e "/stage2/ s%$% inst.ks=${LABEL//\\/\\\\}:/interactive-defaults.ks%" \
	-e "/^\s*\(append\|initrd\|linux\|search\)/! s%${ORIG_NAME}%${INNER_PRETTY_NAME}%g" \
	-e "s/Rescue a .* system/Rescue a ${INNER_PRETTY_NAME} system/g" \
	$CFGS
  umount -dvf $EFIMNT
  rmdir $EFIMNT
}

create_iso() {
  echo "[4/4] Creating new ISO"
  local volid=$(isoinfo -d -i $BOOTISO | grep "Volume id" | cut -d ":" -f2 | sed "s/^ //")
  rm -rvf $TMPDIR/tmp*
  mkisofs -J -T -U \
      -joliet-long \
      -o $NEWBOOTISO \
      -b isolinux/isolinux.bin \
      -c isolinux/boot.cat \
      -no-emul-boot \
      -boot-load-size 4 \
      -boot-info-table \
      -eltorito-alt-boot \
      -e images/efiboot.img \
      -no-emul-boot \
      -R \
      -graft-points \
      -A "$volid" \
      -V "$volid" \
      -publisher "ovirt.org" \
      $TMPDIR
  cond_out isohybrid -u $NEWBOOTISO
  cond_out implantisomd5 --force $NEWBOOTISO
}

main() {
  mkdir $TMPDIR
  cd $TMPDIR

  extract_iso
  add_payload
  modify_bootloader
  create_iso

  rm -rf $TMPDIR || :
}

main
