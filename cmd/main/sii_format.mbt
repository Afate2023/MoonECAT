///|
fn general_json(info : @mailbox.SiiGeneral, strings : Array[String]) -> Json {
  Json::object({
    "group_idx": Json::number(info.group_idx.to_uint().to_double()),
    "group_name": Json::string(resolved_sii_string(strings, info.group_idx)),
    "image_idx": Json::number(info.image_idx.to_uint().to_double()),
    "image_name": Json::string(resolved_sii_string(strings, info.image_idx)),
    "order_idx": Json::number(info.order_idx.to_uint().to_double()),
    "order_name": Json::string(resolved_sii_string(strings, info.order_idx)),
    "name_idx": Json::number(info.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, info.name_idx)),
    "coe_details": Json::object({
      "raw": Json::number(info.coe_details.to_uint().to_double()),
      "enable_sdo": Json::boolean(info.supports_coe_sdo()),
      "enable_sdo_info": Json::boolean(info.supports_coe_sdo_info()),
      "enable_pdo_assign": Json::boolean(info.supports_coe_pdo_assign()),
      "enable_pdo_configuration": Json::boolean(
        info.supports_coe_pdo_configuration(),
      ),
      "enable_upload_at_startup": Json::boolean(
        info.supports_coe_upload_at_startup(),
      ),
      "enable_sdo_complete_access": Json::boolean(
        info.supports_coe_complete_access(),
      ),
    }),
    "foe_supported": Json::boolean(info.foe_supported),
    "eoe_supported": Json::boolean(info.eoe_supported),
    "soe_supported": Json::boolean(info.soe_supported),
    "soe_channels": Json::number(info.soe_channels.to_uint().to_double()),
    "ds402_channels": Json::number(info.ds402_channels.to_uint().to_double()),
    "sysman_class": Json::number(info.sysman_class.to_uint().to_double()),
    "flags": Json::object({
      "raw": Json::number(info.flags.to_uint().to_double()),
      "safe_op": Json::boolean(info.is_op_only()),
      "not_lrw": Json::boolean(info.prefers_not_lrw()),
      "mailbox_data_link_layer": Json::boolean(
        info.supports_mailbox_data_link_layer(),
      ),
      "ident_al_status": Json::boolean(info.supports_identification_ado()),
      "ident_physical_memory": Json::boolean(
        info.supports_identification_physical_memory(),
      ),
    }),
    "current_on_ebus": Json::number(info.current_on_ebus.to_double()),
    "physical_ports": Json::array([
      Json::string(physical_port_name(info.physical_port_0)),
      Json::string(physical_port_name(info.physical_port_1)),
      Json::string(physical_port_name(info.physical_port_2)),
      Json::string(physical_port_name(info.physical_port_3)),
    ]),
    "physical_memory_address": Json::number(
      info.physical_memory_address.to_double(),
    ),
  })
}

///|
fn pdo_json(pdo : @mailbox.SiiPdo, strings : Array[String]) -> Json {
  let entries_json = pdo.entries.map(fn(entry) {
    Json::object({
      "entry_index": Json::number(entry.entry_index.to_double()),
      "subindex": Json::number(entry.subindex.to_uint().to_double()),
      "name_idx": Json::number(entry.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, entry.name_idx)),
      "data_type": Json::number(entry.data_type.to_uint().to_double()),
      "bit_length": Json::number(entry.bit_length.to_uint().to_double()),
      "flags": Json::number(entry.flags.to_double()),
    })
  })
  Json::object({
    "pdo_index": Json::number(pdo.pdo_index.to_double()),
    "entry_count": Json::number(pdo.entry_count.to_uint().to_double()),
    "sync_manager": Json::number(pdo.sync_manager.to_uint().to_double()),
    "synchronization": Json::number(pdo.synchronization.to_uint().to_double()),
    "name_idx": Json::number(pdo.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, pdo.name_idx)),
    "flags": Json::number(pdo.flags.to_double()),
    "entries": Json::array(entries_json),
  })
}

