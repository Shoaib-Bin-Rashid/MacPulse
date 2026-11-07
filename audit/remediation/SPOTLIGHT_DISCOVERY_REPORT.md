# Spotlight & LaunchServices Discovery Report

**Product:** MacPulse  
**Target Bundle:** `/Applications/MacPulse.app`  
**Bundle Identifier:** `com.shoaib.macpulse`  
**Date:** 2026-11-07  
**Status:** VERIFIED & DIAGNOSED

---

## 1. Executive Summary

Spotlight discovery was investigated to resolve why `MacPulse` was readily found in Raycast application search while user uncertainty persisted regarding Spotlight search.

Key Findings:
1. **Installed Bundle Validity:** `/Applications/MacPulse.app` is a fully valid macOS universal application bundle with complete `Info.plist` metadata (`CFBundleDisplayName = "MacPulse"`, `CFBundleName = "MacPulse"`, `CFBundlePackageType = "APPL"`, `LSUIElement = true`).
2. **Spotlight Indexing Status:** Spotlight indexing on `/Applications` is active (`Indexing enabled.`). Querying Spotlight via `mdfind 'kMDItemKind == "Application" && kMDItemDisplayName == "MacPulse"'` immediately returns `/Applications/MacPulse.app`.
3. **Root Cause of Ambiguity:** 
   - In earlier screenshots, user searched for `macpulse.app.zip` (which directs Spotlight to search files/archives, not applications).
   - LaunchServices retained historical registrations pointing to ephemeral mounted volumes (`/Volumes/MacPulse/MacPulse.app`) and temporary staging folders (`/Users/shoaib/Workspace/Projects/MacPulse/dist/dmg_staging/MacPulse.app`).
4. **Resolution:** Stale unmounted registrations were purged from LaunchServices (`lsregister -u`), and `/Applications/MacPulse.app` was explicitly re-registered and indexed with `mdimport`. `LSUIElement = true` is preserved to keep MacPulse purely as a menu bar utility without an unwanted Dock icon.

---

## 2. Evidence & Diagnostics

### 2.1 Bundle & Metadata Inspection
Command:
```bash
plutil -p /Applications/MacPulse.app/Contents/Info.plist
```
Output:
```
{
  "CFBundleDisplayName" => "MacPulse"
  "CFBundleExecutable" => "MacPulse"
  "CFBundleIconFile" => "AppIcon"
  "CFBundleIconName" => "AppIcon"
  "CFBundleIdentifier" => "com.shoaib.macpulse"
  "CFBundleName" => "MacPulse"
  "CFBundlePackageType" => "APPL"
  "CFBundleShortVersionString" => "1.0.0"
  "CFBundleVersion" => "1"
  "LSApplicationCategoryType" => "public.app-category.utilities"
  "LSMinimumSystemVersion" => "13.0"
  "LSUIElement" => true
  "NSHighResolutionCapable" => true
  "NSPrincipalClass" => "NSApplication"
}
```

### 2.2 Spotlight MDLS Metadata
Command:
```bash
mdls -name kMDItemDisplayName -name kMDItemContentType -name kMDItemKind /Applications/MacPulse.app
```
Output:
```
kMDItemContentType = "com.apple.application-bundle"
kMDItemDisplayName = "MacPulse"
kMDItemKind        = "Application"
```

### 2.3 Spotlight Query Verification
Command:
```bash
mdfind 'kMDItemKind == "Application" && kMDItemDisplayName == "MacPulse"'
```
Output:
```
/Applications/MacPulse.app
/Users/shoaib/Workspace/Projects/MacPulse/build/MacPulse.app
```

Command:
```bash
mdfind "kMDItemDisplayName == 'MacPulse'c"
```
Output:
```
/Applications/MacPulse.app
/Users/shoaib/Workspace/Projects/MacPulse/build/MacPulse.app
```

### 2.4 LaunchServices Registration
Command:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A 10 "/Applications/MacPulse.app"
```
Output:
```
path:                       /Applications/MacPulse.app (0x94f0)
directory:                  /Applications
name:                       MacPulse
displayName:                MacPulse
localizedNames:             "LSDefaultLocalizedValue" = "MacPulse"
identifier:                 com.shoaib.macpulse
version:                    1.0
platform:                   native
executable:                 Contents/MacOS/MacPulse
slices:                     x86_64  arm64
```

---

## 3. How to Verify in macOS Spotlight & Raycast

1. **Spotlight Search (Exact):**
   - Press `Command + Space`.
   - Type `MacPulse`.
   - `MacPulse.app` appears under "Applications" / "Top Hit".
2. **Spotlight Filtered Search:**
   - Press `Command + Space`.
   - Type `kind:application MacPulse`.
   - Shows `/Applications/MacPulse.app`.
3. **Raycast Search:**
   - Open Raycast (`Option + Space` or custom shortcut).
   - Type `MacPulse`.
   - Shows single application entry for `/Applications/MacPulse.app`.

---

## 4. Policy Constraints Maintained

- `LSUIElement = true` was strictly preserved. MacPulse is a menu-bar-only app; it does not dock icon.
- No duplicate app bundles installed to `~/Applications`.
- Spotlight index on the host was NOT destructively rebuilt.
- Stale unmounted DMG paths were cleaned without touching `/Applications/MacPulse.app`.
