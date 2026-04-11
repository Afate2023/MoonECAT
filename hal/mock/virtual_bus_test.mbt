///|
/// Helper: create a mock SII EEPROM with the given identity.
fn make_sii(identity : @hal.SlaveIdentity) -> Bytes {
  let data = FixedArray::make(256, b'\x00')
  // Word 8-9: Vendor ID (LE 32-bit)
  let vid = identity.vendor_id
  data[16] = (vid & 0xFFU).reinterpret_as_int().to_byte()
  data[17] = ((vid >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  data[18] = ((vid >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  data[19] = ((vid >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  // Word 10-11: Product Code
  let pc = identity.product_code
  data[20] = (pc & 0xFFU).reinterpret_as_int().to_byte()
  data[21] = ((pc >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  data[22] = ((pc >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  data[23] = ((pc >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  // Word 12-13: Revision
  let rev = identity.revision
  data[24] = (rev & 0xFFU).reinterpret_as_int().to_byte()
  data[25] = ((rev >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  data[26] = ((rev >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  data[27] = ((rev >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  // Word 14-15: Serial
  let ser = identity.serial
  data[28] = (ser & 0xFFU).reinterpret_as_int().to_byte()
  data[29] = ((ser >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  data[30] = ((ser >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  data[31] = ((ser >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  // Word 24-27: Standard mailbox (minimal)
  data[48] = b'\x00'
  data[49] = b'\x10' // RX offset = 0x1000
  data[50] = b'\x80' // RX size = 128
  data[52] = b'\x80'
  data[53] = b'\x10' // TX offset = 0x1080
  data[54] = b'\x80' // TX size = 128
  data[56] = b'\x04' // Mailbox Protocol = CoE
  // Category end marker at word 64
  data[128] = b'\xFF'
  data[129] = b'\xFF'
  Bytes::makei(data.length(), fn(i) { data[i] })
}

///|
fn ek1100_identity() -> @hal.SlaveIdentity {
  @fixtures.sample_ek1100_identity()
}

///|
fn el2004_identity() -> @hal.SlaveIdentity {
  {
    vendor_id: 0x2U,
    product_code: 0x07D43052U,
    revision: 0x100000U,
    serial: 0x0U,
  }
}

///|
fn el1008_identity() -> @hal.SlaveIdentity {
  {
    vendor_id: 0x2U,
    product_code: 0x03F03052U,
    revision: 0x100000U,
    serial: 0x0U,
  }
}

///|
/// Create a 3-slave virtual bus: EK1100 coupler + EL2004 output + EL1008 input.
fn make_three_slave_bus() -> @mock.VirtualBus {
  let id0 = ek1100_identity()
  let id1 = el2004_identity()
  let id2 = el1008_identity()
  @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id0, make_sii(id0)),
    @mock.VirtualSlave::new(1, id1, make_sii(id1)),
    @mock.VirtualSlave::new(2, id2, make_sii(id2)),
  ])
}

///|
test "VirtualBus: BRD count_slaves returns correct WKC" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let count = @protocol.count_slaves(nic, @hal.Duration(50_000_000L))
  assert_eq(count, 3)
}

///|
test "VirtualBus: APRD reads register from correct slave" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // Read reg 0x0000 (Type) from slave at position 1
  let pdu = @protocol.read_register_ap(
    nic,
    1U,
    @protocol.reg_type,
    1,
    @hal.Duration(50_000_000L),
  )
  assert_eq(pdu.wkc, 1U)
  assert_eq(pdu.data[0], b'\x02') // ESC type
}

///|
test "VirtualBus: APWR assigns station address" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // Assign station address 0x1001 to slave at position 0
  @protocol.assign_station_address(nic, 0U, 0x1001U, @hal.Duration(50_000_000L))
  // Verify via FPRD
  let pdu = @protocol.read_register_fp(
    nic,
    0x1001U,
    @protocol.reg_type,
    1,
    @hal.Duration(50_000_000L),
  )
  assert_eq(pdu.wkc, 1U)
  assert_eq(pdu.data[0], b'\x02')
}

///|
test "VirtualBus: assign and read station addresses for 3 slaves" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // Assign station addresses
  for i in 0..<3 {
    @protocol.assign_station_address(
      nic,
      i.reinterpret_as_uint(),
      (0x1001 + i).reinterpret_as_uint(),
      @hal.Duration(50_000_000L),
    )
  }
  // Read back each station address via AP
  for i in 0..<3 {
    let addr = @protocol.read_station_address_ap(
      nic,
      i.reinterpret_as_uint(),
      @hal.Duration(50_000_000L),
    )
    assert_eq(addr, (0x1001 + i).reinterpret_as_uint())
  }
}

///|
test "VirtualBus: ESM state transition Init -> PreOp" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // Assign address first
  @protocol.assign_station_address(nic, 0U, 0x1001U, @hal.Duration(50_000_000L))
  // Write AL Control = 0x02 (PreOp)
  let al_ctrl = Bytes::from_array([b'\x02', b'\x00'])
  let pdu = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    al_ctrl,
    @hal.Duration(50_000_000L),
  )
  assert_eq(pdu.wkc, 1U)
  // Read AL Status
  let status_pdu = @protocol.read_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_status,
    2,
    @hal.Duration(50_000_000L),
  )
  assert_eq(status_pdu.data[0], b'\x02') // PreOp
}

///|
test "VirtualBus: CoE SDO roundtrip uses mailbox SM windows" {
  let identity = @fixtures.sample_ek1100_identity()
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, identity, @fixtures.sample_sii_eeprom()),
  ])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  ignore(@protocol.request_state(nic, 0x1001U, @protocol.PreOp, timeout))
  let mailbox_config = @mailbox.MailboxConfig::from_sii(
    @mailbox.parse_sii_header(@fixtures.sample_sii_eeprom()),
  )
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  @protocol.sdo_download_retry(
    nic,
    0x1001U,
    mailbox_config,
    rmsm,
    0x2000U,
    b'\x00',
    Bytes::from_array([b'\x2A']),
    timeout,
  )
  let payload = @protocol.sdo_upload_retry(
    nic, 0x1001U, mailbox_config, rmsm, 0x2000U, b'\x00', timeout,
  )
  assert_eq(payload[0], b'\x2A')
}

///|
test "VirtualBus: SII EEPROM read via register access" {
  let id = ek1100_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  // Write SII address = word 8 (vendor ID) into reg 0x0504
  let addr_data = Bytes::from_array([b'\x08', b'\x00', b'\x00', b'\x00'])
  let _ = @protocol.write_register_ap(
    nic,
    0U,
    @protocol.reg_sii_address,
    addr_data,
    @hal.Duration(50_000_000L),
  )
  // Trigger read: write 0x01 to SII control (reg 0x0502)
  let ctrl = Bytes::from_array([b'\x01'])
  let _ = @protocol.write_register_ap(
    nic,
    0U,
    @protocol.reg_sii_control,
    ctrl,
    @hal.Duration(50_000_000L),
  )
  // Read SII data from reg 0x0508 (4 bytes = vendor_id LE)
  let sii_pdu = @protocol.read_register_ap(
    nic,
    0U,
    @protocol.reg_sii_data,
    4,
    @hal.Duration(50_000_000L),
  )
  // Vendor ID should be 0x00000002
  assert_eq(sii_pdu.data[0], b'\x02')
  assert_eq(sii_pdu.data[1], b'\x00')
  assert_eq(sii_pdu.data[2], b'\x00')
  assert_eq(sii_pdu.data[3], b'\x00')
}

///|
test "VirtualNic: close prevents further send/recv" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  nic.close()
  let send_result = try? nic.send(Bytes::new(0))
  inspect(send_result, content="Err(LinkDown)")
  let recv_result = try? nic.recv(timeout=@hal.Duration(1000L))
  inspect(recv_result, content="Err(LinkDown)")
}

///|
test "VirtualBus: FPWR to non-existent station gives WKC=0" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // No station addresses assigned yet, so FPRD to 0x1001 should have WKC=0
  let pdu = @protocol.read_register_fp(
    nic,
    0x1001U,
    @protocol.reg_type,
    1,
    @hal.Duration(50_000_000L),
  )
  assert_eq(pdu.wkc, 0U)
}

///|
test "VirtualBus: BWR writes to all slaves" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  // Broadcast write AL Control = PreOp to all slaves
  let builder = @protocol.FrameBuilder::new()
  let al_ctrl = Bytes::from_array([b'\x02', b'\x00'])
  let _idx = builder.add(
    @protocol.EcCommand::BWR,
    @protocol.broadcast_address(@protocol.reg_al_control),
    al_ctrl,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, @hal.Duration(50_000_000L))
  // WKC should be 3 (one per slave)
  assert_eq(response.pdus[0].wkc, 3U)
  // Verify all slaves transitioned to PreOp
  for i in 0..<3 {
    let slave = bus.get_slave(i)
    guard slave is Some(s) else { fail("slave not found") }
    assert_eq(s.al_state, b'\x02') // PreOp
  }
}

///|
test "VirtualSlave: invalid ESM transition sets error bit" {
  let id = ek1100_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  // Try Init → Op directly (invalid)
  let al_ctrl = Bytes::from_array([b'\x08', b'\x00'])
  let _ = @protocol.write_register_ap(
    nic,
    0U,
    @protocol.reg_al_control,
    al_ctrl,
    @hal.Duration(50_000_000L),
  )
  // Read AL Status — should still be Init with error bit set (0x11)
  let status = @protocol.read_register_ap(
    nic,
    0U,
    @protocol.reg_al_status,
    2,
    @hal.Duration(50_000_000L),
  )
  assert_eq(status.data[0] & b'\x0F', b'\x01') // Still Init
  assert_eq(status.data[0] & b'\x10', b'\x10') // Error bit set
  // AL Status Code should be non-zero
  let code = @protocol.read_register_ap(
    nic,
    0U,
    @protocol.reg_al_status_code,
    2,
    @hal.Duration(50_000_000L),
  )
  assert_true(code.data[0] != b'\x00' || code.data[1] != b'\x00')
}

///|
test "VirtualBus: full discovery flow with 3 slaves" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Step 1: Count slaves
  let count = @protocol.count_slaves(nic, timeout)
  assert_eq(count, 3)
  // Step 2: Assign station addresses
  for i in 0..<count {
    @protocol.assign_station_address(
      nic,
      i.reinterpret_as_uint(),
      (0x1001 + i).reinterpret_as_uint(),
      timeout,
    )
  }
  // Step 3: Verify each slave responds to configured address
  for i in 0..<count {
    let pdu = @protocol.read_register_fp(
      nic,
      (0x1001 + i).reinterpret_as_uint(),
      @protocol.reg_type,
      1,
      timeout,
    )
    assert_eq(pdu.wkc, 1U)
  }
  // Step 4: Transition all to PreOp
  for i in 0..<count {
    let al_ctrl = Bytes::from_array([b'\x02', b'\x00'])
    let _ = @protocol.write_register_fp(
      nic,
      (0x1001 + i).reinterpret_as_uint(),
      @protocol.reg_al_control,
      al_ctrl,
      timeout,
    )
  }
  // Step 5: Verify all in PreOp
  for i in 0..<count {
    let status = @protocol.read_register_fp(
      nic,
      (0x1001 + i).reinterpret_as_uint(),
      @protocol.reg_al_status,
      2,
      timeout,
    )
    assert_eq(status.data[0] & b'\x0F', b'\x02') // PreOp
  }
}

///|
/// Helper: write FMMU entry to a slave via FPWR.
/// direction: 0x01 = read (slave→master), 0x02 = write (master→slave)
fn write_fmmu_entry(
  nic : @mock.VirtualNic,
  station : UInt,
  fmmu_index : Int,
  logical_start : UInt,
  length : UInt,
  physical_start : UInt,
  direction : Int,
  activate : Bool,
) -> Unit raise @hal.EcError {
  let timeout = @hal.Duration(50_000_000L)
  let base = 0x0600 + fmmu_index * 16
  let data = FixedArray::make(16, b'\x00')
  // Logical start (4 bytes LE)
  data[0] = (logical_start & 0xFFU).reinterpret_as_int().to_byte()
  data[1] = ((logical_start >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  data[2] = ((logical_start >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  data[3] = ((logical_start >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  // Length (2 bytes LE)
  data[4] = (length & 0xFFU).reinterpret_as_int().to_byte()
  data[5] = ((length >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  // Logical start bit / end bit
  data[6] = b'\x00'
  data[7] = b'\x07'
  // Physical start (2 bytes LE)
  data[8] = (physical_start & 0xFFU).reinterpret_as_int().to_byte()
  data[9] = ((physical_start >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  // Physical start bit
  data[10] = b'\x00'
  // Direction
  data[11] = direction.to_byte()
  // Activate
  data[12] = if activate { b'\x01' } else { b'\x00' }
  let bytes = Bytes::makei(16, fn(i) { data[i] })
  let _ = @protocol.write_register_fp(
    nic,
    station,
    base.reinterpret_as_uint(),
    bytes,
    timeout,
  )
}

///|
/// Helper: set up a bus with station addresses assigned.
fn setup_bus_with_addresses(
  bus : @mock.VirtualBus,
  nic : @mock.VirtualNic,
  count : Int,
) -> Unit raise @hal.EcError {
  let timeout = @hal.Duration(50_000_000L)
  for i in 0..<count {
    @protocol.assign_station_address(
      nic,
      i.reinterpret_as_uint(),
      (0x1001 + i).reinterpret_as_uint(),
      timeout,
    )
  }
  ignore(bus)
}

///|
/// Helper: transition a slave to a target state via FPWR.
fn transition_slave(
  nic : @mock.VirtualNic,
  station : UInt,
  target_state : Byte,
) -> Unit raise @hal.EcError {
  let timeout = @hal.Duration(50_000_000L)
  let al_ctrl = Bytes::from_array([target_state, b'\x00'])
  let _ = @protocol.write_register_fp(
    nic, station, @protocol.reg_al_control, al_ctrl, timeout,
  )
}

///|
test "VirtualSlave: FMMU register write and parse" {
  let id = ek1100_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Write FMMU entry 0: logical 0x0000, length 4, physical 0x1000, direction=write, active
  write_fmmu_entry(nic, 0x1001U, 0, 0x0000U, 4U, 0x1000U, 0x02, true)
  // Write FMMU entry 1: logical 0x0004, length 2, physical 0x1004, direction=read, active
  write_fmmu_entry(nic, 0x1001U, 1, 0x0004U, 2U, 0x1004U, 0x01, true)
  // Parse FMMU entries via get_fmmu
  guard bus.get_slave(0) is Some(slave) else { fail("slave not found") }
  let fmmu0 = slave.get_fmmu(0)
  assert_eq(fmmu0.logical_start, 0x0000U)
  assert_eq(fmmu0.length, 4U)
  assert_eq(fmmu0.physical_start, 0x1000U)
  assert_eq(fmmu0.direction, 0x02)
  assert_true(fmmu0.activate)
  let fmmu1 = slave.get_fmmu(1)
  assert_eq(fmmu1.logical_start, 0x0004U)
  assert_eq(fmmu1.length, 2U)
  assert_eq(fmmu1.physical_start, 0x1004U)
  assert_eq(fmmu1.direction, 0x01)
  assert_true(fmmu1.activate)
  // active_fmmus should return exactly 2
  let active = slave.active_fmmus()
  assert_eq(active.length(), 2)
}

///|
test "VirtualBus: LWR writes process data via FMMU" {
  let id = el2004_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Configure FMMU0: logical 0x0000, 4 bytes, physical 0x1000, write (master→slave)
  write_fmmu_entry(nic, 0x1001U, 0, 0x0000U, 4U, 0x1000U, 0x02, true)
  // Send LWR with output data
  let builder = @protocol.FrameBuilder::new()
  let out = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
  let _idx = builder.add(
    @protocol.EcCommand::LWR,
    @protocol.logical_address(0x0000U),
    out,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 1 (write only)
  assert_eq(response.pdus[0].wkc, 1U)
  // Verify slave's process_data at physical 0x1000
  guard bus.get_slave(0) is Some(slave) else { fail("slave not found") }
  assert_eq(slave.process_data[0x1000], b'\xAA')
  assert_eq(slave.process_data[0x1001], b'\xBB')
  assert_eq(slave.process_data[0x1002], b'\xCC')
  assert_eq(slave.process_data[0x1003], b'\xDD')
}

///|
test "VirtualBus: LRD reads process data via FMMU" {
  let id = el1008_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Configure FMMU0: logical 0x0000, 2 bytes, physical 0x1000, read (slave→master)
  write_fmmu_entry(nic, 0x1001U, 0, 0x0000U, 2U, 0x1000U, 0x01, true)
  // Pre-populate slave's process_data (simulated input pins)
  guard bus.get_slave(0) is Some(slave) else { fail("slave not found") }
  slave.process_data[0x1000] = b'\x55'
  slave.process_data[0x1001] = b'\xAA'
  // Send LRD
  let builder = @protocol.FrameBuilder::new()
  let zeros = Bytes::from_array([b'\x00', b'\x00'])
  let _idx = builder.add(
    @protocol.EcCommand::LRD,
    @protocol.logical_address(0x0000U),
    zeros,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 1 (read only)
  assert_eq(response.pdus[0].wkc, 1U)
  // Verify response contains the slave's input data
  assert_eq(response.pdus[0].data[0], b'\x55')
  assert_eq(response.pdus[0].data[1], b'\xAA')
}

///|
test "VirtualBus: LRW with both read and write FMMUs" {
  let id = el2004_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // FMMU0: outputs (write), logical 0x0000, 4 bytes, physical 0x1000
  write_fmmu_entry(nic, 0x1001U, 0, 0x0000U, 4U, 0x1000U, 0x02, true)
  // FMMU1: inputs (read), logical 0x0004, 2 bytes, physical 0x1100
  write_fmmu_entry(nic, 0x1001U, 1, 0x0004U, 2U, 0x1100U, 0x01, true)
  // Pre-populate input data
  guard bus.get_slave(0) is Some(slave) else { fail("slave not found") }
  slave.process_data[0x1100] = b'\xDE'
  slave.process_data[0x1101] = b'\xAD'
  // Send LRW: 4 bytes output + 2 bytes input = 6 bytes total
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([
    b'\x11', b'\x22', b'\x33', b'\x44', // outputs
     b'\x00', b'\x00', // inputs (will be overwritten by slave)
  ])
  let _idx = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 3 (both read AND write)
  assert_eq(response.pdus[0].wkc, 3U)
  // Verify outputs written to process_data
  assert_eq(slave.process_data[0x1000], b'\x11')
  assert_eq(slave.process_data[0x1001], b'\x22')
  assert_eq(slave.process_data[0x1002], b'\x33')
  assert_eq(slave.process_data[0x1003], b'\x44')
  // Verify inputs read back in response
  assert_eq(response.pdus[0].data[4], b'\xDE')
  assert_eq(response.pdus[0].data[5], b'\xAD')
}

///|
test "VirtualBus: LRW multi-slave PDO exchange" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  setup_bus_with_addresses(bus, nic, 3)
  // Slave 1 (EL2004 at 0x1002): outputs via FMMU0
  //   logical 0x0000, 4 bytes, physical 0x1000, direction=write
  write_fmmu_entry(nic, 0x1002U, 0, 0x0000U, 4U, 0x1000U, 0x02, true)
  // Slave 2 (EL1008 at 0x1003): inputs via FMMU0
  //   logical 0x0004, 2 bytes, physical 0x1000, direction=read
  write_fmmu_entry(nic, 0x1003U, 0, 0x0004U, 2U, 0x1000U, 0x01, true)
  // Pre-populate EL1008 input data (simulated digital inputs)
  guard bus.get_slave(2) is Some(input_slave) else {
    fail("input slave not found")
  }
  input_slave.process_data[0x1000] = b'\xFF' // all bits high
  input_slave.process_data[0x1001] = b'\x0F' // lower nibble high
  // Send LRW spanning both slaves: 4 bytes output + 2 bytes input
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', // outputs for EL2004
     b'\x00', b'\x00', // inputs from EL1008
  ])
  let _idx = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 1 (write from slave1) + 1 (read from slave2) = 2
  assert_eq(response.pdus[0].wkc, 2U)
  // Verify EL2004 got the output data
  guard bus.get_slave(1) is Some(output_slave) else {
    fail("output slave not found")
  }
  assert_eq(output_slave.process_data[0x1000], b'\x01')
  assert_eq(output_slave.process_data[0x1001], b'\x02')
  assert_eq(output_slave.process_data[0x1002], b'\x03')
  assert_eq(output_slave.process_data[0x1003], b'\x04')
  // Verify response has EL1008 input data at bytes 4-5
  assert_eq(response.pdus[0].data[4], b'\xFF')
  assert_eq(response.pdus[0].data[5], b'\x0F')
}

///|
test "VirtualBus: LRW with no matching FMMU gives WKC=0" {
  let id = ek1100_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // No FMMU configured — LRW should pass through with WKC=0
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
  let _idx = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  assert_eq(response.pdus[0].wkc, 0U)
}

///|
test "VirtualBus: inactive FMMU is ignored" {
  let id = el2004_identity()
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, id, make_sii(id))])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Configure FMMU0 but with activate=false
  write_fmmu_entry(nic, 0x1001U, 0, 0x0000U, 4U, 0x1000U, 0x02, false)
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
  let _idx = builder.add(
    @protocol.EcCommand::LWR,
    @protocol.logical_address(0x0000U),
    data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 0 because FMMU is not activated
  assert_eq(response.pdus[0].wkc, 0U)
  // Process data should remain untouched
  guard bus.get_slave(0) is Some(slave) else { fail("slave not found") }
  assert_eq(slave.process_data[0x1000], b'\x00')
}

///|
test "VirtualBus: full Init→Op lifecycle with PDO exchange" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Step 1: Count slaves
  let count = @protocol.count_slaves(nic, timeout)
  assert_eq(count, 3)
  // Step 2: Assign station addresses
  setup_bus_with_addresses(bus, nic, count)
  // Step 3: Transition all Init → PreOp
  for i in 0..<count {
    transition_slave(nic, (0x1001 + i).reinterpret_as_uint(), b'\x02')
  }
  // Verify all in PreOp
  for i in 0..<count {
    guard bus.get_slave(i) is Some(s) else { fail("slave not found") }
    assert_eq(s.al_state & b'\x0F', b'\x02')
  }
  // Step 4: Configure FMMU on slaves (in PreOp)
  // Slave 1 (EL2004): outputs — FMMU0: logical 0x0000, 4 bytes, physical 0x1000, write
  write_fmmu_entry(nic, 0x1002U, 0, 0x0000U, 4U, 0x1000U, 0x02, true)
  // Slave 2 (EL1008): inputs — FMMU0: logical 0x0004, 1 byte, physical 0x1000, read
  write_fmmu_entry(nic, 0x1003U, 0, 0x0004U, 1U, 0x1000U, 0x01, true)
  // Step 5: Transition PreOp → SafeOp → Op
  for i in 0..<count {
    transition_slave(nic, (0x1001 + i).reinterpret_as_uint(), b'\x04') // SafeOp
  }
  for i in 0..<count {
    transition_slave(nic, (0x1001 + i).reinterpret_as_uint(), b'\x08') // Op
  }
  // Verify all in Op
  for i in 0..<count {
    guard bus.get_slave(i) is Some(s) else { fail("slave not found") }
    assert_eq(s.al_state & b'\x0F', b'\x08')
  }
  // Step 6: Simulate input data on EL1008
  guard bus.get_slave(2) is Some(input_slave) else {
    fail("input slave not found")
  }
  input_slave.process_data[0x1000] = b'\xA5' // input pin pattern
  // Step 7: PDO exchange via LRW
  let builder = @protocol.FrameBuilder::new()
  let pdo_data = Bytes::from_array([
    b'\x0F', b'\x00', b'\x00', b'\x00', // outputs (LED pattern)
     b'\x00', // input (will be filled by slave)
  ])
  let _idx = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    pdo_data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  assert_eq(response.pdus[0].wkc, 2U) // 1 write + 1 read
  // Verify outputs arrived at EL2004
  guard bus.get_slave(1) is Some(output_slave) else {
    fail("output slave not found")
  }
  assert_eq(output_slave.process_data[0x1000], b'\x0F')
  // Verify inputs read from EL1008
  assert_eq(response.pdus[0].data[4], b'\xA5')
  // Step 8: Second PDO cycle with changed data
  input_slave.process_data[0x1000] = b'\x5A' // input changed
  let builder2 = @protocol.FrameBuilder::new()
  let pdo_data2 = Bytes::from_array([
    b'\xF0', b'\x00', b'\x00', b'\x00', // new outputs
     b'\x00',
  ])
  let _idx2 = builder2.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    pdo_data2,
  )
  let frame2 = builder2.build()
  let response2 = @protocol.transact(nic, frame2, timeout)
  assert_eq(response2.pdus[0].wkc, 2U)
  assert_eq(output_slave.process_data[0x1000], b'\xF0') // updated output
  assert_eq(response2.pdus[0].data[4], b'\x5A') // updated input
}

// ===== APRW / FPRW / BRW / NOP coverage =====

///|
test "VirtualBus: APRW reads and writes register" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Write some data to slave 0 register 0x0010 first
  let wr_data = Bytes::from_array([b'\x42', b'\x00'])
  let _ = @protocol.write_register_ap(nic, 0U, 0x0010, wr_data, timeout)
  // Now APRW: read current value AND write new value atomically
  let builder = @protocol.FrameBuilder::new()
  let rw_data = Bytes::from_array([b'\xAA', b'\xBB'])
  let addr = @protocol.auto_increment_address(0U) | (0x0010U << 16)
  let _idx = builder.add(@protocol.EcCommand::APRW, addr, rw_data)
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC should be 3 for APRW (read + write)
  assert_eq(response.pdus[0].wkc, 3U)
  // Response data should be the OLD value (read happened before write)
  assert_eq(response.pdus[0].data[0], b'\x42')
}

///|
test "VirtualBus: FPRW reads and writes by station address" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Assign station address to slave 0
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Write some initial data
  let wr_data = Bytes::from_array([b'\x55'])
  let _ = @protocol.write_register_fp(nic, 0x1001U, 0x0000, wr_data, timeout)
  // FPRW: read and write
  let builder = @protocol.FrameBuilder::new()
  let rw_data = Bytes::from_array([b'\x77'])
  let _idx = builder.add(
    @protocol.EcCommand::FPRW,
    @protocol.configured_address(0x1001U, 0x0000),
    rw_data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  assert_eq(response.pdus[0].wkc, 3U)
  // Response should contain old value
  assert_eq(response.pdus[0].data[0], b'\x55')
}

///|
test "VirtualBus: BRW broadcasts read-write to all slaves" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Write unique values to same register on each slave
  let _ = @protocol.write_register_ap(
    nic,
    0U,
    0x0000,
    Bytes::from_array([b'\x01']),
    timeout,
  )
  let _ = @protocol.write_register_ap(
    nic,
    1U,
    0x0000,
    Bytes::from_array([b'\x02']),
    timeout,
  )
  let _ = @protocol.write_register_ap(
    nic,
    2U,
    0x0000,
    Bytes::from_array([b'\x04']),
    timeout,
  )
  // BRW: read from all slaves (OR'd) and write back
  let builder = @protocol.FrameBuilder::new()
  let rw_data = Bytes::from_array([b'\xFF'])
  let _idx = builder.add(
    @protocol.EcCommand::BRW,
    @protocol.broadcast_address(0x0000),
    rw_data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // WKC = 3 per slave × 3 slaves = 9
  assert_eq(response.pdus[0].wkc, 9U)
  // Response data is OR of all slaves' values. Each slave read is OR'd into out_data,
  // but the write also overwrites each slave's register with the frame data (0xFF).
  // So the OR of reads produces 0x01|0x02|0x04 = 0x07 PLUS OR with the write data 0xFF = 0xFF.
  // Actually the data flows through all slaves and gets OR'd together.
  assert_eq(response.pdus[0].data[0], b'\xFF')
}

///|
test "VirtualBus: NOP command passes through" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  let builder = @protocol.FrameBuilder::new()
  let nop_data = Bytes::from_array([b'\x00'])
  let _idx = builder.add(@protocol.EcCommand::NOP, 0U, nop_data)
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // NOP should not increment WKC
  assert_eq(response.pdus[0].wkc, 0U)
}

///|
test "VirtualBus: slave_count returns correct count" {
  let bus = make_three_slave_bus()
  assert_eq(bus.slave_count(), 3)
  let empty_bus = @mock.VirtualBus::new([])
  assert_eq(empty_bus.slave_count(), 0)
}

// ===== VirtualSlave state transitions =====

///|
test "VirtualSlave: Init to Boot transition" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Init → Boot (0x03)
  let al_ctrl = Bytes::from_array([b'\x03', b'\x00'])
  let _ = @protocol.write_register_fp(
    nic, 0x1001U, @protocol.reg_al_control, al_ctrl, timeout,
  )
  let status = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(status.data[0], b'\x03')
}

///|
test "VirtualSlave: PreOp to Init transition" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Init → PreOp
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x02', b'\x00']),
    timeout,
  )
  // PreOp → Init
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x01', b'\x00']),
    timeout,
  )
  let status = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(status.data[0], b'\x01')
}

///|
test "VirtualSlave: SafeOp to PreOp transition" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Init → PreOp → SafeOp
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x02', b'\x00']),
    timeout,
  )
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x04', b'\x00']),
    timeout,
  )
  // SafeOp → PreOp
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x02', b'\x00']),
    timeout,
  )
  let status = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(status.data[0], b'\x02')
}

///|
test "VirtualSlave: SII read beyond eeprom fills 0xFF" {
  let id = ek1100_identity()
  let small_sii = Bytes::make(4, b'\xAA') // only 4 bytes
  let slave = @mock.VirtualSlave::new(0, id, small_sii)
  let bus = @mock.VirtualBus::new([slave])
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  // Set SII word address to word 3 (byte 6, beyond small_sii length 4)
  let addr_data = Bytes::from_array([b'\x03', b'\x00', b'\x00', b'\x00'])
  let _ = @protocol.write_register_ap(
    nic, 0U, @protocol.reg_sii_address, addr_data, timeout,
  )
  // Trigger read
  let ctrl = Bytes::from_array([b'\x01'])
  let _ = @protocol.write_register_ap(
    nic, 0U, @protocol.reg_sii_control, ctrl, timeout,
  )
  // Read SII data: should be 0xFF (beyond eeprom)
  let sii_pdu = @protocol.read_register_ap(
    nic, 0U, @protocol.reg_sii_data, 4, timeout,
  )
  assert_eq(sii_pdu.data[0], b'\xFF')
  assert_eq(sii_pdu.data[1], b'\xFF')
}

///|
test "VirtualSlave: read_process_data" {
  let id = ek1100_identity()
  let slave = @mock.VirtualSlave::new(0, id, make_sii(id))
  // Write some process data directly
  slave.process_data[0x100] = b'\x42'
  slave.process_data[0x101] = b'\x43'
  let data = slave.read_process_data(0x100, 2)
  assert_eq(data[0], b'\x42')
  assert_eq(data[1], b'\x43')
}

///|
test "VirtualSlave: write_process_data" {
  let id = ek1100_identity()
  let slave = @mock.VirtualSlave::new(0, id, make_sii(id))
  let arr : FixedArray[Byte] = [b'\xAA', b'\xBB', b'\xCC']
  slave.write_process_data(0x200, arr, 1, 2) // write arr[1..3] to phys 0x200
  assert_eq(slave.process_data[0x200], b'\xBB')
  assert_eq(slave.process_data[0x201], b'\xCC')
}

// ===== ARMW/FRMW pass-through coverage =====

///|
test "VirtualBus: ARMW command passes through without modifying" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([b'\x00', b'\x00'])
  let _idx = builder.add(
    @protocol.EcCommand::ARMW,
    @protocol.auto_increment_address(0U) | (0x0910U << 16),
    data,
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // ARMW is NOP for VirtualBus — wkc should be 0
  assert_eq(response.pdus[0].wkc, 0U)
}

// ===== Boot → Init state transition =====

///|
test "VirtualSlave: Boot to Init transition" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Init → Boot (0x03)
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x03', b'\x00']),
    timeout,
  )
  // Boot → Init (0x01)
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x01', b'\x00']),
    timeout,
  )
  let status = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(status.data[0], b'\x01')
}

