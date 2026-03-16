///|
pub(all) enum NativeBackendKind {
  Auto
  LinuxRawSocket
  WindowsNpcap
} derive(Eq, Show)

///|
pub(all) struct NativeNicConfig {
  interface_name : String
  backend : NativeBackendKind
  snaplen : Int
  promisc : Bool
  timeout_ms : Int
} derive(Eq, Show)

///|
pub(all) struct NativeInterfaceInfo {
  name : String
  description : String
  loopback : Bool
  up : Bool
  connected : Bool
  wireless : Bool
  index : Int?
} derive(Eq, Show)

///|
pub(all) struct NativeInterfaceListing {
  backend : NativeBackendKind
  interfaces : Array[NativeInterfaceInfo]
} derive(Eq, Show)

///|
pub(all) struct NativeNic {
  config : NativeNicConfig
  mut handle_id : Int
  mut is_open : Bool
  mut last_sent : Bytes
} derive(Eq, Show)
