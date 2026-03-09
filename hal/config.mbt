///|
/// MasterConfig holds global master parameters.
pub(all) struct MasterConfig {
  /// Network interface name (e.g., "eth0", "\\Device\\NPF_{...}").
  interface_name : String
  /// Cycle period in nanoseconds for periodic PDO exchange.
  cycle_period_ns : Int64
  /// Timeout for a single EtherCAT transaction, in nanoseconds.
  recv_timeout_ns : Int64
  /// Maximum number of retries for failed transactions.
  max_retries : Int
  /// Enable DC synchronization.
  dc_enabled : Bool
} derive(Eq, Show)

///|
pub fn MasterConfig::default() -> MasterConfig {
  {
    interface_name: "eth0",
    cycle_period_ns: 1_000_000L, // 1 ms
    recv_timeout_ns: 50_000_000L, // 50 ms
    max_retries: 3,
    dc_enabled: false,
  }
}

///|
/// SlaveIdentity holds the vendor/product identity read from SII.
pub(all) struct SlaveIdentity {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
} derive(Eq, Show)

///|
/// SlaveConfig holds per-slave configuration parameters.
pub(all) struct SlaveConfig {
  /// Position in the EtherCAT ring (0-based).
  position : UInt
  /// Expected identity (from ESI/config file).
  expected_identity : SlaveIdentity?
  /// Configured station address.
  configured_address : UInt
} derive(Eq, Show)
