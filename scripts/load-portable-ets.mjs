import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { stripTypeScriptTypes } from 'node:module';

// 仅转换白名单中的无 SDK 依赖源码。此检查不是 ArkTS 编译器或 Hypium。
const sourceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../app/entry/src/main/ets');
const sources = [
  'model/Types', 'model/Defaults', 'contracts/MatterService',
  'domain/MatterLinks', 'domain/DefaultMatterService', 'mocks/MockMatterService'
];

export async function loadPortableEts() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'todone-business-'));
  try {
    const original = new Map(sources.map(name => [name,
      fs.readFileSync(path.join(sourceRoot, `${name}.ets`), 'utf8')]));
    const typeNames = new Map([...original].map(([name, source]) => [name,
      new Set([...source.matchAll(/export\s+(?:interface|type)\s+(\w+)/g)].map(match => match[1]))]));
    for (const name of sources) {
      const source = original.get(name);
      if (/from\s+['"]@(?:kit|ohos)[/.]/.test(source)) throw new Error(`业务源码依赖了设备 SDK：${name}`);
      // ArkTS 普通 import 可包含 interface；Node 类型擦除要求显式排除这些导入。
      const runtimeSource = source.replace(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?/g,
        (statement, symbols, relative) => {
          const target = path.posix.normalize(path.posix.join(path.posix.dirname(name), relative));
          const types = typeNames.get(target);
          if (!types) throw new Error(`业务源码导入不在白名单中：${name} -> ${relative}`);
          const values = symbols.split(',').map(symbol => symbol.trim()).filter(Boolean)
            .filter(symbol => !types.has(symbol.split(/\s+as\s+/)[0]));
          return values.length ? `import { ${values.join(', ')} } from '${relative}';` : '';
        });
      const transformed = stripTypeScriptTypes(runtimeSource, { mode: 'transform' })
        .replace(/(from\s+['"])(\.[^'"]+)(['"])/g, '$1$2.mjs$3');
      const target = path.join(temp, `${name}.mjs`);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, transformed);
    }
    const load = name => import(pathToFileURL(path.join(temp, `${name}.mjs`)).href);
    const modules = [];
    for (const name of sources) modules.push(await load(name));
    return { modules: Object.fromEntries(sources.map((name, i) => [name, modules[i]])),
      close: () => fs.rmSync(temp, { recursive: true, force: true }) };
  } catch (error) {
    fs.rmSync(temp, { recursive: true, force: true });
    throw error;
  }
}
