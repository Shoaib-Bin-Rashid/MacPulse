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

# Overrides for isolated testing
if [[ -n "${MACPULSE_LEGACY_DIR:-}" ]]; then
    user_app="$MACPULSE_LEGACY_DIR/$name.app"
fi

current_lock_dir=""

# ======================================================================
# Interprocess Transaction Lock Management
# ======================================================================
acquire_lock() {
    local tdir="$1"
    local ldir="$tdir/.MacPulse.lock"
    local timeout="${MACPULSE_LOCK_TIMEOUT:-5}"
    local waited=0

    mkdir -p "$tdir"

    while true; do
        if mkdir "$ldir" 2>/dev/null; then
            echo "$$" > "$ldir/pid"
            date +%s > "$ldir/timestamp"
            current_lock_dir="$ldir"
            return 0
        fi

        # Lock exists. Check if holder process is still alive.
        local holder_pid=""
        if [[ -f "$ldir/pid" ]]; then
            holder_pid=$(cat "$ldir/pid" 2>/dev/null || true)
        fi

        if [[ -n "$holder_pid" ]]; then
            if ! kill -0 "$holder_pid" 2>/dev/null; then
                echo "⚠️  Found stale transaction lock held by dead PID $holder_pid; reclaiming lock..."
                rm -rf "$ldir"
                continue
            fi
        fi

        if (( waited >= timeout )); then
            echo "❌ Another MacPulse transaction is currently active (PID: ${holder_pid:-unknown}, target: $tdir)."
            echo "❌ Timed out waiting for transaction lock after ${timeout}s. Exiting safely to prevent collision."
            return 1
        fi

        sleep 0.2
        waited=$((waited + 1))
    done
}

release_lock() {
    if [[ -n "${current_lock_dir:-}" && -d "$current_lock_dir" ]]; then
        local pid
        pid=$(cat "$current_lock_dir/pid" 2>/dev/null || true)
        if [[ "$pid" == "$$" ]]; then
            rm -rf "$current_lock_dir"
        fi
        current_lock_dir=""
    fi
}

# ======================================================================
# Reusable Application Bundle Validator
# ======================================================================
validate_macpulse_bundle() {
    local bundle="$1"
    local silent="${2:-false}"

    # 1. App bundle directory exists
    if [[ ! -d "$bundle" ]]; then
        [[ "$silent" == true ]] || echo "❌ Bundle directory does not exist: $bundle"
        return 1
    fi

    # 2. Info.plist is valid
    local plist="$bundle/Contents/Info.plist"
    if [[ ! -f "$plist" ]] || ! plutil -lint "$plist" >/dev/null 2>&1; then
        [[ "$silent" == true ]] || echo "❌ Info.plist is missing or invalid in: $bundle"
        return 1
    fi

    # 3. CFBundleIdentifier equals com.shoaib.macpulse
    local bid
    bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
    if [[ "$bid" != "com.shoaib.macpulse" ]]; then
        [[ "$silent" == true ]] || echo "❌ CFBundleIdentifier mismatch in $bundle (got: '$bid', expected: 'com.shoaib.macpulse')"
        return 1
    fi

    # 4. Main executable exists and is executable
    local exec_path="$bundle/Contents/MacOS/$name"
    if [[ ! -f "$exec_path" || ! -x "$exec_path" ]]; then
        [[ "$silent" == true ]] || echo "❌ Main executable is missing or not executable: $exec_path"
        return 1
    fi

    # 5. Mach-O contains arm64 and x86_64
    local lipo_out
    lipo_out=$(lipo -info "$exec_path" 2>/dev/null || true)
    if ! echo "$lipo_out" | grep -q "arm64" || ! echo "$lipo_out" | grep -q "x86_64"; then
        [[ "$silent" == true ]] || echo "❌ Mach-O binary does not contain both arm64 and x86_64: $exec_path"
        return 1
    fi

    # 6. codesign --verify --deep --strict succeeds
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        [[ "$silent" == true ]] || echo "❌ Code signature verification failed for: $bundle"
        return 1
    fi

    return 0
}

