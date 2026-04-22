### Goal
To make Prex's DHCP work to get IP address successfully

### Related source
Please add debugging message to make the target done.
1. net machine dependent and independent driver are implemented with reference
to nuttx's virtio-net driver:
  * ./bsp/drv/deb/net/net.c
  * ./bsp/drv/include/net.h
  * ./bsp/drv/deb/net/vio_net.c
  * nuttx virtio-net driver: ../nuttx/drivers/virtio/virtio-net.*
2. lwip-based network server ported from Phoenix-RTOS:
  * ./usr/server/network
  * original source: ../phoenix-rtos-project/phoenix-rtos-lwip/
3. ifconfig
  * ./usr/sbin/ifconfig/
4. other reference
  * ../LiteBSD/

### Target
Please make Prex be able to get ip successfully from QEMU's NAT DHCP server with
virtio-net device during boot
* don't modify the source of lwip, since it is a git submodule

Don't stop if you don't make it.
