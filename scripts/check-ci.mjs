import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
if (Number(process.versions.node.split('.')[0]) < 24) {
  console.error('可移植业务检查需要 Node 24+；原文档与本机构建检查仍可使用 Node 18+。');
  process.exit(2);
}
function run(args) {
  const result = spawnSync(process.execPath, args, { cwd: root, stdio: 'inherit', timeout: 120000 });
  if (result.error) console.error(result.error.message);
  if (result.error || result.status !== 0) process.exit(result.status || 1);
}
run(['scripts/check-docs.mjs']);
for (const file of fs.readdirSync(path.join(root, 'scripts')).filter(file => file.endsWith('.mjs'))) {
  run(['--check', `scripts/${file}`]);
}
run(['--test', 'tests/matter-service.test.mjs']);
console.log('可移植检查通过；不代表 ArkTS 编译、Hypium 或实机验收通过。');
