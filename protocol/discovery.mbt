///|
/// EtherCAT register addresses used during discovery and configuration.
pub let reg_type : UInt = 0x0000U

///|
pub let reg_revision : UInt = 0x0001U

///|
pub let reg_build : UInt = 0x0002U

///|
/// DL Status register: link status, loop status, signal detection.
pub let reg_dl_status : UInt = 0x0110U

///|
/// DL Control register.
pub let reg_dl_control : UInt = 0x0100U

///|
/// DL Control bit used to enable station alias addressing.
pub let dl_control_alias_enable_bit : Int = 24

///|
/// AL Status register: current ESM state and error indication.
pub let reg_al_status : UInt = 0x0130U

///|
/// AL Status Code register: error code for failed ESM transitions.
pub let reg_al_status_code : UInt = 0x0134U

///|
/// AL Control register: request ESM state transition.
pub let reg_al_control : UInt = 0x0120U

///|
/// Configured Station Address register.
pub let reg_station_address : UInt = 0x0010U

///|
/// Configured Station Alias register.
pub let reg_station_alias : UInt = 0x0012U

///|
/// SII (EEPROM) control/status register.
pub let reg_sii_config : UInt = 0x0500U

///|
/// SII (EEPROM) control/status register.
pub let reg_sii_control : UInt = 0x0502U

///|
/// SII address register (word address for EEPROM read/write).
pub let reg_sii_address : UInt = 0x0504U

///|
/// SII data register (EEPROM data, 4 or 8 bytes depending on operation).
pub let reg_sii_data : UInt = 0x0508U

///|
/// FMMU base register (FMMU0 starts at 0x0600, each FMMU is 16 bytes).
pub let reg_fmmu_base : UInt = 0x0600U

///|
/// FMMU entry size in bytes.
pub let fmmu_entry_size : Int = 16

///|
/// Watchdog Divider register (ESC clock divider for both PDI and SM watchdogs).
pub let reg_watchdog_divider : UInt = 0x0400U

///|
/// PDI Watchdog Time register (master-to-PDI communication timeout).
pub let reg_watchdog_time_pdi : UInt = 0x0410U

///|
/// SM (Process Data) Watchdog Time register (process data arrival timeout).
pub let reg_watchdog_time_pdata : UInt = 0x0420U

///|
/// SM Watchdog Status register (bit 0: 0=expired, 1=active/reloaded).
pub let reg_watchdog_status_pdata : UInt = 0x0440U

///|
/// SM Watchdog Counter register (increments on each watchdog event).
pub let reg_watchdog_counter_pdata : UInt = 0x0442U

///|
/// RX Error Counter base register (0x0300–0x0307, 8 bytes: frame+physical per port).
pub let reg_rx_error_counter : UInt = 0x0300U

///|
/// Forwarded RX Error Counter base register (0x0308–0x030B, 4 bytes: one per port).
pub let reg_fwd_rx_error_counter : UInt = 0x0308U

///|
/// EtherCAT Processing Unit Error Counter register (0x030C).
pub let reg_ecat_pu_error_counter : UInt = 0x030CU

///|
/// PDI Error Counter register (0x030D).
pub let reg_pdi_error_counter : UInt = 0x030DU

///|
/// Lost Link Counter base register (0x0310–0x0313, 4 bytes: one per port).
pub let reg_lost_link_counter : UInt = 0x0310U

///|
/// Sync Manager base register (SM0 starts at 0x0800, each SM is 8 bytes).
pub let reg_sm_base : UInt = 0x0800U

///|
/// Sync Manager entry size in bytes.
pub let sm_entry_size : Int = 8

///|
/// DC receive time register (port 0). Broadcast write latches all port times.
pub let reg_dc_time0 : UInt = 0x0900U

///|
/// DC receive time register (port 1).
pub let reg_dc_time1 : UInt = 0x0904U

///|
/// DC receive time register (port 2).
pub let reg_dc_time2 : UInt = 0x0908U

///|
/// DC receive time register (port 3).
pub let reg_dc_time3 : UInt = 0x090CU

///|
/// DC system time register.
pub let reg_dc_system_time : UInt = 0x0910U

///|
/// DC receive timestamp register used for offset compensation.
pub let reg_dc_sof : UInt = 0x0918U

///|
/// DC system time offset register.
pub let reg_dc_system_offset : UInt = 0x0920U

///|
/// DC propagation delay register.
pub let reg_dc_system_delay : UInt = 0x0928U

///|
/// DC sync window/system difference register.
pub let reg_dc_system_diff : UInt = 0x092CU

///|
/// DC control unit register.
pub let reg_dc_cuc : UInt = 0x0980U

///|
/// DC sync activate register.
pub let reg_dc_sync_act : UInt = 0x0981U

///|
/// DC SYNC0 start time register.
pub let reg_dc_start0 : UInt = 0x0990U

///|
/// DC SYNC0 cycle time register.
pub let reg_dc_cycle0 : UInt = 0x09A0U