# ======================================================================
# Safe Stale Artifact Recovery
# ======================================================================
recover_stale_artifacts() {
    local tdir="$1"
    local itarget="$2"

    echo "🔍 Inspecting $tdir for lingering installation artifacts..."

    # Check target state
    if [[ -d "$itarget" ]]; then
        if validate_macpulse_bundle "$itarget" true; then
            echo "✅ Installed application at $itarget is verified and healthy."
            # Clean up stale temporary artifacts
            for s in "$tdir"/.MacPulse.staging.*.app(N); do
                echo "🧹 Removing stale staging artifact: $s..."
                rm -rf "$s"
            done
            for b in "$tdir"/.MacPulse.backup.*.app(N); do
                echo "🧹 Target application is verified; removing stale backup $b..."
                rm -rf "$b"
            done
            return 0
        fi

        # Target exists but failed validation. Check if it's a foreign app.
        if [[ -f "$itarget/Contents/Info.plist" ]]; then
            local foreign_bid
            foreign_bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$itarget/Contents/Info.plist" 2>/dev/null || true)
            if [[ -n "$foreign_bid" && "$foreign_bid" != "com.shoaib.macpulse" ]]; then
                echo "❌ Foreign or unidentifiable application detected at $itarget (CFBundleIdentifier: '$foreign_bid')!"
                echo "❌ Refusing to delete or overwrite. Preserving all backups and targets for manual intervention."
                return 1
            fi
        fi
        echo "⚠️  Target at $itarget is corrupted or incomplete."
    else
        echo "ℹ️  No application installed at target $itarget."
    fi

    # Find and validate all available backup candidates
    local valid_candidate=""
    for b in "$tdir"/.MacPulse.backup.*.app(Nom); do
        if validate_macpulse_bundle "$b" true; then
            valid_candidate="$b"
            break
        else
            echo "⚠️  Candidate backup failed validation: $b"
        fi
    done

    if [[ -n "$valid_candidate" ]]; then
        echo "🔄 Restoring installation from verified backup: $valid_candidate -> $itarget..."
        rm -rf "$itarget"
        mv "$valid_candidate" "$itarget"
        if validate_macpulse_bundle "$itarget"; then
            echo "✅ Successfully restored and verified application at: $itarget."
            # Clean up remaining stale staging and backups
            rm -rf "$tdir"/.MacPulse.staging.*.app(N)
            rm -rf "$tdir"/.MacPulse.backup.*.app(N)
            return 0
        else
            echo "❌ Restored application failed post-recovery verification! Preserving all artifacts for inspection."
            return 1
        fi
    fi

    # If target is missing/corrupted and NO valid backup was found
    if [[ -d "$itarget" ]] || [[ -e "$tdir"/.MacPulse.backup.*.app(N) ]]; then
        echo "❌ Application at $itarget is invalid, and no valid MacPulse backup candidate is available."
        echo "❌ Preserving all candidate artifacts for manual inspection."
        return 1
    fi

    echo "ℹ️  No stale transaction artifacts found in $tdir."
    return 0
}

# ======================================================================
# Safe Legacy Cleanup (--clean-legacy)
# ======================================================================
clean_legacy_duplicate() {
    local target_app="$1"
    local app_dir
    app_dir="$(dirname "$target_app")"

    acquire_lock "$app_dir"

    if [[ -L "$target_app" ]]; then
        echo "⚠️  $target_app is a symbolic link; safely removing symlink..."
        rm "$target_app"
        echo "✅ Legacy symlink removed: $target_app"
        release_lock
        return 0
    fi

    if [[ -d "$target_app" ]]; then
        local plist="$target_app/Contents/Info.plist"
        if [[ ! -f "$plist" ]]; then
            echo "❌ Refusing to remove $target_app: missing Info.plist (unidentifiable bundle)!"
            release_lock
            return 1
        fi

        local legacy_bid
        legacy_bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
        if [[ "$legacy_bid" == "com.shoaib.macpulse" ]]; then
            echo "🧹 Removing legacy duplicate MacPulse bundle: $target_app..."
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$target_app" 2>/dev/null || true
            rm -rf "$target_app"
            echo "✅ Legacy copy removed: $target_app"
            release_lock
            return 0
        else
            echo "❌ Refusing to remove $target_app: foreign CFBundleIdentifier ('$legacy_bid') does not match com.shoaib.macpulse!"
            release_lock
            return 1
        fi
    fi

    echo "ℹ️  No legacy copy found at $target_app."
    release_lock
    return 0
}

