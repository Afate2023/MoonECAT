///|
/// ENI JSON interchange kept separate from the runtime-facing
/// ConfigurationModel. Runtime accepts only this normalized JSON surface,
/// while XML parsing lives in a standalone conversion tool.

///|
priv struct EniJsonIdentity {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
} derive(ToJson)

///|
priv struct EniJsonMailboxProtocols {
  aoe : Bool
  coe : Bool
  eoe : Bool
  foe : Bool
  soe : Bool
  voe : Bool
} derive(ToJson)

///|
priv struct EniJsonProcessDataSummary {
  sync_manager_count : Int
  fmmu_count : Int
  rx_pdo_count : Int
  tx_pdo_count : Int
  mailbox_protocols : EniJsonMailboxProtocols?
  dc_op_mode_count : Int
  dc_assign_activate_count : Int
} derive(ToJson)

///|
priv struct EniJsonSlave {
  position : Int
  configured_address : UInt?
  alias_address : UInt?
  identity : EniJsonIdentity?
  identification : UInt?
  process_data_summary : EniJsonProcessDataSummary?
  presence : String?
  hot_connect_group : UInt?
} derive(ToJson)

///|
priv struct EniJsonDocument {
  slaves : Array[EniJsonSlave]
} derive(ToJson)

///|
fn parse_eni_json_document(
  json_content : String,
) -> EniJsonDocument raise @hal.EcError {
  let parsed = @json.parse(json_content[:]) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ENI JSON parse failed: " + err.to_string(),
      )
  }
  parse_eni_json_document_value(parsed)
}

///|
fn parse_eni_json_document_value(
  json : Json,
) -> EniJsonDocument raise @hal.EcError {
  guard json is { "slaves": Array(slaves_json), .. } else {
    raise @hal.EcError::EsiParseFailed(
      "ENI JSON decode failed: missing slaves array",
    )
  }
  { slaves: slaves_json.map(slave_json => parse_eni_json_slave(slave_json)) }
}

///|
fn parse_eni_json_slave(json : Json) -> EniJsonSlave raise @hal.EcError {
  guard json
    is {
      "position": position_json,
      "configured_address"? : configured_address_json,
      "alias_address"? : alias_address_json,
      "identity"? : identity_json,
      "identification"? : identification_json,
      "process_data_summary"? : process_data_summary_json,
      "presence"? : presence_json,
      "hot_connect_group"? : hot_connect_group_json,
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ENI JSON decode failed: invalid slave entry",
    )
  }
  {
    position: decode_eni_json_int(position_json),
    configured_address: decode_optional_eni_json_value_uint(
      configured_address_json,
    ),
    alias_address: decode_optional_eni_json_value_uint(alias_address_json),
    identity: decode_optional_eni_json_identity(identity_json),
    identification: decode_optional_eni_json_value_uint(identification_json),
    process_data_summary: decode_optional_eni_json_process_data_summary(
      process_data_summary_json,
    ),
    presence: decode_optional_eni_json_string(presence_json),
    hot_connect_group: decode_optional_eni_json_value_uint(
      hot_connect_group_json,
    ),
  }
}

///|
fn decode_optional_eni_json_string(json : Json?) -> String? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      let decoded : String = @json.from_json(value) catch {
        err =>
          raise @hal.EcError::EsiParseFailed(
            "ENI JSON decode failed: " + err.to_string(),
          )
      }
      Some(decoded)
    }
  }
}

///|
fn decode_optional_eni_json_identity(
  json : Json?,
) -> EniJsonIdentity? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      guard value
        is {
          "vendor_id": vendor_id_json,
          "product_code": product_code_json,
          "revision": revision_json,
          "serial": serial_json,
          ..
        } else {
        raise @hal.EcError::EsiParseFailed(
          "ENI JSON decode failed: invalid identity entry",
        )
      }
      Some({
        vendor_id: decode_eni_json_uint(vendor_id_json),
        product_code: decode_eni_json_uint(product_code_json),
        revision: decode_eni_json_uint(revision_json),
        serial: decode_eni_json_uint(serial_json),
      })
    }
  }
}

///|
fn decode_optional_eni_json_process_data_summary(
  json : Json?,
) -> EniJsonProcessDataSummary? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      guard value
        is {
          "sync_manager_count": sync_manager_count_json,
          "fmmu_count": fmmu_count_json,
          "rx_pdo_count": rx_pdo_count_json,
          "tx_pdo_count": tx_pdo_count_json,
          "mailbox_protocols"? : mailbox_protocols_json,
          "dc_op_mode_count": dc_op_mode_count_json,
          "dc_assign_activate_count": dc_assign_activate_count_json,
          ..
        } else {
        raise @hal.EcError::EsiParseFailed(
          "ENI JSON decode failed: invalid process_data_summary entry",
        )
      }
      Some({
        sync_manager_count: decode_eni_json_int(sync_manager_count_json),
        fmmu_count: decode_eni_json_int(fmmu_count_json),
        rx_pdo_count: decode_eni_json_int(rx_pdo_count_json),
        tx_pdo_count: decode_eni_json_int(tx_pdo_count_json),
        mailbox_protocols: decode_optional_eni_json_mailbox_protocols(
          mailbox_protocols_json,
        ),
        dc_op_mode_count: decode_eni_json_int(dc_op_mode_count_json),
        dc_assign_activate_count: decode_eni_json_int(
          dc_assign_activate_count_json,
        ),
      })
    }
  }
}

