///|
/// CoE service types (CAN application protocol over EtherCAT).
pub(all) enum CoeService {
  SdoRequest
  SdoResponse
  SdoInfo
  PdoRemoteRequest
  TxPdo
  RxPdo
  Emergency
} derive(Eq, Debug)

///|
/// SDO command specifier for expedited/normal transfer.
pub(all) enum SdoCommand {
  DownloadRequest
  DownloadResponse
  UploadRequest
  UploadResponse
  AbortTransfer
} derive(Eq, Debug)

///|
/// SDO request descriptor.
pub(all) struct SdoRequest {
  index : UInt
  subindex : Byte
  command : SdoCommand
  data : Bytes
  complete_access : Bool
} derive(Eq, Debug)