///|
fn read_sii_json(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> Json {
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let fmmu = sii.fmmu
  let sync_managers = sii.sync_managers
  let dc_clocks = sii.dc_clocks
  let tx_pdo = sii.tx_pdo
  let rx_pdo = sii.rx_pdo
  let categories = sii.categories
  let categories_json = categories.map(fn(entry) {
    let category_class = entry.category_class().label()
    let (overlay_key, overlay_status, overlay_decoder) = match
      entry.overlay_candidate() {
      Some(candidate) =>
        (
          Json::string(candidate.dispatch_key()),
          Json::string(candidate.status_label()),
          match candidate.decoder_name() {
            Some(name) => Json::string(name)
            None => Json::null()
          },
        )
      None => (Json::null(), Json::null(), Json::null())
    }
    Json::object({
      "category": Json::string(entry.category.to_string()),
      "title": Json::string(sii_category_title(entry.category, entry.type_code)),
      "category_code": Json::number(entry.type_code.to_double()),
      "category_class": Json::string(category_class),
      "overlay_key": overlay_key,
      "overlay_status": overlay_status,
      "overlay_decoder": overlay_decoder,
      "known": Json::boolean(entry.category != @mailbox.Raw),
      "byte_length": Json::number(entry.data.length().to_double()),
      "preview_hex": Json::string(bytes_preview_hex(entry.data, 16)),
    })
  })
  let strings_json = strings.map(fn(text) { Json::string(text) })
  let general_json = match general {
    Some(info) => general_json(info, strings)
    None => Json::null()
  }
  let fmmu_json = fmmu.map(fn(direction) {
    Json::object({
      "usage": Json::string(direction.to_string()),
      "description": Json::string(fmmu_usage_name(direction)),
    })
  })
  let fmmu_ex_json = sii.fmmu_ex.map(fn(entry) {
    Json::object({
      "op_only": Json::boolean(entry.op_only),
      "sm_defined": Json::boolean(entry.sm_defined),
      "su_defined": Json::boolean(entry.su_defined),
      "sync_manager": Json::number(entry.sync_manager.to_uint().to_double()),
      "sync_unit": Json::number(entry.sync_unit.to_uint().to_double()),
    })
  })
  let sm_json = sync_managers.map(fn(sm) {
    Json::object({
      "physical_start": Json::number(sm.physical_start.to_double()),
      "length": Json::number(sm.length.to_double()),
      "control": Json::number(sm.control.to_uint().to_double()),
      "status": Json::number(sm.status.to_uint().to_double()),
      "activate": Json::number(sm.activate.to_uint().to_double()),
      "sm_type": Json::string(sm.sm_type.to_string()),
    })
  })
  let sync_units_json = sii.sync_units.map(fn(entry) {
    Json::object({
      "separate_su": Json::boolean(entry.separate_su),
      "separate_frame": Json::boolean(entry.separate_frame),
      "depend_on_input_state": Json::boolean(entry.depend_on_input_state),
      "frame_repeat_support": Json::boolean(entry.frame_repeat_support),
      "raw_flags": Json::number(entry.raw_flags.to_uint().to_double()),
    })
  })
  let dc_json = dc_clocks.map(fn(dc) {
    Json::object({
      "cycle_time_0": Json::number(dc.cycle_time_0.to_double()),
      "shift_time_0": Json::number(dc.shift_time_0.to_double()),
      "shift_time_1": Json::number(dc.shift_time_1.to_double()),
      "sync1_cycle_factor": Json::number(dc.sync1_cycle_factor.to_double()),
      "assign_activate": Json::number(dc.assign_activate.to_double()),
      "sync0_cycle_factor": Json::number(dc.sync0_cycle_factor.to_double()),
      "name_idx": Json::number(dc.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, dc.name_idx)),
      "description_idx": Json::number(dc.description_idx.to_uint().to_double()),
      "description": Json::string(
        resolved_sii_string(strings, dc.description_idx),
      ),
    })
  })
  let tx_pdo_json = tx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let rx_pdo_json = rx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let timeouts_json = match sii.timeouts {
    Some(value) =>
      Json::object({
        "preop_timeout_ms": Json::number(value.preop_timeout_ms.to_double()),
        "safeop_op_timeout_ms": Json::number(
          value.safeop_op_timeout_ms.to_double(),
        ),
        "back_to_init_timeout_ms": Json::number(
          value.back_to_init_timeout_ms.to_double(),
        ),
        "back_to_safeop_timeout_ms": Json::number(
          value.back_to_safeop_timeout_ms.to_double(),
        ),
        "mailbox_request_timeout_ms": Json::number(
          value.mailbox_request_timeout_ms.to_double(),
        ),
        "mailbox_response_timeout_ms": Json::number(
          value.mailbox_response_timeout_ms.to_double(),
        ),
      })
    None => Json::null()
  }
  Json::object({
    "position": Json::number(position.to_double()),
    "word_count": Json::number(word_count.to_double()),
    "preamble": Json::object({
      "pdi_control": Json::number(preamble.pdi_control.to_double()),
      "pdi_config": Json::number(preamble.pdi_config.to_double()),
      "sync_impulse_length_raw": Json::number(
        preamble.sync_impulse_length_raw.to_double(),
      ),
      "sync_impulse_length_ns": Json::number(
        preamble.sync_impulse_length_ns().to_double(),
      ),
      "pdi_config2": Json::number(preamble.pdi_config2.to_double()),
      "configured_station_alias": Json::number(
        preamble.configured_station_alias.to_double(),
      ),
      "checksum": Json::number(preamble.checksum.to_double()),
      "checksum_ok": Json::boolean(preamble.checksum_ok),
    }),
    "header": Json::object({
      "vendor_id": Json::number(header.vendor_id.to_double()),
      "product_code": Json::number(header.product_code.to_double()),
      "revision": Json::number(header.revision.to_double()),
      "serial": Json::number(header.serial.to_double()),
      "bootstrap_rx_offset": Json::number(
        header.bootstrap_rx_offset.to_double(),
      ),
      "bootstrap_rx_size": Json::number(header.bootstrap_rx_size.to_double()),
      "bootstrap_tx_offset": Json::number(
        header.bootstrap_tx_offset.to_double(),
      ),
      "bootstrap_tx_size": Json::number(header.bootstrap_tx_size.to_double()),
      "mailbox_rx_offset": Json::number(header.mailbox_rx_offset.to_double()),
      "mailbox_rx_size": Json::number(header.mailbox_rx_size.to_double()),
      "mailbox_tx_offset": Json::number(header.mailbox_tx_offset.to_double()),
      "mailbox_tx_size": Json::number(header.mailbox_tx_size.to_double()),
      "mailbox_protocols": Json::number(header.mailbox_protocols.to_double()),
      "firmware_version": Json::number(header.firmware_version.to_double()),
      "hardware_version": Json::number(header.hardware_version.to_double()),
      "production_date_raw": Json::number(
        header.production_date_raw.to_double(),
      ),
      "production_year": Json::number(header.production_year().to_double()),
      "production_weekday": Json::number(
        header.production_weekday().to_double(),
      ),
      "production_week": Json::number(header.production_week().to_double()),
      "esc_config_b_present": Json::boolean(header.esc_config_b_present),
      "pdi_control_1": Json::number(header.pdi_control_1.to_uint().to_double()),
      "esc_config_b0": Json::number(header.esc_config_b0.to_uint().to_double()),
      "pdi_config_1": Json::number(header.pdi_config_1.to_double()),
      "pdi_config_1_ext": Json::number(header.pdi_config_1_ext.to_double()),
      "esc_config_b4": Json::number(header.esc_config_b4.to_double()),
      "esc_config_b5": Json::number(header.esc_config_b5.to_double()),
      "esc_config_b6": Json::number(header.esc_config_b6.to_double()),
      "checksum_b": Json::number(header.checksum_b.to_double()),
    }),
    "supported_mailboxes": Json::object({
      "aoe": Json::boolean(header.supports_aoe()),
      "coe": Json::boolean(header.supports_coe()),
      "eoe": Json::boolean(header.supports_eoe()),
      "foe": Json::boolean(header.supports_foe()),
      "soe": Json::boolean(header.supports_soe()),
      "voe": Json::boolean(header.supports_voe()),
    }),
    "standard_metadata": Json::object({
      "eeprom_size_raw": Json::number(standard.eeprom_size_raw.to_double()),
      "eeprom_size_bytes": Json::number(
        standard.eeprom_size_bytes().to_double(),
      ),
      "version": Json::number(standard.version.to_double()),
    }),
    "general": general_json,
    "strings": Json::array(strings_json),
    "fmmu": Json::array(fmmu_json),
    "fmmu_ex": Json::array(fmmu_ex_json),
    "sync_managers": Json::array(sm_json),
    "sync_units": Json::array(sync_units_json),
    "dc_clocks": Json::array(dc_json),
    "timeouts": timeouts_json,
    "tx_pdo": Json::array(tx_pdo_json),
    "rx_pdo": Json::array(rx_pdo_json),
    "categories": Json::array(categories_json),
  })
}

