API_SOCKET="/tmp/firecracker.socket"
LOGFILE="./firecracker.log"

# Check KVM access
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "KVM OK" || echo "KVM FAIL"

# Create log file
touch $LOGFILE

# Set log file
echo "Set log file"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"log_path\": \"${LOGFILE}\",
        \"level\": \"Debug\",
        \"show_level\": true,
        \"show_log_origin\": true
    }" \
    "http://localhost/logger"

KERNEL="./vmlinux-5.10.217"
KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off"

ARCH=$(uname -m)

if [ ${ARCH} = "aarch64" ]; then
    KERNEL_BOOT_ARGS="keep_bootcon ${KERNEL_BOOT_ARGS}"
fi

# Set boot source
echo "Set boot source"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"kernel_image_path\": \"${KERNEL}\",
        \"boot_args\": \"${KERNEL_BOOT_ARGS}\"
    }" \
    "http://localhost/boot-source"

ROOTFS="./ubuntu-22.04.ext4"

# Set rootfs
echo "Set rootfs"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"drive_id\": \"rootfs\",
        \"path_on_host\": \"${ROOTFS}\",
        \"is_root_device\": true,
        \"is_read_only\": false
    }" \
    "http://localhost/drives/rootfs"

# The IP address of a guest is derived from its MAC address with
# `fcnet-setup.sh`, this has been pre-configured in the guest rootfs. It is
# important that `TAP_IP` and `FC_MAC` match this.
FC_MAC="06:00:AC:10:00:02"
TAP_DEV="tap0"

# Set network interface
echo "Set network interface"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"iface_id\": \"net1\",
        \"guest_mac\": \"$FC_MAC\",
        \"host_dev_name\": \"$TAP_DEV\"
    }" \
    "http://localhost/network-interfaces/net1"

# Set mem size
echo "Set memory size"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"mem_size_mib\": 2048,
	\"vcpu_count\": 4
    }" \
    "http://localhost/machine-config"

# API requests are handled asynchronously, it is important the configuration is
# set, before `InstanceStart`.
sleep 0.015s

# Start microVM
echo "Start microVM"
curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"action_type\": \"InstanceStart\"
    }" \
    "http://localhost/actions"

# API requests are handled asynchronously, it is important the microVM has been
# started before we attempt to SSH into it.
sleep 2s

echo "Setup internet and DNS"
# Setup internet access in the guest
ssh -i ./ubuntu-22.04.id_rsa root@172.16.0.2  "ip route add default via 172.16.0.1 dev eth0"

# Setup DNS resolution in the guest
ssh -i ./ubuntu-22.04.id_rsa root@172.16.0.2  "echo 'nameserver 185.12.64.1' > /etc/resolv.conf"

# SSH into the microVM
echo "Connect to microVM"
ssh -i ./ubuntu-22.04.id_rsa root@172.16.0.2

# Use `root` for both the login and password.
# Run `reboot` to exit.