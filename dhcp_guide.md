# Guide: Enabling DHCP on Prex with VirtIO-Net

This guide provides the technical solutions for enabling networking on Prex via VirtIO. There are two major areas of failure: the Kernel Driver (MD) and the Network Server Port (MI).

---

## 1. Kernel Driver Implementation (`bsp/drv/dev/net/vio_net.c`)

### Legacy VirtQueue Layout
VirtIO Legacy MMIO has strict alignment requirements.
- **Used Ring Alignment:** The "Used Ring" MUST start on a 4096-byte (page) boundary relative to the start of the VirtQueue.
- **Memory Visibility:** Use `__sync_synchronize()` before incrementing `avail->idx` and after reading `used->idx` to ensure the Host (QEMU) sees the updates.

### Descriptor Chaining
VirtIO-Net requires a 10-byte header (`virtio_net_hdr`) before every packet.
- **2-Descriptor Scheme:** For both TX and RX, use a chain of two descriptors.
  - Descriptor 1: Points to the `virtio_net_hdr` struct (size 10).
  - Descriptor 2: Points to the actual packet buffer.
- **RX Filling:** Pre-fill the RX ring with these 2-descriptor chains during initialization, or the device will never trigger an interrupt.

### Stability
- **Avoid `timer_delay()`:** Calling kernel delays in the driver transmit path can cause Data Aborts. Use a simple volatile timeout loop for hardware status polling.

---

## 2. Network Server Port (`usr/server/network/port/`)

### Threading Fix (`sys_arch.c`)
The default `sys_thread_new` often fails because arguments are passed via stack pointers that go out of scope.
- **Trampoline Pattern:** Create a heap-allocated initialization structure protected by a mutex.
- The parent thread should lock the mutex, create the thread, and wait for the child thread to signal (or unlock) once it has copied the arguments to its own local stack.

### Alignment and Padding (`lwipopts.h`)
- **`ETH_PAD_SIZE`:** Set this to `0`.
- VirtIO-Net expects the Ethernet header to start at byte 0 of the packet buffer. If set to 2 (common for 32-bit alignment), the DHCP server will receive corrupted frames and ignore them.

### LwIP Diagnostics
User-space `printf` is often unreliable in the network server.
- Redirect LwIP logs by defining `LWIP_PLATFORM_DIAG` to call a custom variadic function that uses `vsnprintf` and the `sys_log()` syscall.

---

## 3. DHCP Configuration & Performance

To avoid "endless waiting" or timeouts in the Gemini CLI environment, disable background checks that add latency:

1. **Disable ACD/ARP Checks:**
   - `#define LWIP_ACD 0`
   - `#define LWIP_DHCP_DOES_ACD_CHECK 0`
   - `#define DHCP_DOES_ARP_CHECK 0`
2. **Cooperation Mode:**
   - If disabling `LWIP_AUTOIP`, ensure `#define LWIP_DHCP_AUTOIP_COOP 0` is set to avoid compilation errors in `lwip/src/core/init.c`.

---

## 4. Debugging & Tracing

### LwIP Debug Messages
LwIP has a very granular debug system. It is highly recommended to enable it during initial bring-up:
- **Enable in `lwipopts.h`:**
  - `#define LWIP_DEBUG 1`
  - Define specific modules: `DHCP_DEBUG`, `UDP_DEBUG`, `ETHARP_DEBUG`.
- **Bridge to `sys_log`:** Since standard `printf` may fail, use a `vsnprintf` bridge to `sys_log` to see these messages in the Prex boot console.

### QEMU Tracing
If the driver seems to be "sending" but nothing happens on the network, use QEMU's trace feature to see what the host is doing:
- **Trace Command:**
  ```bash
  qemu-system-arm ... -trace "virtio_net_*" -trace "virtqueue_*"
  ```
- This will show if the host is successfully popping descriptors, if it's dropping them due to length errors, or if it's never receiving the "kick" signal.

---

## 5. Verification Workflow

1. **Wait for Driver Initialization:** Add a `sys_msleep(2000)` in `main.c` before `netif_set_up` to ensure the VirtIO device is ready.
2. **Monitor the Binding:** Use a loop in `main.c` to check `!ip4_addr_isany_val(*netif_ip4_addr(&netif))` to confirm when the IP is actually bound.
3. **QEMU Command:**
   ```bash
   qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
   -netdev user,id=net0 -device virtio-net-device,netdev=net0
   ```
   The assigned IP should be `10.0.2.15` (QEMU default).
