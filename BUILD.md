# Build Issues and Solutions

## Prerequisites

Check that you have **DashSync** repo next to the wallet repo.

Make sure you're on the **master** branch for both DashSync and DashWallet.

### Clang Version Check

Check clang version:

```bash
clang++ --version
```

If you see homebrew version, this might cause issues with building. You need to switch to system version.

```
❌ InstalledDir: /opt/homebrew/opt/llvm/bin
✅ InstalledDir: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
```

To unplug homebrew version, comment out the following in `~/.zshrc` or `~/.zsh_profile` (or `~/.bashrc` if you're using bash):

```bash
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
```

## Required Dependencies

Install the following dependencies:

- **cmake** (version 3.28.3 recommended)
- **cbindgen**
- **rust**

> **Note:** cmake higher than 3.5.0 might cause issues with building. Version 3.28.3 is tested and works.
> 
> Download from: https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-macos-universal.dmg

### Installation Commands

```bash
# Install CMake
sudo "/Applications/CMake.app/Contents/bin/cmake-gui" --install

# Install cbindgen
brew install cbindgen

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
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

### Issue 1: CBind Generation Error

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

### Issue 2: Git Repository Error with DAPI-GRPC

**Error:**
```
Installing DAPI-GRPC (0.22.0-dev.8)
 > Git download
     $ /usr/bin/git clone https://github.com/dashevo/dashsync-iOS.git
     ...
   fatal: not a git repository (or any of the parent directories): .git
```

**Solution:** Downgrade CocoaPods to version 1.15.2. This might require upgrading Ruby to version 3.3.0 or higher:

```bash
# Install Ruby
brew install ruby

# Install specific CocoaPods version
sudo gem install cocoapods -v 1.15.2
```

**Alternative installation:**
```bash
sudo /opt/homebrew/opt/ruby/bin/gem install -n /usr/local/bin cocoapods -v 1.15.2
```

---

### Issue 3: 'dash_shared_core.h' file not found

**Problem:** dash-shared-core was not compiled properly due to various potential reasons.

**Solution:** Check the build log for more details. Usually caused by missing dependencies (see above).

## dash-shared-core Development

If you want to make modifications to dash-shared-core, follow these steps:

### Setup Steps

1. **Place dash-shared-core in the correct location:**
   Put dash-shared-core in the same directory as the wallet repo.

2. **Remove DashSharedCore from DashSync.podspec:**
   ```ruby
   # s.dependency 'DashSharedCore', '0.5.1'
   ```

3. **Add local dash-shared-core to Podfile:**
   In the wallet or DashSync example Podfile, add:
   ```ruby
   pod 'DashSharedCore', :path => '../dash-shared-core/'
   ```