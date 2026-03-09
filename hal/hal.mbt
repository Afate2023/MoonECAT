///|
/// Timestamp represents a monotonic point in time, in nanoseconds.
pub(all) struct Timestamp(Int64) derive(Eq, Show, Compare)

///|
/// Duration represents a span of time, in nanoseconds.
pub(all) struct Duration(Int64) derive(Eq, Show, Compare)

///|
/// NicHandle is an opaque network interface handle provided by the HAL backend.
pub(all) struct NicHandle {
  id : Int
} derive(Eq, Show)

///|
/// The maximum size of an EtherCAT frame payload (Ethernet MTU).
pub let max_frame_size : Int = 1518

///|
/// The EtherCAT EtherType constant (0x88A4).
pub let ethercat_ethertype : Int = 0x88A4

///|
/// Nic defines the minimal network interface contract.
/// All platform backends must implement this trait.
pub(open) trait Nic {
  /// Open a network interface by name.
  open_(String) -> Self raise EcError
  /// Send a raw Ethernet frame. Returns bytes sent.
  send(Self, Bytes) -> Int raise EcError
  /// Receive a raw Ethernet frame.
  /// Returns the received frame bytes.
  recv(Self, timeout~ : Duration) -> Bytes raise EcError
  /// Close the network interface and release resources.
  close(Self) -> Unit
}

///|
/// Clock provides monotonic timing primitives.
pub(open) trait Clock {
  /// Return the current monotonic timestamp in nanoseconds.
  now(Self) -> Timestamp
  /// Sleep for the specified duration.
  sleep(Self, Duration) -> Unit
}

///|
/// FileAccess provides basic file I/O for configuration and diagnostics.
pub(open) trait FileAccess {
  /// Read the entire contents of a file as Bytes.
  read_file(Self, String) -> Bytes raise EcError
  /// Write Bytes to a file, creating or overwriting it.
  write_file(Self, String, Bytes) -> Unit raise EcError
}
