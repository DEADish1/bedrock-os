import assert from 'node:assert/strict';
import { readFile, readdir, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../dist/management-ui/', import.meta.url));
const html = await readFile(path.join(root, 'index.html'), 'utf8');
assert.match(html, /<html lang="en">/);
assert.match(html, /<div id="root"><\/div>/);
assert.doesNotMatch(html, /https?:\/\/|\/main\.tsx|@vite\/client/);
const references = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(match => match[1]);
assert(references.some(reference => reference.startsWith('/assets/') && reference.endsWith('.js')));
assert(references.some(reference => reference.startsWith('/assets/') && reference.endsWith('.css')));
for (const reference of references) {
  assert(reference.startsWith('/') && !reference.includes('..'));
  assert((await stat(path.join(root, reference.slice(1)))).size > 0);
}
const assets = await readdir(path.join(root, 'assets'));
assert(assets.some(name => name.startsWith('rfb-') && name.endsWith('.js')), 'guest-console code was not bundled');
assert(assets.every(name => !name.endsWith('.map')), 'installed UI must not ship source maps');
console.log('Installed UI artifact passed: local entry/assets, CSS, brand icon, and guest-console bundle.');
