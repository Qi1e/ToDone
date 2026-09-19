import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const required = ['AGENTS.md', 'README.md', 'PROJECT_SPEC.md', 'TODO.md', 'DECISIONS.md', 'CHANGELOG.md', 'docs/development.md'];
const errors = [];
for (const name of required) {
  if (!fs.existsSync(path.join(root, name))) errors.push(`缺少文件：${name}`);
}
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isSymbolicLink()) return [];
    if (entry.isDirectory()) return walk(full);
    return entry.name.endsWith('.md') ? [full] : [];
  });
}
const files = fs.readdirSync(root).filter(n => n.endsWith('.md')).map(n => path.join(root, n));
if (fs.existsSync(path.join(root, 'docs'))) files.push(...walk(path.join(root, 'docs')));
for (const file of files) {
  // Supported scope: inline Markdown file links outside fenced code blocks.
  const content = fs.readFileSync(file, 'utf8').replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, '');
  for (const match of content.matchAll(/!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)/g)) {
    const target = match[1].replace(/^<|>$/g, '');
    if (/^[a-z][a-z\d+.-]*:/i.test(target) || target.startsWith('//') || target.startsWith('#')) continue;
    let name;
    try { name = decodeURIComponent(target.split(/[?#]/)[0]); }
    catch { errors.push(`${path.relative(root, file)}：无效链接编码 ${target}`); continue; }
    const resolved = path.resolve(path.dirname(file), name);
    const relative = path.relative(root, resolved);
    if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      errors.push(`${path.relative(root, file)}：链接超出仓库 ${target}`);
    } else if (!fs.existsSync(resolved)) {
      errors.push(`${path.relative(root, file)}：链接不存在 ${target}`);
    }
  }
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`文档检查通过（${files.length} 个 Markdown 文件）。仅检查必需文件和行内本地链接路径，不验证锚点、外链或内容一致性。`);
}
