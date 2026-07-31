///|
pub(all) enum NativeBackendKind {
  Auto
  LinuxRawSocket
  WindowsNpcap
} derive(Eq, Debug)

///|
pub(all) struct NativeNicConfig {
  interface_name : String
  backend : NativeBackendKind
  snaplen : Int
  promisc : Bool
  timeout_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct NativeInterfaceInfo {
  name : String
  description : String
  loopback : Bool
  up : Bool
  connected : Bool
  wireless : Bool
  index : Int?
} derive(Eq, Debug)

///|
pub(all) struct NativeInterfaceListing {
  backend : NativeBackendKind
  interfaces : Array[NativeInterfaceInfo]
} derive(Eq, Debug)

///|
pub(all) struct NativeNic {
  config : NativeNicConfig
  mut handle_id : Int
  mut is_open : Bool
  mut last_sent : Bytes
  mut next_datagram_index : Int
  mut protocol_datagram_indices : Array[Byte]
  mut wire_datagram_indices : Array[Byte]
} derive(Eq, Debug)