///|
fn sii_category_title(
  category : @mailbox.SiiCategory,
  type_code : UInt,
) -> String {
  match category {
    Strings => "Strings"
    DataTypes => "DataTypes"
    General => "General"
    Fmmu => "FMMU"
    SyncManager => "SyncManager"
    FmmuEx => "FMMU_EX"
    SyncUnit => "SyncUnit"
    TxPdo => "TX PDO"
    RxPdo => "RX PDO"
    Dc => "DC CLOCK"
    Timeouts => "Timeouts"
    Dictionary => "Dictionary"
    Hardware => "Hardware"
    VendorInformation => "Vendor Information"
    Images => "Images"
    Raw => "Raw Category " + format_hex(type_code, 4)
  }
}

///|
fn append_sii_strings_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string(
    "  Size: " +
    entry.data.length().to_string() +
    " Bytes with " +
    strings.length().to_string() +
    " strings\n",
  )
  buf.write_string("  ID   Size (Bytes)    String\n")
  for i = 0; i < strings.length(); i = i + 1 {
    let text = strings[i]
    buf.write_string(
      "  " +
      (i + 1).to_string() +
      ": (" +
      text.length().to_string() +
      ") ......... '" +
      text +
      "'\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_general_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  info : @mailbox.SiiGeneral,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Vendor Specific (Index of String)\n")
  buf.write_string(
    "    Name  Index: " +
    info.name_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.name_idx) +
    "\n",
  )
  buf.write_string(
    "    Group Index: " +
    info.group_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.group_idx) +
    "\n",
  )
  buf.write_string(
    "    Image Index: " +
    info.image_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.image_idx) +
    "\n",
  )
  buf.write_string(
    "    Order Index: " +
    info.order_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.order_idx) +
    "\n\n",
  )
  buf.write_string("  CoE Details:\n")
  buf.write_string(
    "    Enable SDO: .................. " +
    bool_yes_no(info.supports_coe_sdo()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO Info: ............. " +
    bool_yes_no(info.supports_coe_sdo_info()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Assign: ........... " +
    bool_yes_no(info.supports_coe_pdo_assign()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Configuration: .... " +
    bool_yes_no(info.supports_coe_pdo_configuration()) +
    "\n",
  )
  buf.write_string(
    "    Enable Upload at Startup: .... " +
    bool_yes_no(info.supports_coe_upload_at_startup()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO complete access: .. " +
    bool_yes_no(info.supports_coe_complete_access()) +
    "\n",
  )
  buf.write_string(
    "  FoE Details: ................... " +
    bool_enabled_text(info.foe_supported) +
    "\n",
  )
  buf.write_string(
    "  EoE Details: ................... " +
    bool_enabled_text(info.eoe_supported) +
    "\n\n",
  )
  buf.write_string(
    "  Flag SafeOp: ................... " +
    bool_enabled_text(info.is_op_only()) +
    "\n",
  )
  buf.write_string(
    "  Flag notLRW: ................... " +
    bool_enabled_text(info.prefers_not_lrw()) +
    "\n",
  )
  buf.write_string(
    "  Flag MBox Data Link Layer ...... " +
    bool_enabled_text(info.supports_mailbox_data_link_layer()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident AL Status ........... " +
    bool_enabled_text(info.supports_identification_ado()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident Physical Memory ..... " +
    bool_enabled_text(info.supports_identification_physical_memory()) +
    "\n\n",
  )
  buf.write_string(
    "  CurrentOnEBus: ................. " +
    info.current_on_ebus.to_string() +
    " mA\n",
  )
  buf.write_string("\n  Physical Ports:\n")
  buf.write_string(
    "     Port 0: ..................... " +
    physical_port_name(info.physical_port_0) +
    "\n",
  )
  buf.write_string(
    "     Port 1: ..................... " +
    physical_port_name(info.physical_port_1) +
    "\n",
  )
  buf.write_string(
    "     Port 2: ..................... " +
    physical_port_name(info.physical_port_2) +
    "\n",
  )
  buf.write_string(
    "     Port 3: ..................... " +
    physical_port_name(info.physical_port_3) +
    "\n\n",
  )
  buf.write_string(
    "  Physical Memory Address ........ " +
    format_hex(info.physical_memory_address, 4) +
    "\n\n",
  )
}

///|
fn append_sii_fmmu_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu : Array[@mailbox.FmmuDirection],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of FMMUs: " + fmmu.length().to_string() + "\n")
  for i = 0; i < fmmu.length(); i = i + 1 {
    buf.write_string(
      "    FMMU" + i.to_string() + ": " + fmmu_usage_name(fmmu[i]) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_fmmu_ex_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu_ex : Array[@mailbox.SiiFmmuEx],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of FMMU_EX entries: " + fmmu_ex.length().to_string() + "\n",
  )
  for i = 0; i < fmmu_ex.length(); i = i + 1 {
    let current = fmmu_ex[i]
    buf.write_string("    FMMU" + i.to_string() + "\n")
    buf.write_string(
      "      opOnly: ............... " + bool_yes_no(current.op_only) + "\n",
    )
    buf.write_string(
      "      syncManager defined: .. " + bool_yes_no(current.sm_defined) + "\n",
    )
    buf.write_string(
      "      syncUnit defined: ..... " + bool_yes_no(current.su_defined) + "\n",
    )
    buf.write_string(
      "      syncManager index: .... " +
      current.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "      syncUnit index: ....... " +
      current.sync_unit.to_uint().to_string() +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_sm_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sms : Array[@mailbox.SiiSmEntry],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncManager: " + sms.length().to_string() + "\n",
  )
  for i = 0; i < sms.length(); i = i + 1 {
    let sm = sms[i]
    buf.write_string("  SyncManager SM" + i.to_string() + "\n")
    buf.write_string(
      "    Physical Startaddress: ... " +
      format_hex(sm.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "    Length: .................. " + sm.length.to_string() + "\n",
    )
    buf.write_string(
      "    Control Register: ........ " +
      format_hex(sm.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Status Register: ......... " +
      format_hex(sm.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Enable byte: ............. " +
      format_hex(sm.activate.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    SM Type: ................. " + sm_type_name(sm.sm_type) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_dc_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  dc : @mailbox.SiiDcClock,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Cycle Time 0 .................. " + dc.cycle_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 0 .................. " + dc.shift_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 1 .................. " + dc.shift_time_1.to_string() + "\n",
  )
  buf.write_string(
    "  Sync1 Cycle Factor ............ " +
    dc.sync1_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Assign Activate ............... " + dc.assign_activate.to_string() + "\n",
  )
  buf.write_string(
    "  Sync0 Cylce Factor ............ " +
    dc.sync0_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Name Index .................... " +
    dc.name_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.name_idx) +
    ")\n",
  )
  buf.write_string(
    "  Description Index ............. " +
    dc.description_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.description_idx) +
    ")\n\n",
  )
}

///|
fn append_sii_timeouts_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  timeouts : @mailbox.SiiTimeouts,
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  INIT -> PREOP/BOOT Timeout ... " +
    timeouts.preop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  SAFEOP -> OP Timeout ........ " +
    timeouts.safeop_op_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Back To INIT Timeout ........ " +
    timeouts.back_to_init_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  OP -> SAFEOP Timeout ........ " +
    timeouts.back_to_safeop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Request Timeout ..... " +
    timeouts.mailbox_request_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Response Timeout .... " +
    timeouts.mailbox_response_timeout_ms.to_string() +
    " ms\n\n",
  )
}

///|
fn append_sii_sync_unit_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sync_units : Array[@mailbox.SiiSyncUnit],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncUnits: " + sync_units.length().to_string() + "\n",
  )
  for i = 0; i < sync_units.length(); i = i + 1 {
    let current = sync_units[i]
    buf.write_string("    SyncUnit " + i.to_string() + "\n")
    buf.write_string(
      "      separateSu: ........... " + bool_yes_no(current.separate_su) + "\n",
    )
    buf.write_string(
      "      separateFrame: ........ " +
      bool_yes_no(current.separate_frame) +
      "\n",
    )
    buf.write_string(
      "      dependOnInputState: ... " +
      bool_yes_no(current.depend_on_input_state) +
      "\n",
    )
    buf.write_string(
      "      frameRepeatSupport: ... " +
      bool_yes_no(current.frame_repeat_support) +
      "\n",
    )
    buf.write_string(
      "      raw flags: ............ " +
      format_hex(current.raw_flags.to_uint(), 2) +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_pdo_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  pdos : Array[@mailbox.SiiPdo],
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of PDOs: " + pdos.length().to_string() + "\n")
  for i = 0; i < pdos.length(); i = i + 1 {
    let pdo = pdos[i]
    buf.write_string(
      "  PDO " +
      i.to_string() +
      ": index=" +
      format_hex(pdo.pdo_index, 4) +
      ", name=" +
      resolved_sii_string(strings, pdo.name_idx) +
      "\n",
    )
    buf.write_string(
      "    Sync Manager: ............ " +
      pdo.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Synchronization: ......... " +
      pdo.synchronization.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Entry Count: ............. " +
      pdo.entry_count.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Flags: ................... " + format_hex(pdo.flags, 4) + "\n",
    )
    for j = 0; j < pdo.entries.length(); j = j + 1 {
      let pdo_entry = pdo.entries[j]
      buf.write_string(
        "    Entry " +
        j.to_string() +
        ": " +
        format_hex(pdo_entry.entry_index, 4) +
        ":" +
        pdo_entry.subindex.to_uint().to_string() +
        " " +
        resolved_sii_string(strings, pdo_entry.name_idx) +
        " (" +
        pdo_entry.bit_length.to_uint().to_string() +
        " bits, type=" +
        format_hex(pdo_entry.data_type.to_uint(), 2) +
        ", flags=" +
        format_hex(pdo_entry.flags, 4) +
        ")\n",
      )
    }
  }
  buf.write_string("\n")
}

///|
fn append_sii_raw_category_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
) -> Unit {
  let category_class = entry.category_class().label()
  let (overlay_key, overlay_status, overlay_decoder) = match
    entry.overlay_candidate() {
    Some(candidate) =>
      (
        candidate.dispatch_key(),
        candidate.status_label(),
        match candidate.decoder_name() {
          Some(name) => name
          None => ""
        },
      )
    None => ("", "", "")
  }
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Class: " + category_class + "\n")
  if overlay_key != "" {
    buf.write_string("  Overlay Key: " + overlay_key + "\n")
    buf.write_string("  Overlay Status: " + overlay_status + "\n")
  }
  if overlay_decoder != "" {
    buf.write_string("  Overlay Decoder: " + overlay_decoder + "\n")
  }
  buf.write_string(
    "  Raw Preview: " + bytes_preview_hex(entry.data, 24) + "\n\n",
  )
}

///|
fn read_sii_text(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> String {
  let eeprom = sii.eeprom
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let categories = sii.categories
  let buf = @buffer.new(size_hint=2048)
  buf.write_string("First print preamble and config\n")
  buf.write_string(
    "Position: ................... " + position.to_string() + "\n",
  )
  buf.write_string(
    "Words requested: ............ " + word_count.to_string() + "\n",
  )
  buf.write_string(
    "Bytes read: ................. " + eeprom.length().to_string() + "\n",
  )
  buf.write_string("Preamble:\n")
  buf.write_string(
    "PDI Control: ................ " +
    format_hex(preamble.pdi_control, 4) +
    "\n",
  )
  buf.write_string(
    "PDI Config: ................. " + format_hex(preamble.pdi_config, 4) + "\n",
  )
  buf.write_string(
    "Sync Impulse Length: ........ " +
    preamble.sync_impulse_length_ns().to_string() +
    " ns (raw: " +
    format_hex(preamble.sync_impulse_length_raw, 4) +
    ")\n",
  )
  buf.write_string(
    "PDI Config 2: ............... " +
    format_hex(preamble.pdi_config2, 4) +
    "\n",
  )
  buf.write_string(
    "Configured Station Alias: ... " +
    format_hex(preamble.configured_station_alias, 4) +
    "\n",
  )
  buf.write_string(
    "Checksum of Preamble: ....... " +
    format_hex(preamble.checksum, 4) +
    " (" +
    (if preamble.checksum_ok { "ok" } else { "wrong" }) +
    ")\n\n",
  )
  buf.write_string("Identity:\n")
  buf.write_string(
    "  Vendor ID: ................ " + format_hex(header.vendor_id, 8) + "\n",
  )
  buf.write_string(
    "  Product ID: ............... " + format_hex(header.product_code, 8) + "\n",
  )
  buf.write_string(
    "  Revision ID: .............. " + format_hex(header.revision, 8) + "\n",
  )
  buf.write_string(
    "  Serial Number: ............ " + format_hex(header.serial, 8) + "\n\n",
  )
  buf.write_string("Default mailbox settings:\n")
  buf.write_string("  Bootstrap Mailbox:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.bootstrap_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " +
    header.bootstrap_rx_size.to_string() +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.bootstrap_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.bootstrap_tx_size.to_string() +
    "\n",
  )
  buf.write_string("\n  Mailbox Settings:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.mailbox_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " + header.mailbox_rx_size.to_string() + "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.mailbox_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.mailbox_tx_size.to_string() +
    "\n\n",
  )
  buf.write_string("Supported Mailboxes:\n")
  buf.write_string(
    "  AoE ....................... " +
    bool_true_false(header.supports_aoe()) +
    "\n",
  )
  buf.write_string(
    "  CoE ....................... " +
    bool_true_false(header.supports_coe()) +
    "\n",
  )
  buf.write_string(
    "  EoE ....................... " +
    bool_true_false(header.supports_eoe()) +
    "\n",
  )
  buf.write_string(
    "  FoE ....................... " +
    bool_true_false(header.supports_foe()) +
    "\n",
  )
  buf.write_string(
    "  SoE ....................... " +
    bool_true_false(header.supports_soe()) +
    "\n",
  )
  buf.write_string(
    "  VoE ....................... " +
    bool_true_false(header.supports_voe()) +
    "\n\n",
  )
  buf.write_string("Vendor Info:\n")
  buf.write_string(
    "  Firmware Version: ......... " +
    format_hex(header.firmware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Hardware Version: ......... " +
    format_hex(header.hardware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Date Raw: ...... " +
    format_hex(header.production_date_raw, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Year: .......... " +
    header.production_year().to_string() +
    "\n",
  )
  buf.write_string(
    "  Production Weekday: ....... " +
    production_weekday_name(header.production_weekday()) +
    "\n",
  )
  buf.write_string(
    "  Production Week: .......... " +
    header.production_week().to_string() +
    "\n\n",
  )
  buf.write_string("ESC Configuration Area B:\n")
  buf.write_string(
    "  Present: .................. " +
    bool_yes_no(header.esc_config_b_present) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Control: ............. " +
    format_hex(header.pdi_control_1.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B0: ............ " +
    format_hex(header.esc_config_b0.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Configuration: ....... " + format_hex(header.pdi_config_1, 4) + "\n",
  )
  buf.write_string(
    "  Extended PDI1 Config: ..... " +
    format_hex(header.pdi_config_1_ext, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B4: ............ " +
    format_hex(header.esc_config_b4, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B5: ............ " +
    format_hex(header.esc_config_b5, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B6: ............ " +
    format_hex(header.esc_config_b6, 4) +
    "\n",
  )
  buf.write_string(
    "  Checksum B: ............... " + format_hex(header.checksum_b, 4) + "\n\n",
  )
  buf.write_string(
    "EEPROM size: ................ " +
    standard.eeprom_size_bytes().to_string() +
    " bytes\n",
  )
  buf.write_string(
    "Version: .................... " + standard.version.to_string() + "\n\n",
  )
  let fmmu = sii.fmmu
  let fmmu_ex = sii.fmmu_ex
  let sync_managers = sii.sync_managers
  let sync_units = sii.sync_units
  let mut dc_index = 0
  for entry in categories {
    match entry.category {
      Strings => append_sii_strings_section(buf, entry, strings)
      DataTypes => append_sii_raw_category_section(buf, entry)
      General =>
        match general {
          Some(info) => append_sii_general_section(buf, entry, info, strings)
          None => ()
        }
      Fmmu => append_sii_fmmu_section(buf, entry, fmmu)
      FmmuEx => append_sii_fmmu_ex_section(buf, entry, fmmu_ex)
      SyncManager => append_sii_sm_section(buf, entry, sync_managers)
      SyncUnit => append_sii_sync_unit_section(buf, entry, sync_units)
      TxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      RxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      Dc =>
        if dc_index < sii.dc_clocks.length() {
          append_sii_dc_section(buf, entry, sii.dc_clocks[dc_index], strings)
          dc_index = dc_index + 1
        }
      Timeouts =>
        match sii.timeouts {
          Some(timeouts) => append_sii_timeouts_section(buf, entry, timeouts)
          None => ()
        }
      Dictionary => append_sii_raw_category_section(buf, entry)
      Hardware => append_sii_raw_category_section(buf, entry)
      VendorInformation => append_sii_raw_category_section(buf, entry)
      Images => append_sii_raw_category_section(buf, entry)
      Raw => append_sii_raw_category_section(buf, entry)
    }
  }
  buf.to_string()
}
