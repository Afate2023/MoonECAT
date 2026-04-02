///|
/// MCU HAL adapter stubs for bare-metal EtherCAT targets.
///
/// Targets: RZ/N2L (Renesas), HPM6E00 (HPMicro), STM32H7 + LAN9252.
/// These stubs define the platform-specific types and provide skeleton
/// implementations. Actual MCU register access is via C FFI bindings
/// that will be linked per-platform.
///
/// Architecture:
///   MCU DMA Ring ←→ McuNic (Nic/ZeroCopyNic) ←→ MoonECAT Runtime
///   MCU Timer    ←→ McuClock (Clock)          ←→ TimebaseSync

///|
/// MCU platform identifier.
pub(all) enum McuPlatform {
  /// Renesas RZ/N2L — dual-core Cortex-R52 + EtherCAT IP
  RzN2L
  /// HPMicro HPM6E00 — RISC-V + triple gigabit Ethernet
  Hpm6E00
  /// STM32H7 + LAN9252 SPI bridge
  Stm32H7Lan9252
  /// Generic placeholder for bring-up
  Generic
} derive(Eq, Show)

///|
/// MCU NIC configuration.
pub(all) struct McuNicConfig {
  /// Platform identifier.
  platform : McuPlatform
  /// Base address of the EtherCAT MAC register block.
  base_addr : UInt
  /// IRQ number for RX complete.
  rx_irq : Int
  /// IRQ number for TX complete.
  tx_irq : Int
  /// DMA ring buffer entry count (must be power of 2).
  ring_size : Int
} derive(Show)

///|
pub fn McuNicConfig::default(platform : McuPlatform) -> McuNicConfig {
  let (base, rx, tx) = match platform {
    RzN2L => (0x4005_0000U, 32, 33)
    Hpm6E00 => (0xF305_0000U, 48, 49)
    Stm32H7Lan9252 => (0x4002_0000U, 61, 62)
    Generic => (0x0000_0000U, 0, 0)
  }
  { platform, base_addr: base, rx_irq: rx, tx_irq: tx, ring_size: 64 }
}

///|
/// McuNic — bare-metal network interface adapter.
///
/// The actual send/recv operations delegate to extern "c" stubs that
/// interact with DMA descriptors and hardware registers.
pub(all) struct McuNic {
  config : McuNicConfig
  mut opened : Bool
  mut tx_count : Int64
  mut rx_count : Int64
} derive(Show)

///|
pub fn McuNic::new(config : McuNicConfig) -> McuNic {
  { config, opened: false, tx_count: 0L, rx_count: 0L }
}

///|
/// Nic trait implementation for McuNic.
/// In actual deployment, each method calls extern "c" functions.
/// This stub version raises NotSupported to indicate unlinked FFI.
pub impl @hal.Nic for McuNic with open_(name) {
  let _ = name
  raise @hal.EcError::NotSupported(
    "McuNic::open_ requires platform-specific C FFI linkage",
  )
}

///|
pub impl @hal.Nic for McuNic with send(self, data) {
  let _ = (self, data)
  raise @hal.EcError::NotSupported("McuNic::send requires C FFI linkage")
}

///|
pub impl @hal.Nic for McuNic with recv(self, timeout~) {
  let _ = (self, timeout)
  raise @hal.EcError::NotSupported("McuNic::recv requires C FFI linkage")
}

///|
pub impl @hal.Nic for McuNic with close(self) {
  self.opened = false
}

///|
/// McuClock — bare-metal timer adapter.
///
/// Uses the platform's high-resolution timer (e.g., Cortex-R52 PMU
/// cycle counter, RISC-V mtime) for nanosecond timestamps.
pub(all) struct McuClock {
  platform : McuPlatform
  /// Timer frequency in Hz (e.g., 400_000_000 for 400 MHz).
  timer_freq_hz : Int64
} derive(Show)

///|
pub fn McuClock::new(platform : McuPlatform, timer_freq_hz : Int64) -> McuClock {
  { platform, timer_freq_hz }
}

///|
pub impl @hal.Clock for McuClock with now(self) {
  let _ = self
  // Stub: actual implementation reads hardware timer via FFI
  @hal.Timestamp(0L)
}

///|
pub impl @hal.Clock for McuClock with sleep(self, dur) {
  let _ = (self, dur)
  // Stub: actual implementation busy-waits or uses timer interrupt
}

///|
/// McuZeroCopyNic — zero-allocation NIC backed by DMA descriptor ring.
///
/// The FramePool slots map directly to DMA descriptors in .DMA_SRAM.
/// No heap allocation in the PDO hot path.
pub(all) struct McuZeroCopyNic {
  config : McuNicConfig
  mut opened : Bool
} derive(Show)

///|
pub fn McuZeroCopyNic::new(config : McuNicConfig) -> McuZeroCopyNic {
  { config, opened: false }
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with open_(name, pool) {
  let _ = (name, pool)
  raise @hal.EcError::NotSupported(
    "McuZeroCopyNic::open_ requires platform-specific C FFI linkage",
  )
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with acquire_tx(self) {
  let _ = self
  raise @hal.EcError::NotSupported("McuZeroCopyNic requires C FFI linkage")
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with tx_buffer(self, frame_ref) {
  let _ = (self, frame_ref)
  FixedArray::make(0, b'\x00')
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with submit(
  self,
  frame_ref,
  length~,
) {
  let _ = (self, frame_ref, length)
  raise @hal.EcError::NotSupported("McuZeroCopyNic requires C FFI linkage")
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with recv(self, timeout~) {
  let _ = (self, timeout)
  raise @hal.EcError::NotSupported("McuZeroCopyNic requires C FFI linkage")
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with rx_buffer(self, frame_ref) {
  let _ = (self, frame_ref)
  FixedArray::make(0, b'\x00')
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with rx_length(self, frame_ref) {
  let _ = (self, frame_ref)
  0
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with release(self, frame_ref) {
  let _ = (self, frame_ref)
}

///|
pub impl @hal.ZeroCopyNic for McuZeroCopyNic with close(self) {
  self.opened = false
}
