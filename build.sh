#!/bin/zsh
# Builds MacPulse native application bundle in build/MacPulse.app.
# Usage: ./build.sh                  Build universal release bundle strictly inside build/
#        ./build.sh --install        Build and safely install to /Applications (or ~/Applications fallback)
#        ./build.sh --open           Build, install, quit running instance, and launch newly installed copy
#        ./build.sh --clean-legacy   Explicitly unregister and remove duplicate copy from ~/Applications
set -euo pipefail
here=${0:A:h}
name="MacPulse"
build_dir="$here/build"
bin_dir="$build_dir/bin"
mkdir -p "$bin_dir"

do_install=false
do_open=false
do_clean_legacy=false

for arg in "$@"; do
    case "$arg" in
        --install)
            do_install=true
            ;;
        --open)
            do_install=true
            do_open=true
            ;;
        --clean-legacy)
            do_clean_legacy=true
            ;;
        --help|-h)
            echo "Usage: ./build.sh [--install] [--open] [--clean-legacy]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: ./build.sh [--install] [--open] [--clean-legacy]"
            exit 1
            ;;
    esac
done

echo "⚡ Compiling MacPulse native binary..."
xcrun clang -fobjc-arc -O2 \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa \
    -framework IOKit \
    -framework ServiceManagement \
    "$here"/Sources/MacPulseNative/*.m \
    -o "$bin_dir/$name"

[[ -x "$bin_dir/$name" ]] || { echo "❌ Compilation failed"; exit 1; }

echo "🔍 Verifying binary architectures..."
lipo -info "$bin_dir/$name" | grep -q "arm64" && lipo -info "$bin_dir/$name" | grep -q "x86_64" || {
    echo "❌ Universal binary verification failed: missing required architectures"
    exit 1
}

app_bundle="$build_dir/$name.app"
system_app="/Applications/$name.app"
user_app="$HOME/Applications/$name.app"
icon_src="$here/Icon/AppIcon.icns"

# Build local bundle strictly in build/ directory
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
touch "$build_dir/.metadata_never_index"
rm -rf "$app_bundle/Contents/MacOS/$name"
cp "$bin_dir/$name" "$app_bundle/Contents/MacOS/$name"
if [[ -f "$icon_src" ]]; then
    cp "$icon_src" "$app_bundle/Contents/Resources/AppIcon.icns"
fi
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app_bundle/Contents/Info.plist"
xattr -cr "$app_bundle"
codesign --force --sign - "$app_bundle" 2>&1 | grep -v "replacing existing signature" || true
echo "✅ Built bundle: $app_bundle"

# Clean up duplicate copy in ~/Applications ONLY if explicitly requested via --clean-legacy
if [[ "$do_clean_legacy" == true ]]; then
    if [[ -d "$user_app" ]]; then
        echo "🧹 Removing legacy duplicate from ~/Applications..."
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$user_app" 2>/dev/null || true
        rm -rf "$user_app"
        echo "✅ Legacy copy removed from ~/Applications."
    else
        echo "ℹ️  No legacy copy found in ~/Applications."
    fi
fi

# Only proceed with system or user installation if explicitly requested
if [[ "$do_install" == false ]]; then
    echo "💡 Note: Normal build completed inside build/ without modifying /Applications or ~/Applications."
    echo "💡 Use './build.sh --install' to safely install, or './build.sh --open' to install and launch."
    exit 0
fi

# Primary installation target: /Applications/MacPulse.app with fallback to ~/Applications
install_target="$system_app"
if ! touch /Applications/.macpulse_check 2>/dev/null; then
    echo "ℹ️  /Applications is not writable without administrator privileges; falling back to $user_app"
    install_target="$user_app"
else
    rm -f /Applications/.macpulse_check
fi

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/macpulse_stage.XXXXXX")
backup_dir=""

cleanup_stage() {
    rm -rf "$stage_dir"
    if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
        rm -rf "$backup_dir"
    fi
}
trap cleanup_stage EXIT INT TERM

echo "📦 Staging application bundle for validation..."
cp -R "$app_bundle" "$stage_dir/$name.app"

# Validation Phase before swapping
echo "🔍 Validating staged application bundle..."
plutil -lint "$stage_dir/$name.app/Contents/Info.plist" >/dev/null || {
    echo "❌ Staged Info.plist validation failed"
    exit 1
}

lipo -info "$stage_dir/$name.app/Contents/MacOS/$name" | grep -q "arm64" && \
lipo -info "$stage_dir/$name.app/Contents/MacOS/$name" | grep -q "x86_64" || {
    echo "❌ Staged binary universal architecture validation failed"
    exit 1
}

codesign --verify --deep --strict "$stage_dir/$name.app" 2>&1 || {
    echo "❌ Staged bundle signature verification failed"
    exit 1
}
echo "✅ Staged bundle passed all validation checks."

# Backup existing installation if present
if [[ -d "$install_target" ]]; then
    backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/macpulse_backup.XXXXXX")
    echo "🛡️  Backing up existing installation to $backup_dir..."
    cp -R "$install_target" "$backup_dir/$name.app"
fi

# Atomic replacement
mkdir -p "$(dirname "$install_target")"
echo "📦 Installing validated bundle to $install_target..."
if ! (rm -rf "$install_target" && cp -R "$stage_dir/$name.app" "$install_target"); then
    echo "❌ Installation copy failed!"
    if [[ -n "$backup_dir" && -d "$backup_dir/$name.app" ]]; then
        echo "🔄 Restoring previous installation from backup..."
        rm -rf "$install_target"
        cp -R "$backup_dir/$name.app" "$install_target"
        echo "✅ Previous installation restored."
    fi
    exit 1
fi

xattr -cr "$install_target"
codesign --force --sign - "$install_target" 2>&1 | grep -v "replacing existing signature" || true

# Register strictly the installed app with LaunchServices & Spotlight
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app_bundle" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r "$install_target" 2>/dev/null || true
mdimport "$install_target" 2>/dev/null || true
touch "$install_target"

echo "✅ Successfully installed MacPulse to: $install_target"

if [[ "$do_open" == true ]]; then
    echo "🚀 Launching $name from $install_target..."
    osascript -e "quit app \"$name\"" 2>/dev/null || true
    sleep 0.5
    open "$install_target"
fi
