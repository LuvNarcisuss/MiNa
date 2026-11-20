import {build} from 'esbuild';
import {cp, mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.resolve(process.argv[2] ?? path.join(root, 'build', 'MiNaPages.zip'));
const stage = await mkdtemp(path.join(tmpdir(), 'mina-pages-'));
try {
  await cp(path.join(root, 'web/public'), stage, {recursive: true});
  await cp(path.join(root, 'web/index.html'), path.join(stage, 'index.html'));
  await build({
    absWorkingDir: root,
    entryPoints: ['web/src/main.tsx'],
    outfile: path.join(stage, 'app.js'),
    bundle: true,
    minify: true,
    platform: 'browser',
    external: ['./art/*', '../art/*'],
    format: 'iife',
    target: 'safari16',
    jsx: 'automatic',
    define: {'process.env.NODE_ENV': '"production"'},
    legalComments: 'eof',
  });
  await mkdir(path.dirname(output), {recursive: true});
  execFileSync('python3', [path.join(root, 'scripts/archive-pages.py'), stage, output]);
} finally {
  await rm(stage, {recursive: true, force: true});
}
