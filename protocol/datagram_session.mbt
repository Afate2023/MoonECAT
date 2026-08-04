///|
/// Supplies EtherCAT Datagram Index values for protocol transactions.
///
/// This trait is intentionally closed: raw NIC implementations transport
/// bytes only. Callers obtain an implementation by wrapping a NIC in
/// `DatagramSession`.
pub trait DatagramIndexSource {
  fn next_datagram_index(Self) -> Byte
}

///|
/// Protocol transaction session for one serial EtherCAT master flow.
///
/// The session owns the Datagram Index cursor while the wrapped NIC remains a
/// byte transport. A cursor value is consumed before a frame is sent, so a
/// failed transaction never reuses its Index.
pub struct DatagramSession[N] {
  inner : N
  mut next_index : Int
  fixed_index : Byte?
}

///|
/// Start an incrementing Datagram Index session.
pub fn[N] DatagramSession::new(
  inner : N,
  start_index? : Byte = b'\x00',
) -> DatagramSession[N] {
  { inner, next_index: start_index.to_int(), fixed_index: None }
}

///|
/// Wrap a NIC for replaying legacy traces whose Datagram Index was always 0.
/// New live and recorded sessions should use `DatagramSession::new`.
pub fn[N] DatagramSession::legacy(inner : N) -> DatagramSession[N] {
  { inner, next_index: 0, fixed_index: Some(b'\x00') }
}

///|
/// Return the Index that will be allocated to the next PDU.
pub fn[N] DatagramSession::next_index(self : DatagramSession[N]) -> Byte {
  match self.fixed_index {
    Some(index) => index
    None => (self.next_index & 0xFF).to_byte()
  }
}

///|
pub impl[N] DatagramIndexSource for DatagramSession[N] with fn next_datagram_index(
  self,
) {
  match self.fixed_index {
    Some(index) => index
    None => {
      let index = (self.next_index & 0xFF).to_byte()
      self.next_index = (self.next_index + 1) & 0xFF
      index
    }
  }
}

///|
/// DatagramSession delegates raw I/O unchanged to its wrapped NIC.
pub impl[N : @hal.Nic] @hal.Nic for DatagramSession[N] with fn open_(name) {
  DatagramSession::new(N::open_(name))
}

///|
pub impl[N : @hal.Nic] @hal.Nic for DatagramSession[N] with fn send(self, data) {
  N::send(self.inner, data)
}

///|
pub impl[N : @hal.Nic] @hal.Nic for DatagramSession[N] with fn recv(
  self,
  timeout~,
) {
  N::recv(self.inner, timeout~)
}

///|
pub impl[N : @hal.Nic] @hal.Nic for DatagramSession[N] with fn close(self) {
  N::close(self.inner)
}
