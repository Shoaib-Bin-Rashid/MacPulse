#!/bin/zsh
# Builds MacPulse and installs it to ~/Applications/MacPulse.app.
# Usage: ./build.sh            release build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="MacPulse"
build_dir="$here/build"
bin_dir="$build_dir/bin"
mkdir -p "$bin_dir"

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

# Build local bundle in build/ directory
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
rm -rf "$app_bundle/Contents/MacOS/$name"
cp "$bin_dir/$name" "$app_bundle/Contents/MacOS/$name"
if [[ -f "$icon_src" ]]; then
    cp "$icon_src" "$app_bundle/Contents/Resources/AppIcon.icns"
fi
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app_bundle/Contents/Info.plist"
xattr -cr "$app_bundle"
codesign --force --sign - "$app_bundle" 2>&1 | grep -v "replacing existing signature" || true

# Clean up any duplicate copy in ~/Applications to avoid Raycast/Spotlight duplicate collisions
if [[ -d "$user_app" ]]; then
    echo "🧹 Removing legacy duplicate from ~/Applications..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$user_app" 2>/dev/null || true
    rm -rf "$user_app"
fi

# Primary installation target: /Applications/MacPulse.app
install_target="$system_app"
if ! touch /Applications/.macpulse_check 2>/dev/null; then
    install_target="$user_app"
else
    rm -f /Applications/.macpulse_check
fi

echo "📦 Installing clean app bundle to $install_target..."
mkdir -p "$(dirname "$install_target")"
rm -rf "$install_target"
cp -R "$app_bundle" "$install_target"
xattr -cr "$install_target"
codesign --force --sign - "$install_target" 2>&1 | grep -v "replacing existing signature" || true

# Register strictly the installed app with LaunchServices & Spotlight for Raycast/Spotlight discovery
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app_bundle" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r "$install_target" 2>/dev/null || true
mdimport "$install_target" 2>/dev/null || true
touch "$install_target"

echo "✅ Installed MacPulse to: $install_target"

if [[ " $* " == *" --open "* ]]; then
    echo "🚀 Launching $name..."
    osascript -e "quit app \"$name\"" 2>/dev/null || true
    sleep 0.5
    open "$install_target"
fi
