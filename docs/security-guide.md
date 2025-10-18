# Security

### Checksum Verification

The action automatically verifies SHA256 checksums for downloaded releases to ensure integrity and security:

**How it works:**
1. **Auto-discovers checksum files** from GitHub release assets
2. **Supports common formats**: `*.sha256`, `*.sha256sum`, `SHA256SUMS`, `checksums.txt`
3. **Verifies before extraction**: Prevents building from corrupted or tampered files
4. **Fails on mismatch**: Build stops if checksum doesn't match
5. **Graceful fallback**: Continues if no checksum file is available (with info message)

**Example output:**
```
ℹ️  Found checksum file: SHA256SUMS
ℹ️  Verifying checksum...
✅ Checksum verified: uv-x86_64-unknown-linux-gnu.tar.gz
```

**Failure behavior:**
```
❌ ERROR: Checksum verification failed for uv-x86_64-unknown-linux-gnu.tar.gz

Expected: abc123...
Actual:   def456...

The downloaded file may be corrupted or tampered with.
```

This feature provides automatic supply chain security without any configuration required.
