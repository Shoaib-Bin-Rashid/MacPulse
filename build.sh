#!/bin/zsh
# Builds MacPulse native application bundle in build/MacPulse.app.
# Usage: ./build.sh                  Build universal release bundle strictly inside build/
#        ./build.sh --install        Build and safely install to /Applications (or ~/Applications fallback)
#        ./build.sh --open           Build, install, quit running instance, and launch newly installed copy
#        ./build.sh --clean-legacy   Explicitly unregister and remove duplicate copy from ~/Applications
#        ./build.sh --recover        Safely recover from an interrupted installation transaction
set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true
here=${0:A:h}
name="MacPulse"
build_dir="$here/build"
bin_dir="$build_dir/bin"
mkdir -p "$bin_dir"

do_install=false
do_open=false
do_clean_legacy=false
do_recover=false

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
        --recover)
            do_recover=true
            ;;
        --help|-h)
            echo "Usage: ./build.sh [--install] [--open] [--clean-legacy] [--recover]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: ./build.sh [--install] [--open] [--clean-legacy] [--recover]"
            exit 1
            ;;
    esac
done

system_app="/Applications/$name.app"
user_app="$HOME/Applications/$name.app"

# Helper function to safely recover stale staging/backup artifacts
recover_stale_artifacts() {
    local tdir="$1"
    local itarget="$2"
    local found=0

    echo "🔍 Inspecting $tdir for lingering installation artifacts..."
    
    # Check for stale backups
    for b in "$tdir"/.MacPulse.backup.*.app(N); do
        if [[ -e "$b" ]]; then
            found=1
            echo "⚠️  Found backup artifact: $b"
            if [[ ! -d "$itarget" ]] || ! plutil -lint "$itarget/Contents/Info.plist" >/dev/null 2>&1; then
                echo "🔄 Restoring application from backup $b to $itarget..."
                rm -rf "$itarget"
                mv "$b" "$itarget"
                echo "✅ Successfully restored installation to $itarget."
            else
                echo "🧹 Installed application at $itarget is verified and intact; removing stale backup $b..."
                rm -rf "$b"
            fi
        fi
    done

    # Check for stale staging directories
    for s in "$tdir"/.MacPulse.staging.*.app(N); do
        if [[ -e "$s" ]]; then
            found=1
            echo "🧹 Removing stale staging artifact: $s..."
            rm -rf "$s"
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        echo "ℹ️  No stale transaction artifacts found in $tdir."
    fi
}

# If --recover was requested alone, run recovery and exit
if [[ "$do_recover" == true && "$do_install" == false ]]; then
    if [[ -n "${MACPULSE_INSTALL_DIR:-}" ]]; then
        recover_stale_artifacts "$MACPULSE_INSTALL_DIR" "$MACPULSE_INSTALL_DIR/$name.app"
    else
        recover_stale_artifacts "/Applications" "$system_app"
        recover_stale_artifacts "$HOME/Applications" "$user_app"
    fi
    exit 0
fi

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

# Determine target directory and path (supporting MACPULSE_INSTALL_DIR for isolated testing)
if [[ -n "${MACPULSE_INSTALL_DIR:-}" ]]; then
    target_dir="$MACPULSE_INSTALL_DIR"
    install_target="$target_dir/$name.app"
    mkdir -p "$target_dir"
else
    install_target="$system_app"
    target_dir="$(dirname "$install_target")"
    if ! touch /Applications/.macpulse_check 2>/dev/null; then
        echo "ℹ️  /Applications is not writable without administrator privileges; falling back to $user_app"
        install_target="$user_app"
        target_dir="$(dirname "$install_target")"
    else
        rm -f /Applications/.macpulse_check
    fi
fi

# Run pre-installation recovery check on target directory in case of prior abnormal interruption
recover_stale_artifacts "$target_dir" "$install_target"

# Transaction State Management
stage_app="$target_dir/.MacPulse.staging.$$.app"
backup_app="$target_dir/.MacPulse.backup.$$.app"
transaction_state="INIT"

rollback_and_cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP
    
    if [[ "$transaction_state" != "COMMITTED" ]]; then
        echo "⚠️  Transaction interrupted or failed (state: $transaction_state, exit code: $exit_code)!"
        
        # If target was backed up, restore it if target is missing or unverified
        if [[ -d "$backup_app" ]]; then
            echo "🛡️  Restoring previous installation from backup..."
            if [[ -d "$install_target" && "$transaction_state" == "SWAPPED" ]]; then
                rm -rf "$install_target"
            fi
            if [[ ! -d "$install_target" ]]; then
                mv "$backup_app" "$install_target"
                echo "✅ Successfully restored previous installation to $install_target."
            else
                echo "ℹ️  Target already present at $install_target. Backup preserved at $backup_app."
            fi
        fi

        # Remove temporary staging app if present
        if [[ -d "$stage_app" ]]; then
            rm -rf "$stage_app"
        fi
    else
        # COMMITTED: Only clean up backup if transaction fully verified and committed
        if [[ -d "$backup_app" ]]; then
            rm -rf "$backup_app"
        fi
        if [[ -d "$stage_app" ]]; then
            rm -rf "$stage_app"
        fi
    fi

    if [[ $exit_code -ne 0 ]]; then
        exit $exit_code
    fi
}
trap rollback_and_cleanup EXIT INT TERM HUP

