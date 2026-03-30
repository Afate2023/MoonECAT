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
