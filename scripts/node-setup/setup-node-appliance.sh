#!/bin/bash

set -eo pipefail

####### defs #######

NODE_SETUP_PATH=$(dirname $(realpath $0))
MAX_VM_MEM="${MAX_VM_MEM:-2048}"
MAX_VM_CPUS="${MAX_VM_CPUS:-2}"
ISO_INSTALL_TIMEOUT="${ISO_INSTALL_TIMEOUT:--1}"
WORKDIR="${WORKDIR:-${HOME/root/var/lib}/ovirt-node}"
LOGDIR="${LOGDIR:-${WORKDIR}}"
APPLIANCE_DOMAIN="appliance.net"
LIBVIRT_NETWORK="ovirt-node-net"
LIBVIRT_IP_OCTET="155"

CENTOS_MIRROR="${CENTOS_MIRROR:-http://mirror.centos.org}"
CENTOS_INSTALLATION_SOURCE="${CENTOS_MIRROR}/centos/8-stream/BaseOS/x86_64/os/"
RELEASE_RPM=

####################


die() { echo "ERROR: $@" >&2 && exit 1; }
dbg() { echo "DEBUG: $@" >&2; }

download_rpm_and_extract() {
    local url=$1
    local name=$2
    local search=$3

    local tmpdir=$(mktemp -d)
    echo "$name: Downloading rpm from $url"
    curl -LsSo "$tmpdir/$name.rpm" $url || die "Download failed"
    echo "$name: Extracting rpm..."
    rpm2cpio "$tmpdir/$name.rpm" | (cd $tmpdir; cpio --quiet -diu) || \
        die "Failed extracting rpm"
    find $tmpdir -name "*.$search" -exec mv -f {} "$WORKDIR/$name.$search" \;
    rm -rf $tmpdir
}

do_ssh() {
    local ssh_key=$1
    local ip=$2
    local cmd=$3

    for i in {1..10}
    do
        dbg "Executing [$cmd] on [$ip]"
        ssh -q -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $ssh_key root@$ip "$cmd" && break ||:
        sleep 5
    done
}

get_vm_ip() {
    local name=$1

    local brdev=$(virsh net-info ${LIBVIRT_NETWORK} | grep ^Bridge | awk '{print $2}')

    for i in {1..30}
    do
        local mac=$(virsh -q domiflist "$name" | awk '{print $5}' | grep [0-9]) ||:

        dbg "Searching ips for mac [$mac] on bridge device [$brdev]"
        local arp_ips=$(ip n show dev "$brdev" | grep "$mac" | awk '{print $1}') ||:
        local v_ips=$(virsh -q domifaddr "$name" | awk '{sub(/\/.*/,""); print $4}') ||:

        dbg "Found arp_ips=$arp_ips, v_ips=$v_ips"
        local ips=$(echo -e "$arp_ips\n$v_ips" | sort -ur)

        for ip in $ips
        do
            dbg "Trying to ping $ip"
            ping -c5 -i 3 $ip >&2 && {
                dbg "Using ip $ip"
                echo $ip
                return
            }
        done
        sleep 10
    done

    # Fallback - just use the ip in case ping is blocked for some reason, this
    # is the previous behavior
    [[ -n "$ips" ]] && echo $ips || die "get_vm_ip failed"
}

prepare_network() {
    set +e
    hint=$(virsh -q net-info ${LIBVIRT_NETWORK} | grep 'Active' | awk '{print $2}')
    set -e
    if [[ $hint == 'yes' ]]; then
        echo "network ${LIBVIRT_NETWORK} already active"
        return
    elif [ -z "$hint" ]; then
        echo "defining network ${LIBVIRT_NETWORK}"
        tmpf=$(mktemp)
        cat << EOF >> ${tmpf}
<network>
  <name>${LIBVIRT_NETWORK}</name>
  <bridge name="virbr${LIBVIRT_IP_OCTET}" />
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address="192.168.${LIBVIRT_IP_OCTET}.1" netmask="255.255.255.0">
    <dhcp>
      <range start='192.168.${LIBVIRT_IP_OCTET}.2' end='192.168.${LIBVIRT_IP_OCTET}.254'/>
    </dhcp>
  </ip>
</network>
EOF
        virsh -q net-define ${tmpf} > /dev/null
    fi
    virsh net-start ${LIBVIRT_NETWORK}
    rm -f ${tmpf}
}

