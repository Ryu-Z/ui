import { copyFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const files = [
  ['vendor/prompt/prompt-v1-latin-300.woff', 'dist/assets/fonts/prompt-v1-latin-300.woff'],
  ['vendor/prompt/prompt-v1-latin-300.woff2', 'dist/assets/fonts/prompt-v1-latin-300.woff2'],
  ['vendor/prompt/prompt-v1-latin-600.woff', 'dist/assets/fonts/prompt-v1-latin-600.woff'],
  ['vendor/prompt/prompt-v1-latin-600.woff2', 'dist/assets/fonts/prompt-v1-latin-600.woff2'],
  ['vendor/icons/fonts/rancher-icons.svg', 'dist/assets/fonts/rancher-icons.svg'],
  ['vendor/icons/fonts/rancher-icons.ttf', 'dist/assets/fonts/rancher-icons.ttf'],
  ['vendor/icons/fonts/rancher-icons.woff', 'dist/assets/fonts/rancher-icons.woff'],
];

for (const [source, target] of files) {
  const out = resolve(target);

  await mkdir(dirname(out), { recursive: true });
  await copyFile(resolve(source), out);
}
