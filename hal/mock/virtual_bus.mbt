///|
/// VirtualBus models an EtherCAT daisy-chain of virtual slaves.
/// It processes EtherCAT frames by routing each PDU through the slave chain
/// according to ETG.1000.4 addressing rules and returning the modified frame.
pub struct VirtualBus {
  slaves : Array[VirtualSlave]
} derive(Show)

///|
pub fn VirtualBus::new(slaves : Array[VirtualSlave]) -> VirtualBus {
  { slaves, }
}

///|
/// Process a raw Ethernet frame through the virtual bus.
/// Decodes the frame, routes each PDU, updates WKC, and re-encodes.
pub fn VirtualBus::process_frame(
  self : VirtualBus,
  raw : Bytes,
) -> Bytes raise @hal.EcError {
  let frame = @protocol.EcFrame::decode(raw)
  let response_pdus : Array[@protocol.Pdu] = []
  for pdu in frame.pdus {
    response_pdus.push(self.process_pdu(pdu))
  }
  let response_frame : @protocol.EcFrame = {
    dst_mac: frame.src_mac, // swap dst/src for response
    src_mac: frame.dst_mac,
    pdus: response_pdus,
  }
  response_frame.encode()
}

///|
/// Process a single PDU through the virtual slave chain.
fn VirtualBus::process_pdu(
  self : VirtualBus,
  pdu : @protocol.Pdu,
) -> @protocol.Pdu {
  let cmd = pdu.header.command
  let addr = pdu.header.address
  let data_len = pdu.data.length()
  let mut wkc = pdu.wkc
  // Make a mutable copy of the data
  let out_data = FixedArray::make(data_len, b'\x00')
  for i in 0..<data_len {
    out_data[i] = pdu.data[i]
  }
  match cmd {
    // Auto-increment commands
    @protocol.EcCommand::APRD => {
      let position = (addr & 0xFFFFU).reinterpret_as_int()
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.position == position {
          let reg_data = slave.read_reg(offset, data_len)
          for i in 0..<data_len {
            out_data[i] = reg_data[i]
          }
          wkc = wkc + 1U
          break
        }
      }
    }
    @protocol.EcCommand::APWR => {
      let position = (addr & 0xFFFFU).reinterpret_as_int()
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.position == position {
          slave.write_reg(offset, pdu.data)
          wkc = wkc + 1U
          break
        }
      }
    }
    @protocol.EcCommand::APRW => {
      let position = (addr & 0xFFFFU).reinterpret_as_int()
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.position == position {
          let reg_data = slave.read_reg(offset, data_len)
          for i in 0..<data_len {
            out_data[i] = reg_data[i]
          }
          slave.write_reg(offset, pdu.data)
          wkc = wkc + 3U // read+write = 3
          break
        }
      }
    }
    // Configured address commands
    @protocol.EcCommand::FPRD => {
      let station = addr & 0xFFFFU
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.station_address == station {
          let reg_data = slave.read_reg(offset, data_len)
          for i in 0..<data_len {
            out_data[i] = reg_data[i]
          }
          wkc = wkc + 1U
          break
        }
      }
    }
    @protocol.EcCommand::FPWR => {
      let station = addr & 0xFFFFU
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.station_address == station {
          slave.write_reg(offset, pdu.data)
          wkc = wkc + 1U
          break
        }
      }
    }
    @protocol.EcCommand::FPRW => {
      let station = addr & 0xFFFFU
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        if slave.station_address == station {
          let reg_data = slave.read_reg(offset, data_len)
          for i in 0..<data_len {
            out_data[i] = reg_data[i]
          }
          slave.write_reg(offset, pdu.data)
          wkc = wkc + 3U
          break
        }
      }
    }
    // Broadcast commands — all slaves respond
    @protocol.EcCommand::BRD => {
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        let reg_data = slave.read_reg(offset, data_len)
        // OR data from each slave (standard broadcast read behavior)
        for i in 0..<data_len {
          out_data[i] = out_data[i] | reg_data[i]
        }
        wkc = wkc + 1U
      }
    }
    @protocol.EcCommand::BWR => {
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        slave.write_reg(offset, pdu.data)
        wkc = wkc + 1U
      }
    }
    @protocol.EcCommand::BRW => {
      let offset = ((addr >> 16) & 0xFFFFU).reinterpret_as_int()
      for slave in self.slaves {
        let reg_data = slave.read_reg(offset, data_len)
        for i in 0..<data_len {
          out_data[i] = out_data[i] | reg_data[i]
        }
        slave.write_reg(offset, pdu.data)
        wkc = wkc + 3U
      }
    }
    // Logical / NOP / Multi-write — minimal handling
    @protocol.EcCommand::NOP => ()
    @protocol.EcCommand::LRD
    | @protocol.EcCommand::LWR
    | @protocol.EcCommand::LRW
    | @protocol.EcCommand::ARMW
    | @protocol.EcCommand::FRMW => ()
  }
  let result_data = Bytes::makei(data_len, fn(i) { out_data[i] })
  { header: pdu.header, data: result_data, wkc }
}

///|
/// Get the number of slaves on the virtual bus.
pub fn VirtualBus::slave_count(self : VirtualBus) -> Int {
  self.slaves.length()
}

///|
/// Get a reference to a slave by position.
pub fn VirtualBus::get_slave(
  self : VirtualBus,
  position : Int,
) -> VirtualSlave? {
  for slave in self.slaves {
    if slave.position == position {
      return Some(slave)
    }
  }
  None
}
