///|
test "topology_fingerprint: deterministic for identical scan" {
  let scan : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x02U,
        product_code: 0x044C2C52U,
        revision: 0x00120000U,
        serial: 0x00000001U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x02U,
        product_code: 0x04562C52U,
        revision: 0x00120000U,
        serial: 0x00000002U,
        identification: 0U,
      },
    ],
  }
  let fp1 = @runtime.topology_fingerprint(scan)
  let fp2 = @runtime.topology_fingerprint(scan)
  assert_eq(fp1, fp2)
  assert_eq(fp1.slave_count, 2)
}

///|
test "topology_fingerprint: different slaves produce different hash" {
  let scan_a : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x02U,
        product_code: 0x044C2C52U,
        revision: 0x00120000U,
        serial: 0x00000001U,
        identification: 0U,
      },
    ],
  }
  let scan_b : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x03U,
        product_code: 0x044C2C52U,
        revision: 0x00120000U,
        serial: 0x00000001U,
        identification: 0U,
      },
    ],
  }
  let fp_a = @runtime.topology_fingerprint(scan_a)
  let fp_b = @runtime.topology_fingerprint(scan_b)
  assert_true(fp_a != fp_b)
}

///|
test "fingerprint_match: identical" {
  let fp : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  assert_eq(
    @runtime.fingerprint_match(fp, fp),
    @runtime.TopologyFingerprintMatch::Identical,
  )
}

///|
test "fingerprint_match: slave count changed" {
  let fp_a : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let fp_b : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 12345L,
  }
  assert_true(
    @runtime.fingerprint_match(fp_a, fp_b)
    is SlaveCountChanged(expected=2, actual=3),
  )
}

///|
test "fingerprint_match: identity changed" {
  let fp_a : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let fp_b : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 99999L,
  }
  assert_eq(
    @runtime.fingerprint_match(fp_a, fp_b),
    @runtime.TopologyFingerprintMatch::IdentityChanged,
  )
}

///|
test "topology_fingerprint_from_config: matches scan fingerprint" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x02U,
        product_code: 0x044C2C52U,
        revision: 0x00120000U,
        serial: 0x00000001U,
        identification: 0U,
      },
    ],
  }
  let config = @runtime.configuration_from_scan(scan)
  let fp_scan = @runtime.topology_fingerprint(scan)
  let fp_config = @runtime.topology_fingerprint_from_config(config)
  assert_eq(fp_scan, fp_config)
}

///|
test "topology_fingerprint: empty scan" {
  let scan : @runtime.ScanReport = { slave_count: 0, slaves: [] }
  let fp = @runtime.topology_fingerprint(scan)
  assert_eq(fp.slave_count, 0)
  assert_eq(
    @runtime.fingerprint_match(fp, fp),
    @runtime.TopologyFingerprintMatch::Identical,
  )
}

///|
test "topology_fingerprint: position order independent of array order" {
  let slave_a : @runtime.SlaveReport = {
    position: 0,
    station_address: 0x1001U,
    alias_address: None,
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x00120000U,
    serial: 0x00000001U,
    identification: 0U,
  }
  let slave_b : @runtime.SlaveReport = {
    position: 1,
    station_address: 0x1002U,
    alias_address: None,
    vendor_id: 0x03U,
    product_code: 0x055D3D63U,
    revision: 0x00130000U,
    serial: 0x00000002U,
    identification: 0U,
  }
  let scan_ab : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [slave_a, slave_b],
  }
  let scan_ba : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [slave_b, slave_a],
  }
  assert_eq(
    @runtime.topology_fingerprint(scan_ab),
    @runtime.topology_fingerprint(scan_ba),
  )
}
