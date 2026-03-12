///|
pub(all) struct HostCapabilityContract {
  nic_open : Bool
  nic_send : Bool
  nic_recv : Bool
  nic_close : Bool
  clock_now : Bool
  clock_sleep : Bool
  file_read : Bool
  file_write : Bool
  shared_memory : Bool
} derive(Eq, Show)

///|
pub fn required_host_contract(command : PluginCommand) -> HostCapabilityContract {
  match command {
    Scan | Validate | Run => {
      nic_open: true,
      nic_send: true,
      nic_recv: true,
      nic_close: true,
      clock_now: true,
      clock_sleep: true,
      file_read: false,
      file_write: false,
      shared_memory: false,
    }
  }
}

///|
pub fn encode_host_contract(contract : HostCapabilityContract) -> Json {
  Json::object({
    "nic_open": Json::boolean(contract.nic_open),
    "nic_send": Json::boolean(contract.nic_send),
    "nic_recv": Json::boolean(contract.nic_recv),
    "nic_close": Json::boolean(contract.nic_close),
    "clock_now": Json::boolean(contract.clock_now),
    "clock_sleep": Json::boolean(contract.clock_sleep),
    "file_read": Json::boolean(contract.file_read),
    "file_write": Json::boolean(contract.file_write),
    "shared_memory": Json::boolean(contract.shared_memory),
  })
}