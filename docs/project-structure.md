# Project Structure

The action code is organized into modular components for maintainability:

```
src/
├── lib/
│   ├── utils.sh          # Logging and output formatting
│   ├── config.sh         # Configuration parsing and validation
│   ├── github-api.sh     # GitHub API interactions
│   ├── discovery.sh      # Architecture pattern discovery
│   ├── validation.sh     # Release and checksum validation
│   ├── build.sh          # Core build functions
│   ├── orchestration.sh  # Build orchestration (parallel and sequential)
│   └── summary.sh        # Build summary generation
├── system.yaml           # System constants and Debian official policies
├── defaults.yaml         # User-configurable default settings
├── main.sh               # Main entry point
build.sh                  # Wrapper for backward compatibility
```

### Configuration Files

- **`src/system.yaml`** - System constants that rarely change:
  - Debian distribution details (bookworm, trixie, forky, sid)
  - Official architecture support policies
  - Architecture pattern mappings
  - Only updated when Debian releases new versions

- **`src/defaults.yaml`** - User-configurable defaults:
  - Build settings (parallel builds, max concurrent, etc.)
  - Auto-discovery preferences
  - Checksum verification patterns
  - Users can override these in their `multiarch-config.yaml`

Each module has a focused responsibility, making the codebase easier to understand, test, and extend.
