///|
/// NicEventLog persistence: NDJSON export/import (B-8).
///
/// Each line is a JSON object representing one NicEvent:
///   {"type":"sent","data":"88a4...","len":42}
///   {"type":"received","data":"88a4..."}
///   {"type":"recv_timeout"}
///   {"type":"send_failed","msg":"..."}
///
/// Header line (optional) carries recording metadata:
///   {"header":true,"version":1,"slave_count":2,"fingerprint":"..."}

///|
/// Convert a single NicEvent to a JSON-compatible string.
pub fn nic_event_to_json(event : NicEvent) -> String {
  match event {
    Sent(data, len) => {
      let hex = bytes_to_hex(data)
      "{\"type\":\"sent\",\"data\":\"" +
      hex +
      "\",\"len\":" +
      len.to_string() +
      "}"
    }
    Received(data) => {
      let hex = bytes_to_hex(data)
      "{\"type\":\"received\",\"data\":\"" + hex + "\"}"
    }
    RecvTimeout => "{\"type\":\"recv_timeout\"}"
    SendFailed(msg) => {
      let escaped = escape_json_string(msg)
      "{\"type\":\"send_failed\",\"msg\":\"" + escaped + "\"}"
    }
  }
}

///|
/// Export a NicEventLog as NDJSON (one JSON object per line).
pub fn NicEventLog::to_ndjson(self : NicEventLog) -> String {
  let buf = StringBuilder::new()
  for i, event in self.events {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(nic_event_to_json(event))
  }
  buf.to_string()
}

///|
/// Export a NicEventLog with a header line containing metadata.
pub fn NicEventLog::to_ndjson_with_header(
  self : NicEventLog,
  slave_count? : Int = 0,
  fingerprint? : String = "",
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"header\":true,\"version\":1,\"slave_count\":")
  buf.write_string(slave_count.to_string())
  buf.write_string(",\"fingerprint\":\"")
  buf.write_string(escape_json_string(fingerprint))
  buf.write_string("\"}")
  for event in self.events {
    buf.write_char('\n')
    buf.write_string(nic_event_to_json(event))
  }
  buf.to_string()
}

///|
/// Parse a single NDJSON line into a NicEvent.
/// Returns None for header lines or unparseable lines.
pub fn nic_event_from_json(line : String) -> NicEvent? {
  if line.contains("\"header\":true") || line.length() == 0 {
    return None
  }
  if line.contains("\"type\":\"sent\"") {
    let data = extract_json_hex(line, "data")
    let len = extract_json_int(line, "len")
    Some(Sent(data, len))
  } else if line.contains("\"type\":\"received\"") {
    let data = extract_json_hex(line, "data")
    Some(Received(data))
  } else if line.contains("\"type\":\"recv_timeout\"") {
    Some(RecvTimeout)
  } else if line.contains("\"type\":\"send_failed\"") {
    let msg = extract_json_string(line, "msg")
    Some(SendFailed(msg))
  } else {
    None
  }
}

///|
/// Import a NicEventLog from NDJSON text (one JSON per line).
/// Header lines are skipped.
pub fn NicEventLog::from_ndjson(text : String) -> NicEventLog {
  let log = NicEventLog::new()
  let lines = split_lines(text)
  for line in lines {
    let trimmed = line
    match nic_event_from_json(trimmed) {
      Some(event) => log.append(event)
      None => ()
    }
  }
  log
}

///|
/// Convert bytes to hex string.
fn bytes_to_hex(data : Bytes) -> String {
  let buf = StringBuilder::new()
  let hex_chars = "0123456789abcdef".to_array()
  for i in 0..<data.length() {
    let b = data[i].to_int()
    buf.write_char(hex_chars[b >> 4])
    buf.write_char(hex_chars[b & 0x0F])
  }
  buf.to_string()
}

///|
/// Parse a hex string back to bytes.
fn hex_to_bytes(hex : String) -> Bytes {
  let chars = hex.to_array()
  let len = chars.length() / 2
  if len == 0 {
    return Bytes::new(0)
  }
  let arr = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    let hi = hex_digit(chars[i * 2])
    let lo = hex_digit(chars[i * 2 + 1])
    arr[i] = ((hi << 4) | lo).to_byte()
  }
  Bytes::from_array(arr)
}

///|
fn hex_digit(c : Char) -> Int {
  let code = c.to_int()
  if code >= 0x30 && code <= 0x39 {
    code - 0x30
  } else if code >= 0x61 && code <= 0x66 {
    code - 0x61 + 10
  } else if code >= 0x41 && code <= 0x46 {
    code - 0x41 + 10
  } else {
    0
  }
}

///|
/// Escape special characters for JSON strings.
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Extract a hex-encoded byte array field from a JSON line.
fn extract_json_hex(line : String, field : String) -> Bytes {
  let hex = extract_json_string(line, field)
  hex_to_bytes(hex)
}

///|
/// Extract an integer field value from a JSON line.
fn extract_json_int(line : String, field : String) -> Int {
  let key = "\"" + field + "\":"
  let haystack = line.to_array()
  let needle = key.to_array()
  let pos = find_substr(haystack, needle)
  if pos < 0 {
    return 0
  }
  let start = pos + needle.length()
  let buf = StringBuilder::new()
  for i = start; i < haystack.length(); i = i + 1 {
    let c = haystack[i]
    if c >= '0' && c <= '9' {
      buf.write_char(c)
    } else if c == '-' && buf.to_string().length() == 0 {
      buf.write_char(c)
    } else {
      break
    }
  }
  let s = buf.to_string()
  if s.length() == 0 {
    0
  } else {
    parse_int_simple(s)
  }
}

///|
/// Extract a string field value from a JSON line.
fn extract_json_string(line : String, field : String) -> String {
  let key = "\"" + field + "\":\""
  let haystack = line.to_array()
  let needle = key.to_array()
  let pos = find_substr(haystack, needle)
  if pos < 0 {
    return ""
  }
  let start = pos + needle.length()
  let buf = StringBuilder::new()
  let mut escaped = false
  for i = start; i < haystack.length(); i = i + 1 {
    let c = haystack[i]
    if escaped {
      buf.write_char(c)
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '"' {
      break
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Find a substring in a char array, returning the start index or -1.
fn find_substr(haystack : Array[Char], needle : Array[Char]) -> Int {
  if needle.length() == 0 {
    return 0
  }
  if haystack.length() < needle.length() {
    return -1
  }
  for i in 0..<=(haystack.length() - needle.length()) {
    let mut matched = true
    for j in 0..<needle.length() {
      if haystack[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
/// Split text into lines.
fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for c in text {
    if c == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push(remaining)
  }
  lines
}

///|
/// Simple integer parser (avoids external dependency).
fn parse_int_simple(s : String) -> Int {
  let chars = s.to_array()
  let mut result = 0
  let mut negative = false
  let mut start = 0
  if chars.length() > 0 && chars[0] == '-' {
    negative = true
    start = 1
  }
  for i = start; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 0x30)
    }
  }
  if negative {
    -result
  } else {
    result
  }
}
