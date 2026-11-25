"""Compile a Swift helper of the localization tools once, for the macOS host.

The helper is cached outside the repository under a name that carries its source digest. The
compile targets the macOS SDK whatever SDK the caller's environment names: the build's sync phase
runs inside an iOS target, where Xcode exports `SDKROOT` as the iPhoneSimulator SDK.
"""
import hashlib
import os
import subprocess


class SwiftHelperError(Exception):
    pass


def host_binary(source, cache_variable, cache_name, prefix):
    """Path of `source` compiled for the macOS host; cache in $cache_variable or ~/Library/Caches/cache_name."""
    with open(source, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()[:16]
    cache = os.environ.get(cache_variable) or os.path.join(
        os.path.expanduser("~"), "Library", "Caches", cache_name)
    binary = os.path.join(cache, prefix + digest)
    if not os.path.exists(binary):
        os.makedirs(cache, exist_ok=True)
        partial = "%s.%d.tmp" % (binary, os.getpid())
        environment = {k: v for k, v in os.environ.items() if k != "SDKROOT"}
        res = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-O", "-o", partial, source],
                             capture_output=True, text=True, env=environment)
        if res.returncode != 0:
            raise SwiftHelperError("cannot compile %s:\n%s" % (source, res.stderr))
        os.replace(partial, binary)
    return binary
