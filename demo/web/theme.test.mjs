import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parseNativeTheme,themeCss,themePath} from './theme-sync.mjs';

test('所有应用 CSS 设计值都能在原生主题中找到，避免两套视觉漂移',async()=>{
  const theme=parseNativeTheme(await readFile(themePath,'utf8'));
  const css=themeCss(theme);
  const ui=await readFile(new URL('./dist/style.css',import.meta.url),'utf8');
  const used=[...ui.matchAll(/var\((--(?:color|radius|space)-\w+)\)/g)].map(m=>m[1]);
  assert.ok(used.length>50);
  for(const name of new Set(used))assert.ok(css.includes(`${name}:`),`缺少原生主题值：${name}`);
  assert.ok(css.includes(`--color-primary: ${theme.Colors.primary};`));
  assert.ok(css.includes(`--radius-large: ${theme.Radius.large}px;`));
});

test('主题缺失时显式报错，不悄悄退回另一套配色',()=>{
  assert.throws(()=>parseNativeTheme(''),/缺少 Colors/);
});