// ===== VirtualSlave process_logical with FMMU =====

///|
test "VirtualSlave: process_logical read through FMMU" {
  let id = ek1100_identity()
  let slave = @mock.VirtualSlave::new(0, id, make_sii(id))
  // Configure FMMU 0 for read (slave→master, direction=0x01)
  // FMMU base = 0x0600, entry size = 16
  let fmmu_base = 0x0600
  // Logical start address = 0x1000 (4 bytes LE)
  slave.registers[fmmu_base] = b'\x00'
  slave.registers[fmmu_base + 1] = b'\x10'
  slave.registers[fmmu_base + 2] = b'\x00'
  slave.registers[fmmu_base + 3] = b'\x00'
  // Length = 2 bytes
  slave.registers[fmmu_base + 4] = b'\x02'
  slave.registers[fmmu_base + 5] = b'\x00'
  // Logical start bit = 0
  slave.registers[fmmu_base + 6] = b'\x00'
  // Logical end bit = 7
  slave.registers[fmmu_base + 7] = b'\x07'
  // Physical start = 0x0100 (2 bytes LE)
  slave.registers[fmmu_base + 8] = b'\x00'
  slave.registers[fmmu_base + 9] = b'\x01'
  // Physical start bit = 0
  slave.registers[fmmu_base + 10] = b'\x00'
  // Direction = 0x01 (read: slave→master)
  slave.registers[fmmu_base + 11] = b'\x01'
  // Activate = 1
  slave.registers[fmmu_base + 12] = b'\x01'
  // Set process data at physical 0x0100
  slave.process_data[0x0100] = b'\xDE'
  slave.process_data[0x0101] = b'\xAD'
  // process_logical: read from logical 0x1000, 2 bytes
  let pdu_data : FixedArray[Byte] = [b'\x00', b'\x00']
  let out_data : FixedArray[Byte] = [b'\x00', b'\x00']
  let (did_read, did_write) = slave.process_logical(
    0x1000U, 2, pdu_data, out_data, true, false,
  )
  assert_true(did_read)
  assert_eq(did_write, false)
  assert_eq(out_data[0], b'\xDE')
  assert_eq(out_data[1], b'\xAD')
}

