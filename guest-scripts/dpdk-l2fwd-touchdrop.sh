ip link set dev eth0 down
modprobe uio_pci_generic
dpdk-devbind.py -b uio_pci_generic 00:02.0
echo 2048 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
dpdk-l2fwd -l 0-1 -n 4 --main-lcore 0 -s 0x2 -- -p 0x0001 --touch --drop