///|
fn decode_optional_eni_json_mailbox_protocols(
  json : Json?,
) -> EniJsonMailboxProtocols? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      guard value
        is {
          "aoe": aoe_json,
          "coe": coe_json,
          "eoe": eoe_json,
          "foe": foe_json,
          "soe": soe_json,
          "voe": voe_json,
          ..
        } else {
        raise @hal.EcError::EsiParseFailed(
          "ENI JSON decode failed: invalid mailbox_protocols entry",
        )
      }
      Some({
        aoe: decode_eni_json_bool(aoe_json),
        coe: decode_eni_json_bool(coe_json),
        eoe: decode_eni_json_bool(eoe_json),
        foe: decode_eni_json_bool(foe_json),
        soe: decode_eni_json_bool(soe_json),
        voe: decode_eni_json_bool(voe_json),
      })
    }
  }
}

///|
fn decode_optional_eni_json_value_uint(
  json : Json?,
) -> UInt? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => Some(decode_eni_json_uint(value))
  }
}

///|
fn decode_eni_json_int(json : Json) -> Int raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ENI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_eni_json_uint(json : Json) -> UInt raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ENI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_eni_json_bool(json : Json) -> Bool raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ENI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
pub fn configuration_to_eni_json(model : ConfigurationModel) -> Json {
  eni_json_document_from_configuration(model).to_json()
}

///|
pub fn configuration_to_eni_json_string(
  model : ConfigurationModel,
  indent? : Int = 2,
) -> String {
  configuration_to_eni_json(model).stringify(indent~)
}

///|
fn project_eni_json_document(document : EniJsonDocument) -> ConfigurationModel {
  {
    source: EniImport,
    total_slaves: document.slaves.length(),
    slaves: document.slaves.map(fn(slave) {
      {
        position: slave.position,
        configured_address: slave.configured_address,
        alias_address: slave.alias_address,
        identity: slave.identity.map(fn(identity) {
          {
            vendor_id: identity.vendor_id,
            product_code: identity.product_code,
            revision: identity.revision,
            serial: identity.serial,
          }
        }),
        identification: slave.identification,
        process_data_summary: slave.process_data_summary.map(fn(summary) {
          {
            sync_manager_count: summary.sync_manager_count,
            fmmu_count: summary.fmmu_count,
            rx_pdo_count: summary.rx_pdo_count,
            tx_pdo_count: summary.tx_pdo_count,
            mailbox_protocols: summary.mailbox_protocols.map(fn(protocols) {
              {
                aoe: protocols.aoe,
                coe: protocols.coe,
                eoe: protocols.eoe,
                foe: protocols.foe,
                soe: protocols.soe,
                voe: protocols.voe,
              }
            }),
            dc_op_mode_count: summary.dc_op_mode_count,
            dc_assign_activate_count: summary.dc_assign_activate_count,
          }
        }),
        presence: decode_eni_json_presence(
          slave.presence,
          slave.hot_connect_group,
        ),
      }
    }),
  }
}

///|
fn eni_json_document_from_configuration(
  model : ConfigurationModel,
) -> EniJsonDocument {
  {
    slaves: model.slaves.map(fn(slave) {
      {
        position: slave.position,
        configured_address: slave.configured_address,
        alias_address: slave.alias_address,
        identity: slave.identity.map(fn(identity) {
          {
            vendor_id: identity.vendor_id,
            product_code: identity.product_code,
            revision: identity.revision,
            serial: identity.serial,
          }
        }),
        identification: slave.identification,
        process_data_summary: slave.process_data_summary.map(fn(summary) {
          {
            sync_manager_count: summary.sync_manager_count,
            fmmu_count: summary.fmmu_count,
            rx_pdo_count: summary.rx_pdo_count,
            tx_pdo_count: summary.tx_pdo_count,
            mailbox_protocols: summary.mailbox_protocols.map(fn(protocols) {
              {
                aoe: protocols.aoe,
                coe: protocols.coe,
                eoe: protocols.eoe,
                foe: protocols.foe,
                soe: protocols.soe,
                voe: protocols.voe,
              }
            }),
            dc_op_mode_count: summary.dc_op_mode_count,
            dc_assign_activate_count: summary.dc_assign_activate_count,
          }
        }),
        presence: match slave.presence {
          @hal.Mandatory => Some("mandatory")
          @hal.Optional(..) => Some("optional")
        },
        hot_connect_group: match slave.presence {
          @hal.Mandatory => None
          @hal.Optional(group_id~) => group_id
        },
      }
    }),
  }
}

///|
fn decode_eni_json_presence(
  presence : String?,
  hot_connect_group : UInt?,
) -> @hal.SlavePresence {
  match presence {
    Some("optional") => @hal.Optional(group_id=hot_connect_group)
    _ => @hal.Mandatory
  }
}
