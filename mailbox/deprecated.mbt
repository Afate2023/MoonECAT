///|
/// Deprecated: replaced by single-pass dispatch in parse_sii_full_info.
/// Kept for whitebox test coverage.
fn collect_sii_strings(categories : Array[SiiCategoryEntry]) -> Array[String] {
  for category in categories {
    if category.category == Strings {
      return parse_sii_strings(category.data)
    }
  }
  []
}

///|
fn collect_sii_general(categories : Array[SiiCategoryEntry]) -> SiiGeneral? {
  for category in categories {
    if category.category == General {
      let parsed : Result[SiiGeneral, Error] = try? parse_sii_general(
        category.data,
      )
      match parsed {
        Ok(general) => return Some(general)
        Err(_) => ()
      }
    }
  }
  None
}

///|
fn collect_sii_timeouts(categories : Array[SiiCategoryEntry]) -> SiiTimeouts? {
  for category in categories {
    if category.category == Timeouts {
      let parsed : Result[SiiTimeouts, Error] = try? parse_sii_timeouts(
        category.data,
      )
      match parsed {
        Ok(timeouts) => return Some(timeouts)
        Err(_) => ()
      }
    }
  }
  None
}

///|
fn collect_sii_fmmu(
  categories : Array[SiiCategoryEntry],
) -> Array[FmmuDirection] {
  for category in categories {
    if category.category == Fmmu {
      return parse_sii_fmmu(category.data)
    }
  }
  []
}

///|
fn collect_sii_fmmu_ex(
  categories : Array[SiiCategoryEntry],
) -> Array[SiiFmmuEx] {
  for category in categories {
    if category.category == FmmuEx {
      return parse_sii_fmmu_ex(category.data)
    }
  }
  []
}

///|
fn collect_sii_sync_managers(
  categories : Array[SiiCategoryEntry],
) -> Array[SiiSmEntry] {
  for category in categories {
    if category.category == SyncManager {
      return parse_sii_sm(category.data)
    }
  }
  []
}

///|
fn collect_sii_sync_units(
  categories : Array[SiiCategoryEntry],
) -> Array[SiiSyncUnit] {
  for category in categories {
    if category.category == SyncUnit {
      return parse_sii_sync_units(category.data)
    }
  }
  []
}

///|
fn collect_sii_pdo(
  categories : Array[SiiCategoryEntry],
  target : SiiCategory,
) -> Array[SiiPdo] {
  let pdos : Array[SiiPdo] = []
  for category in categories {
    if category.category == target {
      for pdo in parse_sii_pdo(category.data) {
        pdos.push(pdo)
      }
    }
  }
  pdos
}

///|
fn collect_sii_dc(categories : Array[SiiCategoryEntry]) -> Array[SiiDcClock] {
  let dc_clocks : Array[SiiDcClock] = []
  for category in categories {
    if category.category == Dc {
      let parsed : Result[SiiDcClock, Error] = try? parse_sii_dc(category.data)
      match parsed {
        Ok(clock) => dc_clocks.push(clock)
        Err(_) => ()
      }
    }
  }
  dc_clocks
}
