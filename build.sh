#!/bin/bash

set -e

CONFIG_FILE=$1
VERSION=$2
BUILD_VERSION=$3
ARCH=${4:-all}

if [ -z "$CONFIG_FILE" ] || [ -z "$VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <config-file> <version> <build-version> [architecture]"
    echo "Example: $0 config.yaml 2.35.0 1 arm64"
    echo "Example: $0 config.yaml 2.35.0 1 all    # Build for all architectures"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Parse configuration using yq
PACKAGE_NAME=$(yq eval '.package_name' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.github_repo' "$CONFIG_FILE")
ARTIFACT_FORMAT=$(yq eval '.artifact_format // "tar.gz"' "$CONFIG_FILE")
BINARY_PATH=$(yq eval '.binary_path // ""' "$CONFIG_FILE")

echo "Building $PACKAGE_NAME version $VERSION"
echo "GitHub repo: $GITHUB_REPO"

# Get Debian distributions from config
DISTRIBUTIONS=$(yq eval '.debian_distributions[]' "$CONFIG_FILE" | tr '\n' ' ')
echo "Distributions: $DISTRIBUTIONS"

# Function to get release pattern for an architecture
get_release_pattern() {
    local arch=$1
    local pattern=$(yq eval ".architectures.${arch}.release_pattern" "$CONFIG_FILE")

    if [ "$pattern" = "null" ] || [ -z "$pattern" ]; then
        echo ""
        return 1
    fi

    # Replace {version} placeholder with actual version
    pattern="${pattern//\{version\}/$VERSION}"
    echo "$pattern"
    return 0
}

# Function to get all supported architectures from config
get_supported_architectures() {
    yq eval '.architectures | keys | .[]' "$CONFIG_FILE"
}

# Function to check if architecture is supported for a distribution
is_arch_supported_for_dist() {
    local arch=$1
    local dist=$2

    # Check if there's a distribution override
    local override_dists=$(yq eval ".distribution_arch_overrides.${arch}.distributions[]" "$CONFIG_FILE" 2>/dev/null)

    if [ "$override_dists" != "null" ] && [ -n "$override_dists" ]; then
        # If override exists, check if dist is in the list
        echo "$override_dists" | grep -q "^${dist}$"
        return $?
    fi

    # No override, all distributions supported
    return 0
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local release_pattern

    release_pattern=$(get_release_pattern "$build_arch")
    if [ $? -ne 0 ]; then
        echo "❌ Unsupported architecture: $build_arch (not found in config)"
        return 1
    fi

    echo "==========================================="
    echo "Building for architecture: $build_arch"
    echo "Release pattern: $release_pattern"
    echo "==========================================="

    # Extract filename without extension for directory name
    local archive_name="${release_pattern}"
    local extract_dir="${archive_name%.tar.gz}"
    extract_dir="${extract_dir%.zip}"
    extract_dir="${extract_dir%.tgz}"

    # Clean up any previous builds for this architecture
    rm -rf "$extract_dir" || true
    rm -f "$archive_name" || true

    # Download the release artifact
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${release_pattern}"
    echo "Downloading from: $download_url"

    if ! wget -q "$download_url"; then
        echo "❌ Failed to download release for $build_arch from $download_url"
        return 1
    fi

    # Extract the archive based on format
    echo "Extracting $archive_name..."
    case "$ARTIFACT_FORMAT" in
        "tar.gz"|"tgz")
            if ! tar -xzf "$archive_name"; then
                echo "❌ Failed to extract $archive_name"
                return 1
            fi
            ;;
        "zip")
            if ! unzip -q "$archive_name"; then
                echo "❌ Failed to extract $archive_name"
                return 1
            fi
            ;;
        *)
            echo "❌ Unsupported archive format: $ARTIFACT_FORMAT"
            return 1
            ;;
    esac

    rm -f "$archive_name"

    # Determine the binary location
    local binary_source
    if [ -n "$BINARY_PATH" ]; then
        binary_source="$extract_dir/$BINARY_PATH"
    else
        binary_source="$extract_dir"
    fi

    # Build packages for each Debian distribution
    for dist in $DISTRIBUTIONS; do
        # Check if this architecture is supported for this distribution
        if ! is_arch_supported_for_dist "$build_arch" "$dist"; then
            echo "⏭️  Skipping $dist for $build_arch (not supported in this distribution)"
            continue
        fi

        FULL_VERSION="${VERSION}-${BUILD_VERSION}+${dist}_${build_arch}"
        echo "  Building $FULL_VERSION"

        if ! docker build . -t "${PACKAGE_NAME}-${dist}-${build_arch}" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg PACKAGE_NAME="$PACKAGE_NAME" \
            --build-arg VERSION="$VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg BINARY_SOURCE="$binary_source" \
            --build-arg GITHUB_REPO="$GITHUB_REPO"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "${PACKAGE_NAME}-${dist}-${build_arch}")"
        if ! docker cp "$id:/${PACKAGE_NAME}_${FULL_VERSION}.deb" - > "./${PACKAGE_NAME}_${FULL_VERSION}.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            docker rm "$id" || true
            return 1
        fi

        docker rm "$id" || true

        if ! tar -xf "./${PACKAGE_NAME}_${FULL_VERSION}.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up extracted directory
    rm -rf "$extract_dir" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building $PACKAGE_NAME $VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    # Get all supported architectures from config
    ARCHITECTURES=$(get_supported_architectures)

    for build_arch in $ARCHITECTURES; do
        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi
        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la ${PACKAGE_NAME}_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi

    echo "Generated packages:"
    ls -la ${PACKAGE_NAME}_*.deb
fi