# If --clean-legacy alone was requested, perform cleanup and exit
if [[ "$do_clean_legacy" == true && "$do_install" == false ]]; then
    clean_legacy_duplicate "$user_app"
    exit 0
fi

# If --recover was requested alone, run recovery and exit
if [[ "$do_recover" == true && "$do_install" == false ]]; then
    if [[ -n "${MACPULSE_INSTALL_DIR:-}" ]]; then
        rec_dir="$MACPULSE_INSTALL_DIR"
        rec_target="$rec_dir/$name.app"
    else
        rec_target="$system_app"
        rec_dir="$(dirname "$rec_target")"
        if ! touch /Applications/.macpulse_check 2>/dev/null; then
            rec_target="$user_app"
            rec_dir="$(dirname "$rec_target")"
        else
            rm -f /Applications/.macpulse_check
        fi
    fi

    acquire_lock "$rec_dir"
    recover_stale_artifacts "$rec_dir" "$rec_target"
    release_lock
    exit 0
fi

# ======================================================================
# Compilation & Local Packaging Phase (Strictly build/ outputs)
# ======================================================================
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

# Clean up duplicate copy in ~/Applications if requested via --clean-legacy alongside install
if [[ "$do_clean_legacy" == true ]]; then
    clean_legacy_duplicate "$user_app"
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

# ======================================================================
# Installation Transaction Lifecycle
# ======================================================================
acquire_lock "$target_dir"

# Failure injection hook for testing lock contention
if [[ -n "${MACPULSE_FAIL_INJECT_PAUSE_LOCK:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Holding lock and creating sync marker..."
    touch "$MACPULSE_FAIL_INJECT_PAUSE_LOCK"
    while true; do sleep 1; done
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

    release_lock

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

if [[ -n "${MACPULSE_FAIL_INJECT_STAGE_ARCH:-}" ]]; then
    echo "💥 [FAILURE INJECTION] Stripping required architecture slice..."
    lipo -extract arm64 "$stage_app/Contents/MacOS/$name" -output "$stage_app/Contents/MacOS/$name.thin" 2>/dev/null || true
    mv "$stage_app/Contents/MacOS/$name.thin" "$stage_app/Contents/MacOS/$name"
    codesign --force --sign - "$stage_app" 2>&1 || true
fi

validate_macpulse_bundle "$stage_app" || {
    echo "❌ Staged bundle pre-swap validation failed!"
    exit 1
}
echo "✅ Staged bundle passed all pre-swap validation checks."

# Step 4: Rename existing target to backup sibling (if existing installation is present)
if [[ -d "$install_target" ]]; then
    echo "🛡️  Preserving existing installation to sibling backup: $backup_app..."
    rm -rf "$backup_app"
    mv "$install_target" "$backup_app"
    transaction_state="BACKED_UP"

    # Deterministic pause hook for true SIGKILL process testing
    if [[ -n "${MACPULSE_FAIL_INJECT_PAUSE_AFTER_BACKUP:-}" ]]; then
        echo "💥 [FAILURE INJECTION] Touching sync marker and pausing after backup rename..."
        touch "$MACPULSE_FAIL_INJECT_PAUSE_AFTER_BACKUP"
        while true; do sleep 1; done
    fi

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

validate_macpulse_bundle "$install_target" || {
    echo "❌ Post-replacement verification failed: installed bundle is invalid!"
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
