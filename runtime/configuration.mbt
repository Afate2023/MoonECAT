///|
/// Unified configuration model for online scan, offline config, and ENI JSON import.

///|
pub(all) enum ConfigurationSource {
  OnlineScan
  OfflineConfig
  EniImport
} derive(Eq, Show)

///|
pub(all) struct ConfigurationSlave {
  position : Int
  configured_address : UInt?
  identity : @hal.SlaveIdentity?
  identification : UInt?
  process_data_summary : ConfigurationProcessDataSummary?
} derive(Eq, Show)

///|
pub(all) struct ConfigurationMailboxProtocols {
  aoe : Bool
  coe : Bool
  eoe : Bool
  foe : Bool
  soe : Bool
  voe : Bool
} derive(Eq, Show)

///|
pub(all) struct ConfigurationProcessDataSummary {
  sync_manager_count : Int
  fmmu_count : Int
  rx_pdo_count : Int
  tx_pdo_count : Int
  mailbox_protocols : ConfigurationMailboxProtocols?
  dc_op_mode_count : Int
  dc_assign_activate_count : Int
} derive(Eq, Show)

///|
pub(all) struct ConfigurationModel {
  source : ConfigurationSource
  total_slaves : Int
  slaves : Array[ConfigurationSlave]
} derive(Eq, Show)

///|
pub(all) enum ConfigurationDifference {
  Missing(position~ : Int)
  Extra(position~ : Int)
  StationAddressMismatch(position~ : Int, expected~ : UInt?, actual~ : UInt?)
  IdentityMismatch(
    position~ : Int,
    expected~ : @hal.SlaveIdentity?,
    actual~ : @hal.SlaveIdentity?
  )
  IdentificationMismatch(position~ : Int, expected~ : UInt?, actual~ : UInt?)
  ProcessDataSummaryMismatch(
    position~ : Int,
    expected~ : ConfigurationProcessDataSummary,
    actual~ : ConfigurationProcessDataSummary
  )
} derive(Eq, Show)

///|
pub(all) struct ConfigurationComparisonReport {
  expected_source : ConfigurationSource
  actual_source : ConfigurationSource
  total_expected : Int
  total_found : Int
  differences : Array[ConfigurationDifference]
  all_ok : Bool
} derive(Eq, Show)

///|
pub fn configuration_from_scan(scan_report : ScanReport) -> ConfigurationModel {
  {
    source: OnlineScan,
    total_slaves: scan_report.slave_count,
    slaves: scan_report.slaves.map(fn(slave) {
      {
        position: slave.position,
        configured_address: Some(slave.station_address),
        identity: Some({
          vendor_id: slave.vendor_id,
          product_code: slave.product_code,
          revision: slave.revision,
          serial: slave.serial,
        }),
        identification: Some(slave.identification),
        process_data_summary: None,
      }
    }),
  }
}

///|
pub fn configuration_from_expected(
  expected : Array[@hal.SlaveConfig],
) -> ConfigurationModel {
  {
    source: OfflineConfig,
    total_slaves: expected.length(),
    slaves: expected.map(fn(slave) {
      {
        position: slave.position.reinterpret_as_int(),
        configured_address: Some(slave.configured_address),
        identity: slave.expected_identity,
        identification: slave.expected_identification,
        process_data_summary: None,
      }
    }),
  }
}

///|
/// Parse ENI JSON interchange and project slave info into the unified configuration model.
pub fn configuration_from_eni_json(
  json_content : String,
) -> ConfigurationModel raise @hal.EcError {
  project_eni_json_document(parse_eni_json_document(json_content))
}

///|
pub fn compare_configurations(
  expected : ConfigurationModel,
  actual : ConfigurationModel,
) -> ConfigurationComparisonReport {
  let differences : Array[ConfigurationDifference] = []
  let mut all_ok = true

  for exp in expected.slaves {
    let pos = exp.position
    match find_configuration_slave_at_position(actual.slaves, pos) {
      Some(found) => {
        if exp.configured_address is Some(expected_address) {
          match found.configured_address {
            Some(actual_address) =>
              if actual_address != expected_address {
                differences.push(
                  StationAddressMismatch(
                    position=pos,
                    expected=Some(expected_address),
                    actual=Some(actual_address),
                  ),
                )
                all_ok = false
                continue
              }
            None => {
              differences.push(
                StationAddressMismatch(
                  position=pos,
                  expected=Some(expected_address),
                  actual=None,
                ),
              )
              all_ok = false
              continue
            }
          }
        }

        if exp.identity is Some(expected_identity) {
          if found.identity != Some(expected_identity) {
            differences.push(
              IdentityMismatch(
                position=pos,
                expected=Some(expected_identity),
                actual=found.identity,
              ),
            )
            all_ok = false
          }
        }

        if exp.identification is Some(expected_identification) {
          if found.identification != Some(expected_identification) {
            differences.push(
              IdentificationMismatch(
                position=pos,
                expected=Some(expected_identification),
                actual=found.identification,
              ),
            )
            all_ok = false
          }
        }

        match (exp.process_data_summary, found.process_data_summary) {
          (Some(expected_summary), Some(actual_summary)) =>
            if actual_summary != expected_summary {
              differences.push(
                ProcessDataSummaryMismatch(
                  position=pos,
                  expected=expected_summary,
                  actual=actual_summary,
                ),
              )
              all_ok = false
            }
          _ => ()
        }
      }
      None => {
        differences.push(Missing(position=pos))
        all_ok = false
      }
    }
  }

  for found in actual.slaves {
    if not(has_configuration_position(expected.slaves, found.position)) {
      differences.push(Extra(position=found.position))
      all_ok = false
    }
  }

  {
    expected_source: expected.source,
    actual_source: actual.source,
    total_expected: expected.total_slaves,
    total_found: actual.total_slaves,
    differences,
    all_ok,
  }
}

///|
fn find_configuration_slave_at_position(
  slaves : Array[ConfigurationSlave],
  position : Int,
) -> ConfigurationSlave? {
  for slave in slaves {
    if slave.position == position {
      return Some(slave)
    }
  }
  None
}

///|
fn has_configuration_position(
  slaves : Array[ConfigurationSlave],
  position : Int,
) -> Bool {
  for slave in slaves {
    if slave.position == position {
      return true
    }
  }
  false
}
