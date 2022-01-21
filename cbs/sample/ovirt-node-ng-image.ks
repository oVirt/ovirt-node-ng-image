#
# THIS KICKSTART IS ONLY USED FOR BUILDING OVIRT NODE
#
#              NOT FOR INSTALLATION
#

url --mirrorlist=http://mirrorlist.centos.org/?repo=BaseOS&release=8-stream&arch=$basearch
repo --name=appstream --mirrorlist=http://mirrorlist.centos.org/?repo=AppStream&release=8-stream&arch=$basearch
repo --name=powertools --mirrorlist=http://mirrorlist.centos.org/?repo=PowerTools&release=8-stream&arch=$basearch
repo --name=extras --mirrorlist=http://mirrorlist.centos.org/?repo=Extras&release=8-stream&arch=$basearch


lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC
network --noipv6
auth --enableshadow --passalgo=sha512
selinux --enforcing
rootpw --lock
firstboot --reconfig
clearpart --all --initlabel
bootloader --timeout=1
part / --size=5120 --fstype=ext4 --fsoptions=discard
poweroff


%packages --excludedocs --ignoremissing --excludeWeakdeps
dracut-config-generic
-dracut-config-rescue
dracut-live
python36
centos-stream-repos
scap-security-guide
%end


%post --erroronfail
set -x
mkdir -p /etc/yum.repos.d

# For build issues debugging purpose, looking for known repositories
dnf repolist

# Adding upstream oVirt vdsm
# 1. Install oVirt release file with repositories
yum install -y --nogpgcheck http://resources.ovirt.org/pub/yum-repo/ovirt-release-master-tested.rpm
yum config-manager --set-enabled powertools || true


yum -y --nogpgcheck --nodocs --setopt=install_weak_deps=False distro-sync



# Adds the latest cockpit bits
yum install --nogpgcheck --nodocs --setopt=install_weak_deps=False -y cockpit

# 1.a Ensure that we use baseurls to ensure we always pick
#     the mist recent content (right after repo composes/releases)
sed -i "/^mirrorlist/ d ; s/^#baseurl/baseurl/" $(find /etc/yum.repos.d/*ovirt*.repo -type f ! -name "*dep*")

# Try to work around failure to sync repo
dnf clean all
rm -rf /var/cache/dnf

# 2. Install oVirt Node release and placeholder
# (exclude ovirt-node-ng-image-update to prevent the obsoletes logic)
yum install -y --nogpgcheck --nodocs --setopt=install_weak_deps=False \
  --exclude ovirt-node-ng-image-update \
  ovirt-release-host-node \
  ovirt-node-ng-image-update-placeholder

# let VDSM configure itself, but don't have the file owned by any package, so we pass 'rpm -V'
touch /var/lib/ngn-vdsm-need-configure

# Postprocess (always the last step)
imgbase --debug --experimental \
  image-build \
  --postprocess \
  --set-nvr=$(rpm -q --qf "ovirt-node-ng-%{version}-0.$(date +%Y%m%d).0" ovirt-release-host-node)
%end
%post
ver=$(rpm -qf /etc/yum.repos.d/ovirt* | grep ^ovirt-release | sort -u | sed 's/ovirt-release//' | cut -b1)
[[ $ver = "-" ]] && ver="m"
ln -sf /usr/share/xml/scap/ssg/content/{ssg-rhel8,ssg-onn$ver}-ds.xml

%end
