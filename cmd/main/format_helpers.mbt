///|
fn decode_payload_u32_le(payload : Bytes) -> UInt? {
  if payload.length() <= 0 || payload.length() > 4 {
    return None
  }
  let mut value = 0U
  for i = 0; i < payload.length(); i = i + 1 {
    value = value | (payload[i].to_uint() << (i * 8))
  }
  Some(value)
}

///|
fn decode_u16_le(payload : Bytes, offset : Int) -> UInt {
  if offset + 1 >= payload.length() {
    0U
  } else {
    payload[offset].to_uint() | (payload[offset + 1].to_uint() << 8)
  }
}

///|
fn decode_u32_le(payload : Bytes, offset : Int) -> UInt {
  if offset + 3 >= payload.length() {
    0U
  } else {
    payload[offset].to_uint() |
    (payload[offset + 1].to_uint() << 8) |
    (payload[offset + 2].to_uint() << 16) |
    (payload[offset + 3].to_uint() << 24)
  }
}

///|
fn bytes_hex(payload : Bytes) -> String {
  let buf = @buffer.new(size_hint=payload.length() * 2 + 2)
  buf.write_string("0x")
  for i = 0; i < payload.length(); i = i + 1 {
    buf.write_string(hex_digit((payload[i].to_int() >> 4) & 0x0F))
    buf.write_string(hex_digit(payload[i].to_int() & 0x0F))
  }
  buf.to_string()
}

///|
fn resolved_sii_string(strings : Array[String], index : Byte) -> String {
  let idx = index.to_int()
  if idx <= 0 || idx > strings.length() {
    "not set"
  } else {
    strings[idx - 1]
  }
}

///|
fn physical_port_name(port : Byte) -> String {
  match port {
    b'\x00' => "not used"
    b'\x01' => "MII"
    b'\x02' => "reserved"
    b'\x03' => "EBUS"
    b'\x04' => "Fast Hot Connect"
    _ => "unknown"
  }
}

///|
fn fmmu_usage_name(direction : @mailbox.FmmuDirection) -> String {
  match direction {
    Outputs | DynamicOutputs => "used for Outputs"
    Inputs | DynamicInputs => "used for Inputs"
    MailboxState => "used for SyncM mailbox status (MBoxStat)"
  }
}

///|
fn sm_type_name(sm_type : @mailbox.SmType) -> String {
  match sm_type {
    MailboxOut => "Mailbox Out"
    MailboxIn => "Mailbox In"
    ProcessDataOut => "Process Data Out"
    ProcessDataIn => "Process Data In"
    DynamicProcessDataOut => "Dynamic Process Data Out"
    DynamicProcessDataIn => "Dynamic Process Data In"
    Unused => "not used or unknown"
  }
}

///|
fn production_weekday_name(weekday : Int) -> String {
  match weekday {
    1 => "Monday"
    2 => "Tuesday"
    3 => "Wednesday"
    4 => "Thursday"
    5 => "Friday"
    6 => "Saturday"
    7 => "Sunday"
    _ => "not set"
  }
}

///|
fn bytes_preview_hex(data : BytesView, max_bytes : Int) -> String {
  let buf = @buffer.new(size_hint=max_bytes * 3)
  let limit = if data.length() < max_bytes { data.length() } else { max_bytes }
  for i = 0; i < limit; i = i + 1 {
    if i > 0 {
      buf.write_string(" ")
    }
    buf.write_string(format_hex(data[i].to_uint(), 2))
  }
  if data.length() > max_bytes {
    buf.write_string(" ...")
  }
  buf.to_string()
}

///|
fn bool_yes_no(value : Bool) -> String {
  if value {
    "yes"
  } else {
    "no"
  }
}

///|
fn bool_enabled_text(value : Bool) -> String {
  if value {
    "enabled"
  } else {
    "not enabled"
  }
}

///|
fn esc_fmmu_type_description(type_register : Byte) -> String {
  match type_register {
    b'\x01' => "inputs"
    b'\x02' => "outputs"
    b'\x00' => "deactivated"
    _ => "unknown"
  }
}

///|
fn bool_true_false(value : Bool) -> String {
  if value {
    "True"
  } else {
    "False"
  }
}

///|
fn hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    _ => "F"
  }
}

///|
fn format_hex(value : UInt, digits : Int) -> String {
  let buf = @buffer.new(size_hint=digits + 2)
  buf.write_string("0x")
  let mut index = digits - 1
  while index >= 0 {
    let nibble = ((value >> (index * 4)) & 0xFU).reinterpret_as_int()
    buf.write_string(hex_digit(nibble))
    if index == 0 {
      break
    }
    index = index - 1
  }
  buf.to_string()
}

///|
fn join_strings(items : Array[String], separator : String) -> String {
  let mut out = ""
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      out = out + separator
    }
    out = out + items[i]
  }
  out
}

///|
fn trace_separator(length : Int) -> String {
  let mut out = ""
  for _i = 0; _i < length; _i = _i + 1 {
    out = out + "-"
  }
  out
}
