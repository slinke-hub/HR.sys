import { cp, mkdir, rm } from 'node:fs/promises';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolve(projectRoot, 'www');
const assetDirectories = ['css', 'images', 'js', 'templates'];
const rootFiles = ['index.html', 'manifest.json', 'offline.html', 'sw.js'];

if (!outputRoot.startsWith(`${projectRoot}\\`) && !outputRoot.startsWith(`${projectRoot}/`)) {
  throw new Error('Refusing to clean a mobile output directory outside the project.');
}

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });

for (const directory of assetDirectories) {
  await cp(resolve(projectRoot, directory), resolve(outputRoot, directory), { recursive: true });
}

for (const file of rootFiles) {
  await cp(resolve(projectRoot, file), resolve(outputRoot, file));
}

console.log('Mobile web bundle created in www/.');
