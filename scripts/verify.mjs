import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv.slice(2);
if (mode.length !== 1 || !['--environment', '--build'].includes(mode[0])) {
  console.error('用法：node scripts/verify.mjs --environment | --build');
  process.exit(2);
}
const configFile = path.join(root, 'tools.local.json');
let config = {};
if (fs.existsSync(configFile)) {
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8')); }
  catch (error) { console.error(`本机配置无法读取：${error.message}`); process.exit(2); }
}
function findOnPath(name) {
  const extensions = process.platform === 'win32' ? ['', '.exe', '.cmd', '.bat'] : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter).filter(Boolean)) {
    for (const extension of extensions) {
      const candidate = path.join(dir, name + extension);
      try {
        if (!fs.statSync(candidate).isFile()) continue;
        fs.accessSync(candidate, process.platform === 'win32' ? fs.constants.F_OK : fs.constants.X_OK);
        return candidate;
      } catch { /* Try next entry. */ }
    }
  }
  return null;
}
function validateBuild(build) {
  if (!build || typeof build.executable !== 'string' || !build.executable.trim() ||
      !Array.isArray(build.args) || !build.args.every(a => typeof a === 'string')) {
    throw new Error('未配置有效 build.executable 和 build.args；先在 DevEco 中取得并验证实际构建命令。');
  }
  if (/\.(cmd|bat)$/i.test(build.executable)) {
    throw new Error('不直接执行批处理文件。请使用实际可执行程序（例如 node.exe）及其 Hvigor 脚本参数。');
  }
  const executable = path.isAbsolute(build.executable) ? build.executable : findOnPath(build.executable);
  if (!executable || !fs.existsSync(executable)) throw new Error('找不到构建可执行程序。');
  if (build.timeoutMs !== undefined && (!Number.isInteger(build.timeoutMs) || build.timeoutMs < 1)) {
    throw new Error('build.timeoutMs 必须为正整数毫秒。');
  }
  return executable;
}
if (mode[0] === '--environment') {
  console.log(`Node ${process.version}；${process.platform}；仓库 ${root}`);
  let missing = false;
  for (const name of ['git', 'ohpm', 'hvigorw', 'hvigor', 'hdc']) {
    const found = findOnPath(name);
    console.log(`${name}: ${found || 'PATH 未发现（DevEco 内可能可用）'}`);
    if ((name === 'git' || name === 'ohpm' || name === 'hdc') && !found) missing = true;
  }
  try { validateBuild(config.build); console.log('本机构建入口已配置；尚未执行。'); }
  catch (error) { console.log(error.message); missing = true; }
  console.log('此检查不安装、不升级、不连接设备；发现工具不等于版本兼容或构建通过。本机路径仅用于排错，请勿公开敏感输出。');
  process.exitCode = missing ? 2 : 0;
} else {
  try {
    const executable = validateBuild(config.build);
    const docs = spawnSync(process.execPath, [path.join(root, 'scripts/check-docs.mjs')], { cwd: root, stdio: 'inherit' });
    if (docs.error || docs.status !== 0) throw new Error('文档检查未通过，未启动构建。');
    console.log('开始执行本机已确认的构建入口，工作目录 app/。');
    const result = spawnSync(executable, config.build.args, {
      cwd: path.join(root, 'app'), stdio: 'inherit', shell: false,
      timeout: config.build.timeoutMs ?? 600000
    });
    if (result.error) throw result.error;
    if (result.signal) throw new Error(`构建被信号终止：${result.signal}`);
    if (result.status !== 0) { console.error(`构建命令失败：${result.status}`); process.exitCode = result.status || 1; }
    else console.log('配置的构建命令退出码为 0；请核对日志与产物。此结果不代表实机验收通过。');
  } catch (error) { console.error(error.message); process.exitCode = 2; }
}
