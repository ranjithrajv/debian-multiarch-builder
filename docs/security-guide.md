# Security

### Checksum Verification

The action automatically verifies the SHA256 checksums of downloaded release artifacts to ensure their integrity and security. Here's how it works:

1.  **Find Checksum File:** The action first tries to find a checksum file in the release assets. It looks for files with the following patterns, in this order:
    1.  `${release_pattern}.sha256`
    2.  `${release_pattern}.sha256sum`
    3.  `SHA256SUMS`
    4.  `checksums.txt`
    5.  Any file containing `sha256`, `checksums`, or `sums` in its name (excluding `.sig` files).

2.  **Download Checksum File:** If a checksum file is found, it's downloaded to the runner.

3.  **Extract Checksum:** The action then extracts the checksum for the specific release artifact from the checksum file.

4.  **Verify Checksum:** Finally, it calculates the SHA256 checksum of the downloaded artifact and compares it with the expected checksum. If the checksums don't match, the build fails.

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
