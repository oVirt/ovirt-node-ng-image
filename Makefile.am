# Copyright (C) 2016 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.

SQUASHFSFILENAME = @IMAGENAME@.squashfs.img
RPMMANIFESTNAME = @IMAGENAME@.manifest-rpm
RPMUNSIGNEDNAME = @IMAGENAME@.unsigned-rpms

EXTRA_DIST = \
	data/centos.ks \
	data/fedora.ks

DISTCLEANFILES = \
	aclocal.m4 \
	configure \
	install-sh \
	livemedia.log \
	Makefile.in \
	missing \
	*.log

debug-ks: data/@IMAGENAME@.ks
	sed -i 's/^poweroff/#poweroff/' $<

# Building a "LiveOS" vm for debugging ks issues
debug-squashfs: LMCOPTS=--vnc vnc=127.0.0.1:5
debug-squashfs: | debug-ks $(SQUASHFSFILENAME)
	@echo debug-squashfs $(SQUASHFSFILENAME)

squashfs: $(SQUASHFSFILENAME) $(RPMMANIFESTNAME) $(RPMUNSIGNEDNAME)
	@echo squashfs: $(SQUASHFSFILENAME)
	@echo squashfs rpm-manifest: $(RPMMANIFESTNAME)
	@echo squashfs rpm-unsigned: $(RPMUNSIGNEDNAME)

product.img:
	bash scripts/create-product-img.sh $@

offline-installation-iso: product.img
	PRODUCTIMG=$(PWD)/product.img \
			   BOOTISO=$(BOOTISO) \
			   SQUASHFS=$(SQUASHFSFILENAME) \
			   VERSION=$(PACKAGE_VERSION) \
			   DERVICEBOOTISOSCRIPT=scripts/derive-boot-iso.sh \
			   bash scripts/create-nightly-boot-iso.sh

@BOOTISO@:
	wget --timeout=120 $(BOOTISOURL)

LMC ?= livemedia-creator
%.squashfs.img: data/%.ks @BOOTISO@
	$(LMC) $(LMCOPTS) --make-pxe-live --iso @BOOTISO@ --ks $< --resultdir build --tmp @TMPDIR@
	mv -v build/*squash* "$@"

# Short TMPDIR otherwise we run into trouble with guestfish < 1.33.27-1.fc24
# # -x -v to be more verbose
IN_ROOTFS=LIBGUESTFS_TMPDIR=/var/tmp guestfish --ro -a $(SQUASHFSFILENAME) run : mount /dev/sda / : mount-loop /LiveOS/rootfs.img / : sh
$(RPMMANIFESTNAME): $(SQUASHFSFILENAME)
	$(IN_ROOTFS) "rpm -qa|sort" > $@

$(RPMUNSIGNEDNAME): $(SQUASHFSFILENAME)
	$(IN_ROOTFS) "rpm -qa --qf '%{name}-%{version}-%{release}.%{arch} (%{SIGPGP:pgpsig})\n'" | grep -v "Key ID" > $@

ovirt-node-ng.spec: PLACEHOLDER_RPM=ovirt-node-ng-image-update-placeholder
ovirt-node-ng.spec: PLACEHOLDER_RPM_VERSION=$(shell $(IN_ROOTFS) "rpm -q --qf %{version} $(PLACEHOLDER_RPM)")
ovirt-node-ng.spec: PLACEHOLDER_RPM_RELEASE=$(shell $(IN_ROOTFS) "rpm -q --qf %{release} $(PLACEHOLDER_RPM)")
ovirt-node-ng.spec: ovirt-node-ng.spec.in
	sed \
		-e "s/\@IMAGENAME\@/$(IMAGENAME)/" \
		-e "s/\@PACKAGE_VERSION\@/$(PACKAGE_VERSION)/" \
		-e "s/\@PACKAGE_NAME\@/$(PACKAGE_NAME)/" \
		-e "s/\@PACKAGE_RPM_VERSION\@/$(PACKAGE_RPM_VERSION)/" \
		-e "s/\@PACKAGE_RPM_RELEASE\@/$(PACKAGE_RPM_RELEASE)/" \
		-e "s/\@PLACEHOLDER_RPM_VERSION\@/$(PLACEHOLDER_RPM_VERSION)/" \
		-e "s/\@PLACEHOLDER_RPM_RELEASE\@/$(PLACEHOLDER_RPM_RELEASE)/" \
		$< > $@

RPMBUILD = rpmbuild
TMPREPOS = tmp.repos

rpm srpm: ovirt-node-ng.spec $(RPMMANIFESTNAME) $(RPMUNSIGNEDNAME) $(SQUASHFSFILENAME) product.img
	rm -fr "$(TMPREPOS)"
	mkdir -p $(TMPREPOS)/{SPECS,RPMS,SRPMS,SOURCES}
	make dist
	$(RPMBUILD) \
		--define="_topdir `pwd`/$(TMPREPOS)" \
		--define "_sourcedir `pwd`" \
		-ba ovirt-node-ng.spec
	@echo
	@echo "srpm and rpm(s) available at '$(TMPREPOS)'"
	@echo

clean-local:
	-rm -vrf $(SQUASHFSFILENAME) $(RPMMANIFESTNAME) $(RPMUNSIGNEDNAME) $(INSTALLEDIMAGEFILE) ovirt-node-ng.spec build