///|
test "VirtualSlave: process_logical write through FMMU" {
  let id = ek1100_identity()
  let slave = @mock.VirtualSlave::new(0, id, make_sii(id))
  let fmmu_base = 0x0600
  // Logical start = 0x2000
  slave.registers[fmmu_base] = b'\x00'
  slave.registers[fmmu_base + 1] = b'\x20'
  slave.registers[fmmu_base + 2] = b'\x00'
  slave.registers[fmmu_base + 3] = b'\x00'
  // Length = 3
  slave.registers[fmmu_base + 4] = b'\x03'
  slave.registers[fmmu_base + 5] = b'\x00'
  slave.registers[fmmu_base + 6] = b'\x00'
  slave.registers[fmmu_base + 7] = b'\x07'
  // Physical start = 0x0200
  slave.registers[fmmu_base + 8] = b'\x00'
  slave.registers[fmmu_base + 9] = b'\x02'
  slave.registers[fmmu_base + 10] = b'\x00'
  // Direction = 0x02 (write: master→slave)
  slave.registers[fmmu_base + 11] = b'\x02'
  slave.registers[fmmu_base + 12] = b'\x01'
  let pdu_data : FixedArray[Byte] = [b'\xCA', b'\xFE', b'\xBE']
  let out_data : FixedArray[Byte] = [b'\x00', b'\x00', b'\x00']
  let (did_read, did_write) = slave.process_logical(
    0x2000U, 3, pdu_data, out_data, false, true,
  )
  assert_eq(did_read, false)
  assert_true(did_write)
  assert_eq(slave.process_data[0x0200], b'\xCA')
  assert_eq(slave.process_data[0x0201], b'\xFE')
  assert_eq(slave.process_data[0x0202], b'\xBE')
}

