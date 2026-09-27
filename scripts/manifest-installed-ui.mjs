import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../dist/management-ui/', import.meta.url));
const commit = process.env.BEDROCK_SOURCE_COMMIT;
assert.match(commit ?? '', /^[0-9a-f]{40}$/, 'BEDROCK_SOURCE_COMMIT must identify the source commit');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const files = [];
async function visit(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
    assert(!entry.isSymbolicLink(), 'installed assets must not contain symlinks');
    const relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) await visit(path.join(directory, entry.name), `${relative}/`);
    else {
      assert(entry.isFile() && relative !== 'build-manifest.json');
      const bytes = await readFile(path.join(directory, entry.name));
      files.push({ path: relative, size_bytes: bytes.length, sha256: sha256(bytes) });
    }
  }
}
await visit(root);
const lock = await readFile(new URL('../package-lock.json', import.meta.url));
await writeFile(path.join(root, 'build-manifest.json'), JSON.stringify({
  schema: 1, source_commit: commit, node_version: process.version,
  lock_sha256: sha256(lock), files,
}, null, 2) + '\n');
console.log(`Manifested ${files.length} installed UI files for ${commit}.`);