run_network_check() {
    local name=$1
    local vmpasswd=$2

    local expect_script="./net-check.exp"

cat << EOF > $expect_script
#!/usr/bin/expect

set timeout 300

spawn virsh console $name --force

expect "Escape character is"
send "\r"

expect "login: " { send "root\r" }
expect "Password: " { send "$vmpasswd\r" }
expect "~]# " { send "imgbase check\r" }
expect "~]# " { send "ip a\r" }
expect "~]# " { send "ip r\r" }
expect "~]# " { send "journalctl -a --no-pager\r" }
expect "~]# " { send "exit\r" }
EOF
    chmod +x $expect_script
    $expect_script > network-check.log 2>&1 ||:
}

append_ssg_profile() {
    local ksfile=$1

    if [[ -n $SSG_PROFILE ]]; then
        cat << EOF >> $ksfile
%addon org_fedora_oscap
content-type = scap-security-guide
profile = $SSG_PROFILE
%end
EOF
    fi
}

run_nodectl_check() {
    local name=$1
    local ssh_key=$2
    local ip=$3
    local timeout=120
    local check=""

    while [[ -z "$check" ]]
    do
        [[ $timeout -eq 0 ]] && break
        check=$(do_ssh "$ssh_key" "$ip" "imgbase check")
        sleep 10
        timeout=$((timeout - 10))
    done

    echo "$check" > $name-nodectl-check.log
}

prepare_appliance() {
    local name=$1
    local url=$2

    download_rpm_and_extract "$url" $name "ova"

    local diskimg=$(tar tf $WORKDIR/$name.ova |  grep -Po "images.*(?=.meta)")
    local tmpdir=$(mktemp -d)

    tar xf $WORKDIR/$name.ova -C $tmpdir || die "Failed extracting ova"
    mv $tmpdir/$diskimg $WORKDIR/$name.qcow2
    find $tmpdir -name "*.ovf" -exec mv -f {} "$WORKDIR/$name.ovf" \;
    rm -rf $tmpdir $WORKDIR/$name.ova
}

