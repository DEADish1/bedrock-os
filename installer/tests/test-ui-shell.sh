#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ui="$ROOT/installer/ui"
for file in index.html styles.css recovery.js app.js; do [ -s "$ui/$file" ] || { printf 'error: installer UI file is missing: %s\n' "$file" >&2; exit 1; }; done
node --check "$ui/recovery.js"
node --check "$ui/app.js"
node --input-type=module - "$ui/recovery.js" <<'NODE'
import { pathToFileURL } from "node:url";
const recoveryPath = process.argv[2];
await import(pathToFileURL(recoveryPath));
const { classify, messageFor } = globalThis.BedrockRecovery;
const cases = [
  ["target has insufficient capacity", "insufficient-space"],
  ["The media write was interrupted or incomplete", "interrupted-write"],
  ["written media checksum does not match", "verification-failed"],
  ["selected target is mounted", "drive-unavailable"],
  ["administrator approval was cancelled", "approval-not-completed"],
  ["malformed progress sequence", "invalid-progress"],
  ["unexpected protected writer failure", "write-failed"],
];
for (const [input, expected] of cases) {
  if (classify(input).code !== expected) throw new Error(`${input}: expected ${expected}`);
  const message = messageFor(input);
  if (!message.includes("Do not boot from or use this drive")) throw new Error(`unsafe guidance: ${input}`);
  if (/ready|successful verification\.$/i.test(classify(input).title)) throw new Error(`false success: ${input}`);
}
NODE
grep -q 'bedrock://installer-progress' "$ui/app.js"
grep -q 'Rereading and verifying media' "$ui/app.js"
grep -q 'state.image.sizeBytes' "$ui/app.js"
grep -q 'choose_and_verify_image' "$ui/app.js"
grep -q 'list_targets' "$ui/app.js"
grep -q 'write_verified_image' "$ui/app.js"
grep -q 'event.target.value !== state.phrase' "$ui/app.js"
grep -q 'No drive is written until its full name is confirmed' "$ui/index.html"
grep -q 'aria-label="Explain confirmation"' "$ui/index.html"
grep -q 'Do not copy the ISO file onto the disc' "$ui/index.html"
grep -q 'Bedrock Installer does not write CDs or DVDs' "$ui/index.html"
grep -q 'renderProgress({ phase: "failed" })' "$ui/app.js"
if grep -Eq '\b(dd|diskutil|Get-Disk)\b' "$ui/app.js"; then
  printf 'error: installer UI bypasses the secure desktop bridge\n' >&2
  exit 1
fi
printf 'Bedrock graphical installer shell contract is valid.\n'
