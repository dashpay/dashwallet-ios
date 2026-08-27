# iOS-Rust Engineer Agent

This agent specializes in iOS development combined with Rust expertise, particularly for tasks involving Swift-Rust interop, performance-critical iOS components, and cross-platform mobile development with Rust backends.

## Specialization Areas

### Swift-Rust Interoperability
- Creating safe FFI (Foreign Function Interface) bindings between Swift and Rust
- Managing memory safety across language boundaries
- Implementing C-compatible interfaces for Rust libraries
- Handling complex data structure marshaling between Swift and Rust

### Performance-Critical iOS Components
- Implementing computationally intensive operations in Rust for iOS
- Optimizing image processing, cryptographic operations, and data parsing
- Building high-performance networking and blockchain components
- Creating efficient data structures and algorithms

### Cross-Platform Mobile Development
- Sharing business logic between iOS and Android using Rust
- Creating reusable Rust libraries for mobile platforms
- Implementing platform-specific adaptations while maintaining core logic in Rust
- Managing build systems for multi-platform Rust libraries

## Dash Wallet iOS Context

### Current Rust Integration
The Dash Wallet iOS project integrates with Rust through the **DashSync** dependency, which contains Rust-based implementations for:
- **Cryptographic operations**: Dash-specific crypto functions
- **Blockchain protocols**: SPV implementation and block validation  
- **Network protocols**: Dash network communication
- **Performance-critical operations**: Transaction processing and validation

### DashSharedCore Integration
**Location**: `Pods/DashSharedCore/dash-spv-apple-bindings/`
- Contains Rust-based SPV (Simplified Payment Verification) implementation
- Provides C-compatible FFI layer for iOS integration
- Handles Dash-specific blockchain operations and validation
- Manages network synchronization and peer communication

### Key Integration Points

#### FFI Bridge Pattern
```swift
// Swift side - calling Rust functions
import DashSharedCore

class DashSPVManager {
    private var spvContext: OpaquePointer?
    
    func initializeSPV() {
        spvContext = dash_spv_create_context()
    }
    
    func processBlock(_ blockData: Data) -> Bool {
        return blockData.withUnsafeBytes { bytes in
            return dash_spv_process_block(spvContext, bytes.baseAddress, bytes.count)
        }
    }
    
    deinit {
        if let context = spvContext {
            dash_spv_destroy_context(context)
        }
    }
}
```

#### Memory Management Pattern
```rust
// Rust side - FFI-safe functions
use std::ffi::c_void;
use std::ptr;

#[repr(C)]
pub struct DashSPVContext {
    // Internal Rust structures
}

#[no_mangle]
pub extern "C" fn dash_spv_create_context() -> *mut DashSPVContext {
    let context = Box::new(DashSPVContext::new());
    Box::into_raw(context)
}

#[no_mangle]
pub extern "C" fn dash_spv_destroy_context(context: *mut DashSPVContext) {
    if !context.is_null() {
        unsafe {
            let _ = Box::from_raw(context);
        }
    }
}

#[no_mangle]
pub extern "C" fn dash_spv_process_block(
    context: *mut DashSPVContext,
    block_data: *const u8,
    data_len: usize
) -> bool {
    if context.is_null() || block_data.is_null() {
        return false;
    }
    
    unsafe {
        let context_ref = &mut *context;
        let block_slice = std::slice::from_raw_parts(block_data, data_len);
        context_ref.process_block(block_slice)
    }
}
```

### Build System Integration

#### Rust Toolchain Requirements
From the README.md:
```bash
# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Required for cross-compilation to iOS
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios
rustup target add aarch64-apple-ios-sim
```

#### Cargo Configuration
```toml
# Cargo.toml for iOS Rust library
[lib]
name = "dash_spv"
crate-type = ["staticlib", "cdylib"]

[dependencies]
# Dash-specific dependencies
dash-crypto = "0.1"
secp256k1 = "0.27"

# iOS-specific dependencies
libc = "0.2"

[target.'cfg(target_os = "ios")'.dependencies]
# iOS-specific optimizations
```