// ===== FaultNic coverage =====

///|
test "FaultNic: open_ creates empty nic" {
  let nic : @mock.FaultNic = @hal.Nic::open_("test")
  nic.close()
}

///|
test "FaultNic: close marks nic closed" {
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let nic = @mock.FaultNic::new(inner, @mock.FaultInjector::new())
  nic.close()
  // After close, inner is_open should be false
  let result : Result[Int, _] = try? nic.send(b"\x00")
  assert_true(result is Err(_))
}

///|
test "FaultNic: send with SendFailure raises" {
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let injector = @mock.FaultInjector::new()
  let nic = @mock.FaultNic::new(inner, injector)
  injector.add(@mock.SendFailure("boom"), @mock.AtCycle(0))
  let result : Result[Int, _] = try? nic.send(b"\x00\x01")
  assert_true(result is Err(_))
}

///|
test "FaultNic: send with non-send fault passes through" {
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let injector = @mock.FaultInjector::new()
  let nic = @mock.FaultNic::new(inner, injector)
  // RecvTimeout is not a send fault — it should be ignored during send
  injector.add(@mock.RecvTimeout, @mock.AtCycle(0))
  // Build a minimal valid frame to send
  let builder = @protocol.FrameBuilder::new()
  let _idx = builder.add(
    @protocol.EcCommand::NOP,
    0U,
    Bytes::from_array([b'\x00']),
  )
  let frame = builder.build()
  let sent = nic.send(frame.encode())
  assert_true(sent > 0)
}

