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
SSGDIR=$PRDDIR/usr/share/xml/scap/ssg/content

echo "Building version ${VERSION} from branch ${BRANCH}"

mkdir -p "$PRDDIR" "$PIXMAPDIR" "$KSDIR"
cp "$SRCDIR"/sidebar-logo.png "$PIXMAPDIR/"

if [[ -n $SHIP_OVIRT_CONF ]]; then
    product_conf_dir=$PRDDIR/etc/anaconda/product.d
    mkdir -p $product_conf_dir
    if [ "$(rpm --eval %{almalinux})" == "9" ] ; then
      cp $DATADIR/ovirt.alma.el9.conf $product_conf_dir/ovirt.conf
    elif [ "$(rpm --eval %{rocky})" == "9" ] ; then
      cp $DATADIR/ovirt.rocky.el9.conf $product_conf_dir/ovirt.conf
    else
      cp $DATADIR/ovirt$(rpm --eval "%dist").conf $product_conf_dir/ovirt.conf
    fi
fi

if [[ -n $SSG_TARGET_XML ]]; then
    mkdir -p $SSGDIR
    ln -sf $SSG_TARGET_XML $SSGDIR/ssg-onn${VERSION:0:1}-ds.xml
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
