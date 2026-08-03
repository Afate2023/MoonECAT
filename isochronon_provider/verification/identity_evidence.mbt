///|
pub(all) suberror IdentityExternalEvidenceError {
  InvalidExternalIdentityEvidence(String)
} derive(Eq, Debug)

///|
pub struct IdentityExternalEvidenceReport {
  priv result_digest : String
  priv trace_digest : String
  priv capture_digest : String
  priv mapping_digest : String
  priv packet_count : Int
  priv transaction_count : Int
  priv detail : String
}

///|
/// Exact tshark projection owned by MoonECAT. Generic Lockwire process and
/// capture APIs do not need to know any EtherCAT dissector field.
pub fn identity_tshark_fields() -> Array[String] {
  [
    "frame.number", "frame.interface_id", "frame.cap_len", "frame.len", "frame.time_epoch",
    "eth.dst", "eth.src", "eth.type", "ecat.cmd", "ecat.adp", "ecat.ado", "ecat.subframe.length",
    "ecat.data",
  ]
}

///|
/// Stack-owned independent evidence join. Provider result, persisted Lockwire
/// trace, packet capture and tshark projection must all be consumed exactly.
pub fn verify_identity_external_evidence(
  result_bytes~ : Bytes,
  result_digest~ : String,
  trace_bytes~ : Bytes,
  trace_digest~ : String,
  capture_bytes~ : Bytes,
  capture_digest~ : String,
  capture_interface~ : String,
  tshark_stdout~ : Bytes,
  expected_topology_digest~ : String,
  expected_policy_digest~ : String,
) -> IdentityExternalEvidenceReport raise IdentityExternalEvidenceError {
  let decoded = @assurance.decode_identity_assurance_artifact(
    result_bytes,
    expected_digest=result_digest,
  ) catch {
    error =>
      raise InvalidExternalIdentityEvidence("provider artifact: \{Repr(error)}")
  }
  if decoded.disposition() !=
    @assurance.ProtocolFactsMatchAwaitingExternalEvidence ||
    decoded.expected_topology_digest() != expected_topology_digest ||
    decoded.policy_digest() != expected_policy_digest ||
    decoded.observed_count() != decoded.expected_count() ||
    decoded.issue_count() != 0 ||
    decoded.transaction_count() <= 0 {
    raise InvalidExternalIdentityEvidence(
      "provider identity facts do not match pinned target",
    )
  }
  let trace = @trace.RunTraceArtifact::from_canonical_bytes(trace_bytes) catch {
    error =>
      raise InvalidExternalIdentityEvidence("trace artifact: \{Repr(error)}")
  }
  if trace.digest_hex() != trace_digest ||
    trace.terminal().kind() != @trace.Committed ||
    trace.terminal().loss_count() != 0 {
    raise InvalidExternalIdentityEvidence(
      "trace digest or terminal state mismatch",
    )
  }
  let policy = @pcapng.PcapngCapturePolicy::verification_target(
    capture_interface,
  ) catch {
    error =>
      raise InvalidExternalIdentityEvidence("capture policy: \{Repr(error)}")
  }
  let capture = @pcapng.parse_pcapng_capture(capture_bytes, policy) catch {
    error =>
      raise InvalidExternalIdentityEvidence("capture artifact: \{Repr(error)}")
  }
  if capture.digest_hex() != capture_digest ||
    !capture.all_bytes_consumed() ||
    capture.packet_count() <= 0 {
    raise InvalidExternalIdentityEvidence(
      "capture digest or completeness mismatch",
    )
  }
  let mapping = @pcapng.derive_exact_capture_trace_mapping(trace, capture)
  let correlation = @pcapng.correlate_capture_trace(trace, capture, mapping)
  if !correlation.passes() {
    raise InvalidExternalIdentityEvidence(
      "trace/capture correlation is incomplete",
    )
  }
  verify_tshark_projection(capture, tshark_stdout)
  {
    result_digest,
    trace_digest,
    capture_digest,
    mapping_digest: correlation.mapping_digest_hex(),
    packet_count: capture.packet_count(),
    transaction_count: decoded.transaction_count(),
    detail: "provider identity, persisted trace, pcapng and tshark projection agree",
  }
}

