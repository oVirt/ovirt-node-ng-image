url --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$arch
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f$releasever&arch=$arch
# Fixes bz#1594856
updates https://bugzilla.redhat.com/attachment.cgi?id=1454675


%packages --excludedocs --ignoremissing --excludeWeakdeps
dracut-live
dracut-config-generic
-dracut-config-rescue
grub2-efi-x64
%end

%post
rm -vf /etc/libvirt/qemu/networks/autostart/default.xml
%end
