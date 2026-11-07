import { spawnSync } from "child_process";
import { existsSync, mkdirSync, rmSync } from "fs";
import { join } from "path";

console.log("📦 Packaging MacPulse DMG...");

const projectRoot = join(import.meta.dir, "..");
const appPath = join(projectRoot, "build", "MacPulse.app");
const distDir = join(projectRoot, "dist");
const dmgPath = join(distDir, "MacPulse.dmg");

console.log("Building application first...");
const buildResult = spawnSync("zsh", [join(projectRoot, "build.sh")], {
  cwd: projectRoot,
  stdio: "inherit",
});
if (buildResult.status !== 0) {
  console.error("❌ Failed to build application before packaging.");
  process.exit(1);
}

if (!existsSync(distDir)) {
  mkdirSync(distDir, { recursive: true });
}

if (existsSync(dmgPath)) {
  rmSync(dmgPath);
}

// Create staging directory with /Applications symlink for drag-and-drop installer
const stagingDir = join(distDir, "dmg_staging");
if (existsSync(stagingDir)) {
  rmSync(stagingDir, { recursive: true, force: true });
}
mkdirSync(stagingDir, { recursive: true });

spawnSync("cp", ["-R", appPath, stagingDir]);
try {
  spawnSync("ln", ["-s", "/Applications", join(stagingDir, "Applications")]);
} catch (e) {
  console.warn("Could not create Applications symlink:", e);
}

// Create DMG using hdiutil
console.log(`Creating DMG image at: ${dmgPath}`);
const hdiutilResult = spawnSync("hdiutil", [
  "create",
  "-volname", "MacPulse",
  "-srcfolder", stagingDir,
  "-ov",
  "-format", "UDZO",
  dmgPath,
], {
  stdio: "inherit",
});

if (existsSync(stagingDir)) {
  rmSync(stagingDir, { recursive: true, force: true });
}

if (hdiutilResult.status === 0) {
  console.log("✅ MacPulse.dmg created successfully!");
} else {
  console.error("❌ Failed to create DMG.");
  process.exit(hdiutilResult.status ?? 1);
}
