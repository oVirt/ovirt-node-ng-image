# Guides:
# https://fedoraproject.org/wiki/Anaconda/ProductImage#Product_image
# https://git.fedorahosted.org/cgit/fedora-logos.git/tree/anaconda

set -e

isfinal() { [[ ! "$1" =~ (-pre|-snapshot|master) ]] ; }

BRANCH=${BRANCH:-master}
GUESSED_ISFINAL=$(isfinal ${BRANCH} && echo True || echo False )

ISFINAL=${ISFINAL:-${GUESSED_ISFINAL}}
VERSION=${BRANCH#ovirt-}

DST=$(realpath ${1:-$PWD/product.img})
DATADIR=$(dirname $0)/../data
SRCDIR=$DATADIR/pixmaps
PRDDIR=product/
PIXMAPDIR=$PRDDIR/usr/share/anaconda/pixmaps/
KSDIR=$PRDDIR/usr/share/anaconda/

mkdir -p "$PRDDIR" "$PIXMAPDIR" "$KSDIR"
cp "$SRCDIR"/sidebar-logo.png "$PIXMAPDIR/"

if [[ -n $SHIP_OVIRT_INSTALLCLASS ]]; then
    inst_class_dir=$PRDDIR/run/install/product/pyanaconda/installclasses
    mkdir -p $inst_class_dir
    cp $DATADIR/ovirt.py $inst_class_dir
fi

# FIXME we could deliver the ks in the product.img
# but for simplicity we use the inst.ks approach
# Branding: product.img
# ks: kargs
#cp "$KSFILE" "$KSDIR"/interactive-defaults.ks

cat > "$PRDDIR/.buildstamp" <<EOF
[Main]
Product=oVirt Node Next
Version=${VERSION}
BugURL=https://bugzilla.redhat.com
IsFinal=${ISFINAL}
UUID=$(date +%Y%m%d).x86_64
[Compose]
Lorax=21.30-1
EOF

pushd $PRDDIR
  find . | cpio -c -o --quiet | pigz -9c > $DST
popd

rm -rf $PRDDIR

#unpigz < $DST | cpio -t