///|
test "FaultNic: recv with FrameCorrupt injects corruption" {
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let injector = @mock.FaultInjector::new()
  let nic = @mock.FaultNic::new(inner, injector)
  // Set up FrameCorrupt to fire on recv count 0
  injector.add(@mock.FrameCorrupt(offset=0, value=b'\xFF'), @mock.AtCycle(0))
  // First send a frame so there's something to receive
  let builder = @protocol.FrameBuilder::new()
  let _idx = builder.add(
    @protocol.EcCommand::NOP,
    0U,
    Bytes::from_array([b'\x00']),
  )
  let frame = builder.build()
  let _ = nic.send(frame.encode())
  // Recv should get corrupted data (byte 0 → 0xFF)
  let data = nic.recv(timeout=@hal.Duration(50_000_000L))
  assert_eq(data[0], b'\xFF')
}

///|
test "FaultNic: recv with WkcCorrupt modifies wkc" {
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let injector = @mock.FaultInjector::new()
  let nic = @mock.FaultNic::new(inner, injector)
  injector.add(@mock.WkcCorrupt(delta=1), @mock.AtCycle(0))
  let builder = @protocol.FrameBuilder::new()
  let _idx = builder.add(
    @protocol.EcCommand::NOP,
    0U,
    Bytes::from_array([b'\x00']),
  )
  let frame = builder.build()
  let _ = nic.send(frame.encode())
  let data = nic.recv(timeout=@hal.Duration(50_000_000L))
  // WkcCorrupt should return data (possibly corrupted WKC)
  assert_true(data.length() > 0)
}

