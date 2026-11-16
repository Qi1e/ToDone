import { readFile } from 'node:fs/promises';

export const themePath = new URL('../../app/entry/src/main/ets/common/Theme.ets', import.meta.url);

// Read the original ArkUI design tokens. Do not keep a second palette in the Demo.
export function parseNativeTheme(source) {
  const result = {};
  for (const group of ['Colors', 'Radius', 'Space']) {
    const body = source.match(new RegExp(`export const ${group}[^=]*=\\s*\\{([^}]+)\\}`))?.[1];
    if (!body) throw new Error(`Theme.ets 缺少 ${group}`);
    result[group] = {};
    for (const match of body.matchAll(/(\w+)\s*:\s*(?:'([^']+)'|(\d+))/g)) {
      result[group][match[1]] = match[2] ?? Number(match[3]);
    }
    if (!Object.keys(result[group]).length) throw new Error(`无法读取 ${group}`);
  }
  return result;
}

export function themeCss(theme) {
  const names = { Colors: 'color', Radius: 'radius', Space: 'space' };
  return `/* Generated from app/entry/src/main/ets/common/Theme.ets */\n:root {\n${Object.entries(theme).flatMap(([group, values]) => Object.entries(values).map(([key, value]) => `  --${names[group]}-${key}: ${value}${typeof value === 'number' ? 'px' : ''};`)).join('\n')}\n}\n`;
}

export async function readThemeCss() {
  return themeCss(parseNativeTheme(await readFile(themePath, 'utf8')));
}
