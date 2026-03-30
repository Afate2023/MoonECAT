///|
/// VirtualNic is a network interface backed by a VirtualBus.
/// Sent frames are processed through the virtual slave chain and the
/// response is queued for the next recv call.
/// This enables full EtherCAT discovery and configuration testing
/// with multiple virtual slaves without real hardware.
pub struct VirtualNic {
  bus : VirtualBus
  rx_buffer : Array[Bytes]
  mut is_open : Bool
}

///|
pub fn VirtualNic::new(bus : VirtualBus) -> VirtualNic {
  { bus, rx_buffer: [], is_open: true }
}

///|
pub impl @hal.Nic for VirtualNic with open_(name) {
  ignore(name)
  VirtualNic::new(VirtualBus::new([]))
}

///|
pub impl @hal.Nic for VirtualNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  // Process the frame through the virtual bus
  let response = self.bus.process_frame(data)
  self.rx_buffer.push(response)
  data.length()
}

///|
pub impl @hal.Nic for VirtualNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  if self.rx_buffer.is_empty() {
    raise @hal.EcError::RecvTimeout
  }
  self.rx_buffer.remove(0)
}

///|
pub impl @hal.Nic for VirtualNic with close(self) {
  self.is_open = false
}

///|
/// Convenience: create a VirtualNic with a pre-built bus of slaves.
pub fn VirtualNic::with_slaves(slaves : Array[VirtualSlave]) -> VirtualNic {
  VirtualNic::new(VirtualBus::new(slaves))
}
