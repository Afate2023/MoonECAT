///|
/// CoE Emergency message decoding per ETG.1000.6 §5.6.3.
/// Emergency objects are sent unsolicited by slaves on error conditions.

///|
/// Decoded CoE Emergency message.
pub(all) struct EmergencyMessage {
  /// Emergency error code (2 bytes, ETG.1000.6 Table 44).
  error_code : UInt
  /// Error register value (1 byte, object 0x1001).
  error_register : Byte
  /// Manufacturer-specific error data (5 bytes).
  data : Bytes
} derive(Eq, Show)

///|
/// CoE Emergency message payload size (error_code + error_register + data).
let emergency_payload_len : Int = 8

///|
/// Decode a CoE Emergency message from the CoE payload
/// (after mailbox header + CoE header, i.e., the SDO/Emergency data area).
pub fn decode_emergency(payload : Bytes) -> EmergencyMessage raise @hal.EcError {
  if payload.length() < emergency_payload_len {
    raise @hal.EcError::MailboxProtocol(
      "emergency payload too short: " + payload.length().to_string(),
    )
  }
  let error_code = payload[0].to_uint() | (payload[1].to_uint() << 8)
  let error_register = payload[2]
  let data = Bytes::makei(5, fn(i) { payload[3 + i] })
  { error_code, error_register, data }
}

///|
/// Decode a full mailbox frame as a CoE Emergency message.
/// Parses mailbox header, verifies CoE type and Emergency service,
/// then decodes the emergency payload.
pub fn decode_emergency_frame(
  frame : Bytes,
) -> (MailboxHeader, EmergencyMessage) raise @hal.EcError {
  let mbh = MailboxHeader::from_bytes(frame)
  if mbh.mb_type != CoE {
    raise @hal.EcError::MailboxProtocol(
      "expected CoE mailbox for emergency, got " + mbh.mb_type.to_string(),
    )
  }
  // Verify we have enough data for CoE header + Emergency payload
  // Mailbox header = 6 bytes, CoE header = 2 bytes, Emergency = 8 bytes
  if frame.length() < 16 {
    raise @hal.EcError::MailboxProtocol(
      "emergency frame too short: " + frame.length().to_string(),
    )
  }
  // CoE header: service type in bits [15:12]
  let coe_word = frame[6].to_uint() | (frame[7].to_uint() << 8)
  let svc_field = (coe_word >> 12) & 0xFU
  if svc_field != 1U {
    // 1 = Emergency
    raise @hal.EcError::MailboxProtocol(
      "expected Emergency service (1), got " +
      svc_field.reinterpret_as_int().to_string(),
    )
  }
  // Emergency payload starts at offset 8 (after mailbox header + CoE header)
  let payload = Bytes::makei(emergency_payload_len, fn(i) { frame[8 + i] })
  let emg = decode_emergency(payload)
  (mbh, emg)
}