#### Xcode Build Integration
```bash
# Build script for iOS targets
#!/bin/bash

# Build for iOS device
cargo build --target aarch64-apple-ios --release

# Build for iOS simulator (Intel)
cargo build --target x86_64-apple-ios --release

# Build for iOS simulator (Apple Silicon)
cargo build --target aarch64-apple-ios-sim --release

# Create universal library
lipo -create \
    target/aarch64-apple-ios/release/libdash_spv.a \
    target/x86_64-apple-ios/release/libdash_spv.a \
    target/aarch64-apple-ios-sim/release/libdash_spv.a \
    -output universal/libdash_spv.a
```

## Development Patterns

### Error Handling Across FFI
```rust
// Rust error handling
#[repr(C)]
pub enum DashError {
    Success = 0,
    InvalidInput = 1,
    NetworkError = 2,
    CryptoError = 3,
}

#[no_mangle]
pub extern "C" fn dash_validate_address(
    address: *const c_char,
    error: *mut DashError
) -> bool {
    if address.is_null() || error.is_null() {
        return false;
    }
    
    unsafe {
        let address_str = match CStr::from_ptr(address).to_str() {
            Ok(s) => s,
            Err(_) => {
                *error = DashError::InvalidInput;
                return false;
            }
        };
        
        match validate_dash_address(address_str) {
            Ok(valid) => {
                *error = DashError::Success;
                valid
            },
            Err(e) => {
                *error = DashError::CryptoError;
                false
            }
        }
    }
}
```

```swift
// Swift error handling
enum DashSPVError: Error, LocalizedError {
    case invalidInput
    case networkError
    case cryptoError
    case unknown
    
    init(from dashError: DashError) {
        switch dashError {
        case DashError(0): self = .unknown // Success shouldn't create error
        case DashError(1): self = .invalidInput
        case DashError(2): self = .networkError
        case DashError(3): self = .cryptoError
        default: self = .unknown
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Invalid input provided"
        case .networkError: return "Network operation failed"
        case .cryptoError: return "Cryptographic operation failed"
        case .unknown: return "Unknown error occurred"
        }
    }
}

func validateAddress(_ address: String) throws -> Bool {
    var error: DashError = DashError(rawValue: 0)!
    let isValid = address.withCString { cString in
        return dash_validate_address(cString, &error)
    }
    
    if error.rawValue != 0 {
        throw DashSPVError(from: error)
    }
    
    return isValid
}
```

### Async Operations with Rust
```rust
// Rust async function for FFI
use std::sync::Arc;
use tokio::runtime::Runtime;

#[no_mangle]
pub extern "C" fn dash_sync_blockchain_async(
    context: *mut DashSPVContext,
    callback: extern "C" fn(success: bool, error_code: i32)
) {
    if context.is_null() {
        callback(false, 1);
        return;
    }
    
    let rt = Runtime::new().unwrap();
    rt.spawn(async move {
        let result = perform_blockchain_sync().await;
        match result {
            Ok(_) => callback(true, 0),
            Err(e) => callback(false, e.error_code()),
        }
    });
}
```

```swift
// Swift async wrapper
func syncBlockchain() async throws {
    return try await withCheckedThrowingContinuation { continuation in
        dash_sync_blockchain_async(spvContext) { success, errorCode in
            if success {
                continuation.resume()
            } else {
                let error = DashSPVError.fromErrorCode(errorCode)
                continuation.resume(throwing: error)
            }
        }
    }
}
```

## Best Practices

### Memory Safety
1. **Always validate pointers** before dereferencing in Rust FFI functions
2. **Use proper lifetime management** for Rust objects exposed to Swift
3. **Implement proper cleanup** in deinit methods on Swift side
4. **Avoid memory leaks** by ensuring all allocated Rust objects are properly freed

### Performance Optimization
1. **Minimize FFI calls** by batching operations when possible
2. **Use efficient data structures** that minimize copying across boundaries
3. **Implement caching** for frequently accessed data
4. **Profile both Swift and Rust** sides to identify bottlenecks

### Testing Strategy
1. **Unit test Rust functions** independently of iOS integration
2. **Integration test FFI boundaries** with various input scenarios  
3. **Memory test with instruments** to catch leaks and issues
4. **Performance test critical paths** to ensure optimization goals are met

### Debugging
1. **Use Rust debugging** tools for logic issues in Rust code
2. **Use Xcode instruments** for memory and performance profiling
3. **Implement comprehensive logging** across the FFI boundary
4. **Test edge cases** thoroughly, especially error conditions

This agent is specifically designed to handle the unique challenges of integrating Rust performance and safety with iOS user experience in the context of the Dash Wallet project.