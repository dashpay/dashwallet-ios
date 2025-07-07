# Build Issues and Solutions

## Prerequisites

Check that you have **DashSync** repo next to the wallet repo. If fixing issues with **dash-shared-core** (e.g. CoinJoin), you'll need it next to the wallet repo as well.

Make sure you're on the **master** branch for both DashSync and DashWallet.

## Required Dependencies

Install the following dependencies:

### Install via Homebrew
```bash
brew install cmake
brew install cbindgen
brew install rust
```

### Xcode Setup
```bash
xcode-select --install
sudo xcodebuild -license accept
```

### Pod Installation
Run from the wallet directory:
```bash
pod install --verbose
```

## Potential Issues and Solutions

### 1: 'dash_shared_core.h' file not found

**Problem:** dash-shared-core was not compiled properly due to various potential reasons.

**Solution:** Check the build log for more details. Usually caused by missing dependencies (see below).

---

### 2: CBind Generation Error

**Error:**
```
Compiling rs-merk-verify-c-binding v0.1.3 (https://github.com/dashpay/rs-merk-verify-c-binding?branch=for-use-in-main-crate#930aeb2a)
error: failed to run custom build command for `dash-spv-coinjoin v0.1.0 (/Users/username/Development/dash-shared-core/dash-spv-coinjoin)`
```

**Solution:** Install cbindgen if not already installed:
```bash
brew install cbindgen
```

---

### 3: Git Repository Error with DAPI-GRPC

**Error:**
```
Installing DAPI-GRPC (0.22.0-dev.8)
 > Git download
     $ /usr/bin/git clone https://github.com/dashevo/dashsync-iOS.git
     ...
   fatal: not a git repository (or any of the parent directories): .git
```

**Solution:** Downgrade CocoaPods to version 1.15.2:
```bash
gem install cocoapods -v 1.15.2
```
