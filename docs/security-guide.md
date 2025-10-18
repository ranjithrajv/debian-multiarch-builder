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

### Lintian Integration

Lintian is a tool that checks Debian packages for common errors and policy violations. By enabling Lintian integration, you can ensure that your packages are compliant with Debian policy and free of common errors.

To enable Lintian integration, set the `lintian-check` input to `true` in your workflow file:

```yaml
- name: Build packages
  uses: ranjithrajv/debian-multiarch-builder@v1
  with:
    config-file: 'package.yaml'
    version: ${{ inputs.version }}
    build-version: ${{ inputs.build_version }}
    lintian-check: true
```

When Lintian integration is enabled, the action will run Lintian on each package that is built. If Lintian finds any errors, the build for that package will fail. The output of the Lintian check will be included in the build logs, and the results will be stored in the `build-summary.json` file.
