import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const desktopDir = resolve(scriptDir, "..");
const tauriDir = join(desktopDir, "src-tauri");
const development = process.argv.slice(2).includes("--development");

if (!development) {
  if (process.env.BEDROCK_REQUIRE_PRODUCTION_TRUST !== "1") {
    throw new Error("release sidecars require BEDROCK_REQUIRE_PRODUCTION_TRUST=1");
  }
  const certificate = process.env.BEDROCK_INSTALLER_TRUST_CERT;
  if (!certificate || !existsSync(certificate)) {
    throw new Error("release sidecars require a readable BEDROCK_INSTALLER_TRUST_CERT");
  }
}

const cargo = process.env.CARGO || "cargo";
const rustc = process.env.RUSTC || "rustc";
const triple = execFileSync(rustc, ["--print", "host-tuple"], { encoding: "utf8" }).trim();
if (!/^[A-Za-z0-9_.-]+$/.test(triple)) throw new Error("Rust returned an invalid host target triple");

const build = spawnSync(
  cargo,
  ["build", "--release", "--bin", "bedrock-media-writer", "--manifest-path", join(tauriDir, "Cargo.toml")],
  { cwd: tauriDir, env: process.env, stdio: "inherit" },
);
if (build.status !== 0) throw new Error("the protected writer helper did not compile");

const extension = process.platform === "win32" ? ".exe" : "";
const targetRoot = process.env.CARGO_TARGET_DIR
  ? resolve(tauriDir, process.env.CARGO_TARGET_DIR)
  : join(tauriDir, "target");
const source = join(targetRoot, "release", `bedrock-media-writer${extension}`);
const destination = join(tauriDir, "binaries", `bedrock-media-writer-${triple}${extension}`);
if (!existsSync(source)) throw new Error("the protected writer helper output is missing");
mkdirSync(dirname(destination), { recursive: true });
copyFileSync(source, destination);
if (process.platform !== "win32") chmodSync(destination, 0o755);

const digest = path => createHash("sha256").update(readFileSync(path)).digest("hex");
if (digest(source) !== digest(destination)) throw new Error("the packaged helper does not match the compiled helper");
process.stdout.write(`${destination}\n`);