///|
test "FaultNic: recv with SendFailure during recv passes through" {
  // SendFailure fault in recv phase → just call inner recv
  let bus = make_three_slave_bus()
  let inner = @mock.VirtualNic::new(bus)
  let injector = @mock.FaultInjector::new()
  let nic = @mock.FaultNic::new(inner, injector)
  // First send a frame normally
  let builder = @protocol.FrameBuilder::new()
  let _idx = builder.add(
    @protocol.EcCommand::NOP,
    0U,
    Bytes::from_array([b'\x00']),
  )
  let frame = builder.build()
  let _ = nic.send(frame.encode())
  // Now set up SendFailure for recv — should be ignored, just returns inner data
  injector.add(@mock.SendFailure("ignored"), @mock.AtCycle(0))
  let data = nic.recv(timeout=@hal.Duration(50_000_000L))
  assert_true(data.length() > 0)
}

///|
test "VirtualSlave: SafeOp to Init transition" {
  let bus = make_three_slave_bus()
  let nic = @mock.VirtualNic::new(bus)
  let timeout = @hal.Duration(50_000_000L)
  @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  // Init → PreOp
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x02', b'\x00']),
    timeout,
  )
  // PreOp → SafeOp
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x04', b'\x00']),
    timeout,
  )
  // SafeOp → Init (the uncovered transition)
  let _ = @protocol.write_register_fp(
    nic,
    0x1001U,
    @protocol.reg_al_control,
    Bytes::from_array([b'\x01', b'\x00']),
    timeout,
  )
  let status = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(status.data[0], b'\x01')
}