///|
fn verify_tshark_projection(
  capture : @pcapng.PcapngCaptureArtifact,
  stdout : Bytes,
) -> Unit raise IdentityExternalEvidenceError {
  if stdout.is_empty() || stdout.length() > 1024 * 1024 {
    raise InvalidExternalIdentityEvidence("tshark output bound")
  }
  let lines = tshark_projection_lines(stdout)
  if lines.length() != capture.packet_count() {
    raise InvalidExternalIdentityEvidence(
      "tshark did not consume every capture packet",
    )
  }
  for index, line in lines {
    let fields = line.split("\t").to_array()
    guard capture.packet_at(index) is Some(packet) else {
      raise InvalidExternalIdentityEvidence("capture packet index disappeared")
    }
    if fields.length() != identity_tshark_fields().length() ||
      parse_exact_decimal(fields[0], index + 1) == false ||
      parse_exact_decimal(fields[1], packet.interface_id()) == false ||
      parse_exact_decimal(fields[2], packet.captured_length()) == false ||
      parse_exact_decimal(fields[3], packet.original_length()) == false ||
      fields[4].is_empty() ||
      !tshark_projection_matches_frame(fields, packet.frame()) {
      raise InvalidExternalIdentityEvidence(
        "tshark EtherCAT projection mismatch at packet \{index}",
      )
    }
  }
}

///|
fn tshark_projection_matches_frame(
  fields : Array[StringView],
  frame_bytes : Bytes,
) -> Bool {
  if fields.length() != identity_tshark_fields().length() {
    return false
  }
  let frame = @protocol.EcFrame::decode(frame_bytes) catch { _ => return false }
  if frame.pdus.length() != 1 {
    return false
  }
  let pdu = frame.pdus[0]
  let projected_data = fields[12].to_owned()
  // Wireshark suppresses the generic ecat.data field when a register-specific
  // dissector consumes the payload. A non-empty projection must still match
  // every APWR byte; raw frame bytes are decoded and checked independently.
  let data_matches = match pdu.header.command {
    @protocol.APWR =>
      projected_data.is_empty() || projected_data == tshark_data_text(pdu.data)
    @protocol.APRD | @protocol.BRD => projected_data.is_empty()
    _ => false
  }
  fields[5].to_owned() == tshark_mac_text(frame.dst_mac) &&
  fields[6].to_owned() == tshark_mac_text(frame.src_mac) &&
  fields[7].to_owned() == "0x88a4" &&
  fields[8].to_owned() == "0x" + pdu.header.command.to_byte().to_hex() &&
  fields[9].to_owned() ==
  tshark_hex16(@protocol.address_station(pdu.header.address)) &&
  fields[10].to_owned() ==
  tshark_hex16(@protocol.address_offset(pdu.header.address)) &&
  parse_exact_decimal(fields[11], pdu.data.length()) &&
  data_matches
}

///|
fn tshark_mac_text(mac : FixedArray[Byte]) -> String {
  let builder = StringBuilder::new()
  for index in 0..<mac.length() {
    if index > 0 {
      builder.write_char(':')
    }
    builder.write_string(mac[index].to_hex())
  }
  builder.to_string()
}

///|
fn tshark_hex16(value : UInt) -> String {
  "0x" +
  ((value >> 8) & 0xFFU).reinterpret_as_int().to_byte().to_hex() +
  (value & 0xFFU).reinterpret_as_int().to_byte().to_hex()
}

///|
fn tshark_data_text(data : Bytes) -> String {
  let builder = StringBuilder::new()
  for byte in data {
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
fn tshark_projection_lines(
  stdout : Bytes,
) -> Array[String] raise IdentityExternalEvidenceError {
  let text = @utf8.decode(stdout) catch {
    _ => raise InvalidExternalIdentityEvidence("tshark output is not UTF-8")
  }
  let lines : Array[String] = []
  for raw in text.split("\n") {
    let line = if raw.has_suffix("\r") {
      raw[:raw.length() - 1].to_owned()
    } else {
      raw.to_owned()
    }
    if !line.is_empty() {
      lines.push(line)
    }
  }
  lines
}

///|
fn parse_exact_decimal(value : StringView, expected : Int) -> Bool {
  let parsed = @string.parse_int(value) catch { _ => return false }
  parsed == expected && parsed.to_string() == value.to_owned()
}

///|
pub fn IdentityExternalEvidenceReport::result_digest(
  self : IdentityExternalEvidenceReport,
) -> String {
  self.result_digest
}

///|
pub fn IdentityExternalEvidenceReport::trace_digest(
  self : IdentityExternalEvidenceReport,
) -> String {
  self.trace_digest
}

///|
pub fn IdentityExternalEvidenceReport::capture_digest(
  self : IdentityExternalEvidenceReport,
) -> String {
  self.capture_digest
}

///|
pub fn IdentityExternalEvidenceReport::mapping_digest(
  self : IdentityExternalEvidenceReport,
) -> String {
  self.mapping_digest
}

///|
pub fn IdentityExternalEvidenceReport::packet_count(
  self : IdentityExternalEvidenceReport,
) -> Int {
  self.packet_count
}

///|
pub fn IdentityExternalEvidenceReport::transaction_count(
  self : IdentityExternalEvidenceReport,
) -> Int {
  self.transaction_count
}

///|
pub fn IdentityExternalEvidenceReport::detail(
  self : IdentityExternalEvidenceReport,
) -> String {
  self.detail
}