///|
/// DC SYNC1 cycle time register.
pub let reg_dc_cycle1 : UInt = 0x09A4U

///|
/// SlaveInfo represents a discovered slave on the network.
pub(all) struct SlaveInfo {
  /// Position on the bus (0 = first slave)
  position : Int
  /// Configured station address (assigned during configuration)
  mut configured_address : UInt
  /// Identity from SII EEPROM
  identity : @hal.SlaveIdentity
  /// Current ESM state
  mut al_status : EsmState
  /// DL status (link/signal)
  dl_status : UInt
  /// SII data read from EEPROM
  mut sii : @mailbox.SiiData?
} derive(Show)

///|
/// Result of a bus scan operation.
pub(all) struct ScanResult {
  /// Number of slaves found
  slave_count : Int
  /// Detailed information per slave
  slaves : Array[SlaveInfo]
} derive(Show)

///|
/// Count the number of slaves on the bus by sending a BRD to register 0x0000.
/// The working counter indicates how many slaves responded.
pub fn[N : @hal.Nic] count_slaves(
  nic : N,
  timeout : @hal.Duration,
) -> Int raise @hal.EcError {
  let pdu = transact_pdu(
    nic,
    EcCommand::BRD,
    broadcast_address(reg_type),
    Bytes::new(1),
    timeout,
  )
  pdu.wkc.reinterpret_as_int()
}

///|
/// Read a register from a slave using auto-increment addressing.
pub fn[N : @hal.Nic] read_register_ap(
  nic : N,
  position : UInt,
  register : UInt,
  length : Int,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let addr = auto_increment_address(position) | (register << 16)
  transact_pdu(nic, EcCommand::APRD, addr, Bytes::new(length), timeout)
}

///|
/// Write a register to a slave using auto-increment addressing.
pub fn[N : @hal.Nic] write_register_ap(
  nic : N,
  position : UInt,
  register : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let addr = auto_increment_address(position) | (register << 16)
  transact_pdu(nic, EcCommand::APWR, addr, data, timeout)
}

///|
/// Read a register from a slave using configured station addressing.
pub fn[N : @hal.Nic] read_register_fp(
  nic : N,
  station : UInt,
  register : UInt,
  length : Int,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let addr = configured_address(station, register)
  transact_pdu(nic, EcCommand::FPRD, addr, Bytes::new(length), timeout)
}

///|
/// Write a register to a slave using configured station addressing.
pub fn[N : @hal.Nic] write_register_fp(
  nic : N,
  station : UInt,
  register : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let addr = configured_address(station, register)
  transact_pdu(nic, EcCommand::FPWR, addr, data, timeout)
}

///|
/// Assign a configured station address to a slave at the given position.
pub fn[N : @hal.Nic] assign_station_address(
  nic : N,
  position : UInt,
  station_address : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let buf = @buffer.new(size_hint=2)
  buf.write_byte((station_address & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(
    ((station_address >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  let pdu = write_register_ap(
    nic,
    position,
    reg_station_address,
    buf.to_bytes(),
    timeout,
  )
  if pdu.wkc == 0U {
    raise @hal.EcError::SendFailed(
      "station address assignment failed for position " +
      position.reinterpret_as_int().to_string(),
    )
  }
}

///|
/// Read configured station address register (0x0010) using auto-increment addressing.
pub fn[N : @hal.Nic] read_station_address_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_ap(nic, position, reg_station_address, 2, timeout)
  if pdu.data.length() < 2 {
    raise @hal.EcError::InvalidPdu("station address response too short")
  }
  pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
}

///|
/// Read station alias register (0x0012) using configured station addressing.
pub fn[N : @hal.Nic] read_station_alias(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_station_alias, 2, timeout)
  if pdu.data.length() < 2 {
    raise @hal.EcError::InvalidPdu("station alias response too short")
  }
  pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
}

///|
/// Set DL Control Bit24 to enable alias addressing for one slave.
pub fn[N : @hal.Nic] enable_alias_addressing(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let dl = read_register_fp(nic, station, reg_dl_control, 4, timeout)
  if dl.data.length() < 4 {
    raise @hal.EcError::InvalidPdu("DL control response too short")
  }
  let current = dl.data[0].to_uint() |
    (dl.data[1].to_uint() << 8) |
    (dl.data[2].to_uint() << 16) |
    (dl.data[3].to_uint() << 24)
  let updated = current | (1U << dl_control_alias_enable_bit)
  let buf = @buffer.new(size_hint=4)
  buf.write_byte((updated & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((updated >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((updated >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((updated >> 24) & 0xFFU).reinterpret_as_int().to_byte())
  let pdu = write_register_fp(
    nic,
    station,
    reg_dl_control,
    buf.to_bytes(),
    timeout,
  )
  if pdu.wkc == 0U {
    raise @hal.EcError::SendFailed(
      "enable alias addressing failed for station " +
      station.reinterpret_as_int().to_string(),
    )
  }
}
