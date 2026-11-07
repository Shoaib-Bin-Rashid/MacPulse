import { spawnSync } from "child_process";
import { existsSync, mkdirSync, copyFileSync, chmodSync } from "fs";
import { join } from "path";

console.log("⚡ Building MacPulse...");

const projectRoot = join(import.meta.dir, "..");
const buildScript = join(projectRoot, "build.sh");

if (!existsSync(buildScript)) {
  console.error("❌ build.sh not found in project root!");
  process.exit(1);
}

const result = spawnSync("zsh", [buildScript], {
  cwd: projectRoot,
  stdio: "inherit",
});

if (result.status !== 0) {
  console.error(`❌ Build failed with exit code ${result.status}`);
  process.exit(result.status ?? 1);
}

console.log("✅ MacPulse build completed successfully!");
