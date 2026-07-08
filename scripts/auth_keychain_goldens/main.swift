//
//  C7 auth goldens — PinCodec byte fixtures (frozen from a live
//  DashSync-written keychain, see goldens.txt) + the LockoutPolicy table.
//

import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("OK   \(label)")
    } else {
        failures += 1
        print("FAIL \(label)")
    }
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func data(fromHex string: String) -> Data {
    var out = Data()
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(index, offsetBy: 2)
        out.append(UInt8(string[index..<next], radix: 16)!)
        index = next
    }
    return out
}

// MARK: PinCodec vs frozen bytes (goldens.txt)

// pin "1111" → 31313131 (UTF-8, no BOM, no length prefix)
check(hex(PinCodec.encode(string: "1111")) == "31313131", "pin encode == golden 31313131")
check(PinCodec.decodeString(data(fromHex: "31313131")) == "1111", "pin decode golden -> \"1111\"")

// int64 zero → 8 zero bytes
check(hex(PinCodec.encode(int64: 0)) == "0000000000000000", "int64 0 encode == golden")
check(PinCodec.decodeInt64(data(fromHex: "0000000000000000")) == 0, "int64 0 decode")

// USES_AUTHENTICATION == 1 → 0100000000000000 (the endianness witness)
check(hex(PinCodec.encode(int64: 1)) == "0100000000000000", "int64 1 encode little-endian == golden")
check(PinCodec.decodeInt64(data(fromHex: "0100000000000000")) == 1, "int64 1 decode")

// BIOMETRIC_ALLOWED_AMOUNT_LEFT == UINT64_MAX → ffffffffffffffff
check(hex(PinCodec.encode(int64: Int64(bitPattern: UInt64.max))) == "ffffffffffffffff",
      "uint64 max encode == golden")
check(PinCodec.decodeInt64(data(fromHex: "ffffffffffffffff")).map { UInt64(bitPattern: $0) } == UInt64.max,
      "uint64 max decode")

// Round-trip a non-symmetric value to pin down byte order unambiguously.
check(hex(PinCodec.encode(int64: 0x0102030405060708)) == "0807060504030201",
      "int64 multi-byte little-endian layout")
check(PinCodec.decodeInt64(data(fromHex: "0807060504030201")) == 0x0102030405060708,
      "int64 multi-byte round-trip")

// Length guard: only exactly-8-byte payloads decode.
check(PinCodec.decodeInt64(data(fromHex: "01020304")) == nil, "short int64 payload rejected")

// MARK: LockoutPolicy table
// wait = failHeight + 6^(failCount−3)·60 − secureTime  (DSAuthenticationManager.m:241)

let height: TimeInterval = 1_000_000
let now: TimeInterval = 1_000_000 // secureTime == failHeight → wait == pure backoff

check(LockoutPolicy.waitTime(failCount: 0, failHeight: height, secureTime: now) == 0, "count 0 -> no lockout")
check(LockoutPolicy.waitTime(failCount: 2, failHeight: height, secureTime: now) == 0, "count 2 -> no lockout")
check(LockoutPolicy.waitTime(failCount: 3, failHeight: height, secureTime: now) == 60, "count 3 -> 60 s")
check(LockoutPolicy.waitTime(failCount: 4, failHeight: height, secureTime: now) == 360, "count 4 -> 6 min")
check(LockoutPolicy.waitTime(failCount: 5, failHeight: height, secureTime: now) == 2_160, "count 5 -> 36 min")
check(LockoutPolicy.waitTime(failCount: 6, failHeight: height, secureTime: now) == 12_960, "count 6 -> 3.6 h")
check(LockoutPolicy.waitTime(failCount: 7, failHeight: height, secureTime: now) == 77_760, "count 7 -> 21.6 h")

// The clock elapses the wait: secureTime past the backoff → non-positive.
check(LockoutPolicy.waitTime(failCount: 4, failHeight: height, secureTime: height + 360) <= 0,
      "count 4 fully elapsed -> unlocked")
check(LockoutPolicy.waitTime(failCount: 4, failHeight: height, secureTime: height + 100) == 260,
      "count 4 partially elapsed -> 260 s left")

// Constants pinned to the pod's.
check(LockoutPolicy.allowedFailCount == 3 && LockoutPolicy.maxFailCount == 8 && LockoutPolicy.pinLength == 4,
      "constants: 3 free attempts, permanent at 8, 4-digit PIN")

if failures > 0 {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
print("\nALL AUTH GOLDENS PASS")
