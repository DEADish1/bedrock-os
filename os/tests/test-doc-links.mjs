#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const roots = ["docs", ".github/ISSUE_TEMPLATE"];
const files = ["CHANGELOG.md", "PROJECT-ROADMAP.md", "PRIVACY.md", "SECURITY.md", "SUPPORT.md", "THIRD-PARTY-NOTICES.md"];
for (const directory of roots) {
  for (const name of fs.readdirSync(path.join(root, directory))) {
    if (name.endsWith(".md")) files.push(path.join(directory, name));
  }
}
let checked = 0;
for (const relative of files) {
  const source = fs.readFileSync(path.join(root, relative), "utf8");
  for (const match of source.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
    const target = match[1].trim().replace(/^<|>$/g, "");
    if (/^(https?:|mailto:|#)/i.test(target)) continue;
    const local = decodeURIComponent(target.split("#", 1)[0]);
    if (!local) continue;
    const resolved = path.resolve(path.dirname(path.join(root, relative)), local);
    if (!resolved.startsWith(root + path.sep) || !fs.existsSync(resolved)) throw new Error(`${relative}: missing or unsafe link ${target}`);
    checked++;
  }
}
console.log(`Bedrock documentation links valid (${checked} local links).`);
