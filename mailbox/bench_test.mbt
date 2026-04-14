///|
/// Benchmark: SII EEPROM parsing at various granularities.
test "bench: SII parsing pipeline" (b : @bench.T) {
  let eeprom = @fixtures.sample_sii_eeprom()
  b.bench(name="parse_sii_preamble", fn() {
    b.keep(@mailbox.parse_sii_preamble(eeprom) catch { _ => panic() })
  })
  b.bench(name="parse_sii_header", fn() {
    b.keep(@mailbox.parse_sii_header(eeprom) catch { _ => panic() })
  })
  b.bench(name="parse_sii_categories", fn() {
    b.keep(@mailbox.parse_sii_categories(eeprom))
  })
  b.bench(name="parse_sii_full_info", fn() {
    b.keep(@mailbox.parse_sii_full_info(eeprom) catch { _ => panic() })
  })
}

///|
/// Benchmark: Individual sub-parser performance (isolated from full_info).
test "bench: SII sub-parsers isolated" (b : @bench.T) {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  let categories = @mailbox.parse_sii_categories(eeprom)
  // Find specific categories for isolated benchmarks
  let mut strings_data : BytesView = b""[:]
  let mut general_data : BytesView = b""[:]
  let mut fmmu_data : BytesView = b""[:]
  let mut sm_data : BytesView = b""[:]
  let mut pdo_data : BytesView = b""[:]
  for cat in categories {
    match cat.category {
      Strings => strings_data = cat.data
      General => general_data = cat.data
      Fmmu => fmmu_data = cat.data
      SyncManager => sm_data = cat.data
      TxPdo => pdo_data = cat.data
      _ => ()
    }
  }
  if strings_data.length() > 0 {
    b.bench(name="parse_sii_strings", fn() {
      b.keep(@mailbox.parse_sii_strings(strings_data))
    })
  }
  if general_data.length() > 0 {
    b.bench(name="parse_sii_general", fn() {
      b.keep(@mailbox.parse_sii_general(general_data) catch { _ => panic() })
    })
  }
  if fmmu_data.length() > 0 {
    b.bench(name="parse_sii_fmmu", fn() {
      b.keep(@mailbox.parse_sii_fmmu(fmmu_data))
    })
  }
  if sm_data.length() > 0 {
    b.bench(name="parse_sii_sm", fn() { b.keep(@mailbox.parse_sii_sm(sm_data)) })
  }
  if pdo_data.length() > 0 {
    b.bench(name="parse_sii_pdo", fn() {
      b.keep(@mailbox.parse_sii_pdo(pdo_data))
    })
  }
  b.bench(name="parse_sii_standard_metadata", fn() {
    b.keep(@mailbox.parse_sii_standard_metadata(eeprom) catch { _ => panic() })
  })
}

///|
/// Benchmark: SII parsing with process-data EEPROM (more categories).
test "bench: SII full parse with PDO categories" (b : @bench.T) {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  b.bench(name="parse_sii_full_info_with_pdo", fn() {
    b.keep(@mailbox.parse_sii_full_info(eeprom) catch { _ => panic() })
  })
}

///|
/// Benchmark: FMMU and SM mapping calculation.
test "bench: FMMU/SM mapping calculation" (b : @bench.T) {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  // Pre-parse SII for isolated mapping benchmark
  let sii = @mailbox.parse_sii_full_info(eeprom)
  b.bench(name="calculate_sm_configs", fn() {
    b.keep(@mailbox.calculate_sm_configs(sii.header, sii.sync_managers))
  })
  let sm_configs = @mailbox.calculate_sm_configs(sii.header, sii.sync_managers)
  let sm_patched = @mailbox.apply_pdo_lengths_to_sm_configs(
    sm_configs,
    sii.tx_pdo,
    sii.rx_pdo,
  )
  b.bench(name="calculate_fmmu_configs", fn() {
    b.keep(@mailbox.calculate_fmmu_configs(sii.fmmu, sm_patched, 0x1000U))
  })
  // Full pipeline: raw EEPROM → complete SlaveMapping
  b.bench(name="calculate_slave_mapping_full", fn() {
    b.keep(
      @mailbox.calculate_slave_mapping(eeprom, 0x1000U) catch {
        _ => panic()
      },
    )
  })
}

///|
/// Benchmark: SmConfig and FmmuConfig serialization to bytes.
test "bench: SM/FMMU config to_bytes" (b : @bench.T) {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  let mapping = @mailbox.calculate_slave_mapping(eeprom, 0x1000U)
  if mapping.sm_configs.length() > 0 {
    let sm = mapping.sm_configs[0]
    b.bench(name="sm_config_to_bytes", fn() { b.keep(sm.to_bytes()) })
  }
  if mapping.fmmu_configs.length() > 0 {
    let fmmu = mapping.fmmu_configs[0]
    b.bench(name="fmmu_config_to_bytes", fn() { b.keep(fmmu.to_bytes()) })
  }
}