make_cidata_iso() {
    local ssh_key=$1
    local vmpasswd=$2

    local pub_ssh=$(cat $ssh_key.pub)
    local tmpdir=$(mktemp -d)

    echo "instance-id: rhevm-engine" > $tmpdir/meta-data
    cat << EOF > $tmpdir/user-data
#cloud-config
chpasswd:
  list: |
    root:$vmpasswd
  expire: False
EOF
    genisoimage -quiet -output $WORKDIR/ci.iso -volid cidata \
                        -joliet -rock $tmpdir/* || die "genisoimage failed"

    rm -rf $tmpdir
}

setup_appliance() {
    local name=$1
    local url=$2
    local ssh_key=$3
    local vmpasswd=$4

    # creating $WORKDIR/{$name.qcow2,ci.iso} - XXX: validate.....
    prepare_appliance $name $url
    make_cidata_iso $ssh_key $vmpasswd

    local diskimg="$WORKDIR/$name.qcow2"
    local ovf="$WORKDIR/$name.ovf"
    local cidata="$WORKDIR/ci.iso"
    local logfile="$LOGDIR/virt-install-$name.log"

    local ovf_mem=$(grep -Po "(?<=<rasd:Caption>)[^<]+(?= MB of memory)" $ovf)
    local ovf_cpus=$(grep -Po "(?<=<rasd:Caption>)[^<]+(?= virtual CPU)" $ovf)

    echo "$name: OVF reports $ovf_mem RAM and $ovf_cpus CPUs"

    local v_mem=$(( ovf_mem > MAX_VM_MEM ? MAX_VM_MEM : ovf_mem ))
    local v_cpus=$(( ovf_cpus > MAX_VM_CPUS ? MAX_VM_CPUS : ovf_cpus ))

    echo "$name: Setting up appliance from disk $diskimg"

    virt-customize -q -a $diskimg --ssh-inject root:file:$ssh_key.pub || \
                    die "Failed injecting public ssh key"

    echo "$name: Using $v_mem RAM and $v_cpus CPUs"

    virt-install -d \
        --name $name \
        --ram $v_mem \
        --vcpus $v_cpus \
        --disk path=$diskimg,bus=ide \
        --network network:${LIBVIRT_NETWORK},model=virtio  \
        --vnc \
        --noreboot \
        --boot hd \
        --cdrom $cidata \
        --os-type linux \
        --rng /dev/urandom \
        --noautoconsole > $logfile 2>&1 || die "virt-install failed"

    local ip=$(get_vm_ip $name)
    local fqdn=$name.$APPLIANCE_DOMAIN

    echo "$name: Setting up repos and hostname ($fqdn)"

    do_ssh "$ssh_key" "$ip" "hostnamectl set-hostname $fqdn; echo \"$ip $fqdn $name\" >> /etc/hosts"
    [[ -n "$RELEASE_RPM" ]] && do_ssh "$ssh_key" "$ip" "rpm -U --quiet $RELEASE_RPM"
    do_ssh "$ssh_key" "$ip" "systemctl -q enable sshd; systemctl -q mask --now cloud-init"

    do_ssh "$ssh_key" "$ip" "echo SSO_ALTERNATE_ENGINE_FQDNS=\"$ip\" > /etc/ovirt-engine/engine.conf.d/99-alt-fqdn.conf"
    do_ssh "$ssh_key" "$ip" "sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
    do_ssh "$ssh_key" "$ip" "systemctl restart sshd"

    echo "$name: appliance is available at $ip"

    rm $cidata
}

virt_install_location() {
    local iso=$1
    local vver=$(virt-install --version | tr -d .)

    if [[ $vver -ge 210 ]]; then
       echo "$iso,kernel=isolinux/vmlinuz,initrd=isolinux/initrd.img"
    else
       echo "$iso"
    fi
}

setup_node_iso() {
    local name=$1
    local node_iso_path=$2
    local ssh_key=$3
    local vmpasswd=$4
    local shutdown=$5

    local ksfile="$WORKDIR/node-iso-install.ks"
    local diskimg="$WORKDIR/$name.qcow2"
    local logfile="$LOGDIR/node-iso-virt-install-$name.log"
    local ssh=$(cat $ssh_key.pub)

    local tmpdir=$(mktemp -d)
    mount -o ro $node_iso_path $tmpdir
    cat << EOF > $ksfile
timezone --utc Etc/UTC
lang en_US.UTF-8
keyboard us
auth --enableshadow --passalgo=sha512
selinux --enforcing
network --bootproto=dhcp --hostname=$name
firstboot --reconfig
sshkey --username=root "$ssh"
rootpw --plaintext $vmpasswd
poweroff
clearpart --all --initlabel --disklabel=gpt
autopart --type=thinp
bootloader --timeout=1
EOF

    append_ssg_profile "$ksfile"

    sed 's/^imgbase/imgbase --debug/' $tmpdir/*ks* >> $ksfile
    umount $tmpdir && rmdir $tmpdir

    echo "$name: Installing ISO to VM..."

    virt-install -d \
        --name "$name" \
        --boot menu=off \
        --memory $MAX_VM_MEM \
        --vcpus $MAX_VM_CPUS \
        --cpu host \
        --location "$(virt_install_location $node_iso_path)" \
        --extra-args "inst.ks=file:///node-iso-install.ks inst.sshd=1 console=ttyS0" \
        --initrd-inject "$ksfile" \
        --graphics none \
        --noreboot \
        --check all=off \
        --wait $ISO_INSTALL_TIMEOUT \
        --os-variant rhel8.0 \
        --noautoconsole \
        --rng /dev/urandom \
        --network network:${LIBVIRT_NETWORK},model=virtio  \
        --disk path=$diskimg,size=65 > "$logfile" 2>&1 || {
            local ip=$(get_vm_ip $name)
            echo "$name: node is available at $ip"
            die "virt-install timed out"
        }

    if [[ -z $shutdown ]]
    then
        echo -e "$name: Finished installing, starting VM..."

        virsh -q start $name || die "virsh start failed"
        local ip=$(get_vm_ip $name)

        run_nodectl_check $name $ssh_key $ip
        run_network_check $name $vmpasswd

        echo "$name: node is available at $ip"
    else
        echo "$name: Finished installing, VM is down"
    fi

    rm $ksfile
}

setup_node() {
    local name=$1
    local url=$2
    local ssh_key=$3
    local vmpasswd=$4
    local shutdown=$5

    download_rpm_and_extract "$url" "$name" "squashfs.img"

    local squashfs="$WORKDIR/$name.squashfs.img"
    local diskimg="$WORKDIR/$name.qcow2"
    local ksfile="$WORKDIR/node-install.ks"
    local logfile="$LOGDIR/virt-install-$name.log"
    local kickstart_in="$NODE_SETUP_PATH/node-install.ks.in"
    local ssh=$(cat $ssh_key.pub)

    sed -e "s#@HOSTNAME@#$name#" \
        -e "s#@SSHKEY@#$ssh#" \
        -e "s#@VMPASSWD@#$vmpasswd#" \
        $kickstart_in > $ksfile

    append_ssg_profile "$ksfile"

    qemu-img create -q -f qcow2 $diskimg 65G || die "Failed creating disk"

    echo "$name: Installing $squashfs to $diskimg..."
    echo "$name: Install log file is $logfile"

    virt-install -d \
        --name "$name" \
        --boot menu=off \
        --memory $MAX_VM_MEM \
        --vcpus $MAX_VM_CPUS \
        --cpu host \
        --location "${CENTOS_INSTALLATION_SOURCE}" \
        --extra-args "inst.ks=file:///node-install.ks console=ttyS0 inst.sshd=1" \
        --initrd-inject $ksfile \
        --check disk_size=off,path_in_use=off \
        --graphics none \
        --noreboot \
        --wait -1 \
        --os-variant rhel8.0 \
        --noautoconsole \
        --rng /dev/urandom \
        --network network:${LIBVIRT_NETWORK},model=virtio  \
        --disk path=$diskimg,bus=virtio,cache=unsafe,discard=unmap,format=qcow2 \
        --disk path=$squashfs,readonly=on,device=disk,bus=virtio,serial=livesrc \
        > $logfile 2>&1 || die "virt-install failed"


    if [[ -z $shutdown ]]
    then
        echo "$name: Finished installing, starting VM..."

        virsh -q start $name || die "virsh start failed"
        local ip=$(get_vm_ip $name)

        run_nodectl_check $name $ssh_key $ip
        run_network_check $name $vmpasswd

        echo "$name: node is available at $ip"
    else
        echo "$name: Finished installing, VM is down"
    fi

    rm $ksfile $squashfs
}

main() {
    local node_url=""
    local appliance_url=""
    local node_iso_path=""
    local vmpasswd=""
    local machine=""
    local shutdown="" # Supported for nodes only

    while getopts "n:a:i:p:m:s" OPTION
    do
        case $OPTION in
            n)
                node_url=$OPTARG
                ;;
            a)
                appliance_url=$OPTARG
                ;;
            i)
                node_iso_path=$OPTARG
                ;;
            p)
                vmpasswd=$OPTARG
                ;;
            m)
                machine=$OPTARG
                ;;
            s)
                shutdown=1
                ;;
        esac
    done


    [[ -z "$node_url" && -z "$appliance_url" && -z "$node_iso_path" ]] && {
        echo "Usage: $0 -n <node_rpm_url> -a <appliance_rpm_url> -i <node_iso>"
        exit 1
    }

    [[ $EUID -ne 0 ]] && {
        echo "Must run as root"
        exit 1
    }

    [[ -z "$vmpasswd" ]] && {
        while [[ -z "$vmpasswd" ]]
        do
            echo -n "Set VM password: "
            read -s vmpasswd
            echo ""
        done

        echo -n "Reenter password: "
        read -s vmpasswd2
        echo ""

        [[ "$vmpasswd" != "$vmpasswd2" ]] && {
            echo "Passwords do not match"
            exit 1
        }
    }

    [[ ! -d "$WORKDIR" ]] && mkdir -p "$WORKDIR"

    echo "Using WORKDIR: $WORKDIR"

    prepare_network

    [[ ! -z "$node_url" ]] && {
        node=${machine:-node-$RANDOM}
        ssh_key="$WORKDIR/sshkey-$node"
        [[ -n $machine && -f $ssh_key ]] && rm -f $ssh_key{,.pub}
        ssh-keygen -q -f $ssh_key -N ''
        setup_node "$node" "$node_url" "$ssh_key" "$vmpasswd" "$shutdown"
    }

    [[ ! -z "$node_iso_path" ]] && {
        node=${machine:-node-iso-$RANDOM}
        ssh_key="$WORKDIR/sshkey-$node"
        [[ -n $machine && -f $ssh_key ]] && rm -f $ssh_key{,.pub}
        ssh-keygen -q -f $ssh_key -N ''
        setup_node_iso "$node" "$node_iso_path" "$ssh_key" "$vmpasswd" "$shutdown"
    }

    [[ ! -z "$appliance_url" ]] && {
        appliance=${machine:-engine-$RANDOM}
        ssh_key="$WORKDIR/sshkey-$appliance"
        [[ -n $machine && -f $ssh_key ]] && rm -f $ssh_key{,.pub}
        ssh-keygen -q -f $ssh_key -N ''
        setup_appliance "$appliance" "$appliance_url" "$ssh_key" "$vmpasswd"
        echo "For smoketesting, remember to run engine-setup on $appliance"
    } || :
}

main "$@"