# Step 1: Guard against overwriting an unrelated application
if [[ -d "$install_target" ]]; then
    if [[ -f "$install_target/Contents/Info.plist" ]]; then
        existing_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$install_target/Contents/Info.plist" 2>/dev/null || true)
        if [[ -n "$existing_bundle_id" && "$existing_bundle_id" != "com.shoaib.macpulse" ]]; then
            echo "❌ Target at $install_target exists and is not MacPulse (bundle id: $existing_bundle_id)!"
            echo "❌ Aborting installation to protect unrelated application."
            exit 1
        fi
    fi
fi

# Step 2: Stage application on the destination filesystem
echo "📦 Staging application bundle on target filesystem: $stage_app..."
rm -rf "$stage_app"

if [[ -n "${MACPULSE_FAIL_INJECT_COPY:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Simulating copy failure during staging..."
    exit 1
fi

cp -R "$app_bundle" "$stage_app"
transaction_state="STAGED"

# Step 3: Pre-swap validation
echo "🔍 Validating staged application bundle before swap..."

if [[ -n "${MACPULSE_FAIL_INJECT_STAGE_PLIST:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Corrupting staged Info.plist..."
    echo "INVALID XML DATA" > "$stage_app/Contents/Info.plist"
fi

plutil -lint "$stage_app/Contents/Info.plist" >/dev/null || {
    echo "❌ Staged Info.plist validation failed"
    exit 1
}

staged_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$stage_app/Contents/Info.plist" 2>/dev/null || true)
if [[ "$staged_bundle_id" != "com.shoaib.macpulse" ]]; then
    echo "❌ Staged bundle identifier mismatch (found: $staged_bundle_id, expected: com.shoaib.macpulse)"
    exit 1
fi

if [[ -n "${MACPULSE_FAIL_INJECT_STAGE_ARCH:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Stripping required architecture slice..."
    FAKE_NO_X86=true
fi

if [[ "${FAKE_NO_X86:-false}" == true ]]; then
    echo "❌ Staged binary universal architecture validation failed: missing x86_64"
    exit 1
fi

lipo -info "$stage_app/Contents/MacOS/$name" | grep -q "arm64" && \
lipo -info "$stage_app/Contents/MacOS/$name" | grep -q "x86_64" || {
    echo "❌ Staged binary universal architecture validation failed"
    exit 1
}

codesign --verify --deep --strict "$stage_app" 2>&1 || {
    echo "❌ Staged bundle signature verification failed"
    exit 1
}
echo "✅ Staged bundle passed all pre-swap validation checks."

# Step 4: Rename existing target to backup sibling (if existing installation is present)
if [[ -d "$install_target" ]]; then
    echo "🛡️  Preserving existing installation to sibling backup: $backup_app..."
    rm -rf "$backup_app"
    mv "$install_target" "$backup_app"
    transaction_state="BACKED_UP"

    # Signal failure injection test hooks
    if [[ -n "${MACPULSE_FAIL_INJECT_SIGTERM:-}" ]]; then
        echo "💥 [FAILURE INJECTION] Simulating SIGTERM right after backup rename..."
        kill -TERM $$
    fi
    if [[ -n "${MACPULSE_FAIL_INJECT_SIGINT:-}" ]]; then
        echo "💥 [FAILURE INJECTION] Simulating SIGINT right after backup rename..."
        kill -INT $$
    fi
fi

# Step 5: Rename validated staging bundle into target location (atomic on same filesystem)
echo "📦 Swapping validated bundle into target: $install_target..."
if [[ -n "${MACPULSE_FAIL_INJECT_SWAP:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Simulating rename/swap failure..."
    exit 1
fi

mv "$stage_app" "$install_target"
transaction_state="SWAPPED"

# Step 6: Post-replacement verification
echo "🔍 Verifying installed application bundle at target..."

if [[ -n "${MACPULSE_FAIL_INJECT_VERIFY:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Corrupting installed target to trigger post-swap verification failure..."
    rm -f "$install_target/Contents/MacOS/$name"
fi

[[ -x "$install_target/Contents/MacOS/$name" ]] || {
    echo "❌ Post-replacement verification failed: binary missing or not executable"
    exit 1
}

plutil -lint "$install_target/Contents/Info.plist" >/dev/null || {
    echo "❌ Post-replacement verification failed: Info.plist is invalid"
    exit 1
}

codesign --verify --deep --strict "$install_target" 2>&1 || {
    echo "❌ Post-replacement verification failed: codesign verification failed"
    exit 1
}

# Step 7: Commit transaction
transaction_state="COMMITTED"
echo "✅ Post-replacement verification succeeded. Transaction committed."

# Step 8: Registration & Notifications
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
