# Prex Network Stack

This document describes the architecture and implementation of the network stack in Prex, covering the layers from hardware drivers to the POSIX socket API.

## Overview

The Prex network stack is built using a microkernel-oriented approach. Networking services are provided by a dedicated **Network Server** task, which communicates with user applications via IPC and with hardware via device drivers.

### Layered Architecture

1.  **POSIX Socket API**: C library wrappers (`socket`, `connect`, `send`, etc.) that translate calls into IPC messages.
2.  **IPC Bridge**: The messaging protocol defined in `include/ipc/network.h`.
3.  **Network Server**: A user-mode task (`usr/server/network/`) running the **LwIP** (Lightweight IP) stack.
4.  **MI (Machine Independent) Layer**: LwIP core and the `sys_arch` porting layer.
5.  **MD (Machine Dependent) Layer**: Hardware-specific drivers (e.g., VirtIO Net).

---

## Driver Level (MD/MI)

### Machine Dependent (MD)
Hardware drivers are implemented as kernel-mode or driver-module components. The primary driver for QEMU virtualization is the **VirtIO Net** driver (`bsp/drv/dev/net/vio_net.c`).

*   **Interrupt Handling**: Drivers use **IST (Interrupt Service Threads)** to handle packet reception. This prevents long-running ISRs and ensures system stability.
*   **Buffer Management**: Uses a ring buffer mechanism (VirtQueue) to exchange packets with the hardware/hypervisor.
*   **Zero-Padding**: For VirtIO, a 10-byte header is prepended to each packet.

### Machine Independent (MI) Interface
Drivers expose a standard Prex device interface (`read`, `write`, `ioctl`). The Network Server opens these devices (e.g., `/dev/net0`) and uses them as the physical layer for LwIP.

---

## Network Server

The Network Server is the heart of the networking system.

*   **LwIP Integration**: It utilizes LwIP for TCP/IPv4/UDP/ICMP/DHCP/DNS protocols.
*   **Thread Model**:
    *   **Main Thread**: Handles IPC requests from other tasks.
    *   **TCP/IP Thread**: The core LwIP processing thread.
    *   **Input Thread**: Polls the network device for incoming packets and feeds them to LwIP.
    *   **Monitor Thread**: Periodically checks for DHCP lease status and DNS configuration updates.
*   **Synchronization**: Implemented via a `sys_arch` port using Prex semaphores and mutexes.

---

## IPC Protocol

Communication with the Network Server happens through the `/serv/network` object.

### Message Structure
Defined in `include/ipc/network.h`:
```c
struct net_msg {
    struct msg_header hdr;
    int socket;     // Target socket descriptor
    int flags;      // Socket flags (e.g., MSG_DONTWAIT)
    size_t len;     // Data length
    struct sockaddr addr; // Remote address for connect/sendto
    char data[2048]; // Payload buffer
};
```

### Operation Codes
*   `NET_SOCKET`: Create a new socket.
*   `NET_BIND`: Bind socket to a local address.
*   `NET_CONNECT`: Connect to a remote host.
*   `NET_SEND` / `NET_RECV`: Stream data transfer.
*   `NET_SENDTO` / `NET_RECVFROM`: Datagram data transfer.
*   `NET_SHUTDOWN`: Partial or full socket closure.
*   `NET_CLOSE`: Release socket resources.
*   `NET_RESOLVE`: DNS hostname resolution.

---

## POSIX API Implementation

The POSIX socket API is implemented in `usr/lib/posix/file/socket.c`. It provides a seamless bridge for standard C applications.

### Supported Functions
*   `socket()`, `bind()`, `listen()`, `accept()`
*   `connect()`, `send()`, `recv()`, `sendto()`, `recvfrom()`
*   `shutdown()`, `close()`
*   `gethostbyname()` (Translates to `NET_RESOLVE`)
*   `htonl()`, `htons()`, `ntohl()`, `ntohs()` (In `usr/lib/libc/gen/endian.c`)

### DNS Support
The `gethostbyname()` implementation sends a `NET_RESOLVE` message to the Network Server. The server uses LwIP's DNS resolver to look up the FQDN and returns the IP address.

---

## Utilities

*   **ifconfig**: Displays network interface status (IP, Netmask, GW, MAC).
*   **ping**: Verifies connectivity using ICMP Echo requests. Supports FQDNs.
*   **nc (netcat)**: Versatile networking tool for TCP/UDP data transfer. Enhanced with LF->CRLF conversion and `shutdown` support for HTTP scripting.
*   **weather.sh**: A sample shell script that fetches real-time weather data from `wttr.in` using `nc`.

---

## Reference Implementation
This networking stack is developed based on the following reference implementations:

- **Network Server & IPC**: Based on the architecture and implementation of [Phoenix-RTOS](https://www.phoenix-rtos.com/).
- **Networking Tools (ping, nc)**: Based on tools ported from [LiteBSD](https://github.com/dankmanning/litebsd).

Maintained by Champ Yen (champ.yen@gmail.com).

---

## Configuration

*   **DHCP**: Automatically enabled at boot if `CONFIG_NET` is defined.
*   **fstab**: Network-related files (like weather scripts) can be stored on a VFAT partition and mounted at `/usr` via `conf/etc/fstab`.
*   **rc**: The boot script (`conf/etc/rc`) initializes the search PATH and can trigger network services.
