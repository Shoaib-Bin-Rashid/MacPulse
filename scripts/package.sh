#!/bin/zsh
set -euo pipefail
here=${0:A:h:h}
dist="$here/dist"
app="$here/build/MacPulse.app"
dmg="$dist/MacPulse.dmg"
icon="$here/Icon/AppIcon.icns"

echo "📦 Packaging MacPulse DMG..."

# Always execute clean build before packaging
"$here/build.sh"

mkdir -p "$dist"
rm -f "$dmg"

# Create a temporary DMG staging directory
staging="$dist/dmg_staging"
rm -rf "$staging"
mkdir -p "$staging"

cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

# Set volume icon on DMG if available
if [[ -f "$icon" ]]; then
    cp "$icon" "$staging/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$staging/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$staging" 2>/dev/null || true
    fi
fi

hdiutil create -volname "MacPulse" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"

echo "✅ Generated $dmg"
ls -lh "$dmg"
