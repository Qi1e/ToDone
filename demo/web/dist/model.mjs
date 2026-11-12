export const types = {
  date: { name: '日期与天数', icon: '◷', help: '距离某天、已经过多久，或何时截止', shortHelp: '倒数、累计天数或截止' },
  counter: { name: '计数', icon: '#', help: '累计次数或数量' },
  list: { name: '列表', icon: '☷', help: '列出内容，也可以关联已有事项', shortHelp: '整理内容或关联事项' },
  record: { name: '记录', icon: '↺', help: '记下每次发生的时间' },
  note: { name: '备注', icon: '≡', help: '补充文字说明' }
};
export const modes = { countdown: '倒数日', elapsed: '正数日', deadline: '截止时间' };
export const uid = () => crypto.randomUUID();
export function newDraft() { return { id: uid(), title: '', modules: [], scratch: {} }; }
export function localDate(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
function dayNumber(date) { const [y,m,d]=date.split('-').map(Number); return Date.UTC(y,m-1,d)/86400000; }
export function dateResult(m, now = new Date()) {
  if (!m.date || !m.mode) return '选择方式和日期后，这里会显示结果';
  const days = dayNumber(m.date) - dayNumber(localDate(now));
  if(m.mode === 'elapsed') return `已过 ${-days} 天 · 起始当天为 0 天`;
  if(m.mode === 'countdown') return days === 0 ? '就是今天' : days > 0 ? `还有 ${days} 天` : `已过去 ${-days} 天`;
  if(m.withTime && m.time) return `${m.date} ${m.time} 截止 · ${new Date(`${m.date}T${m.time}`).getTime() < now.getTime() ? '已逾期' : days === 0 ? '今天截止' : `剩余 ${days} 天`}`;
  return `${m.date} 截止 · ${days < 0 ? '已逾期' : days === 0 ? '今天截止' : `剩余 ${days} 天`}`;
}
export function moduleName(m) { return `${m.type === 'date' ? modes[m.mode] || types.date.name : types[m.type].name}${m.name ? ` · ${m.name}` : ''}`; }
export function summary(m) {
  if(m.type==='date') return `${m.mode==='deadline' ? '' : `${m.date} · `}${dateResult(m)}`;
  if(m.type==='counter') return `${m.value} · 每次增加 ${m.step}`;
  if(m.type==='list') return m.items.length ? `共 ${m.items.length} 项 · ${m.items.slice(0,3).map(i=>(i.ref?'事项：':'文字：')+i.title).join('、')}` : '空列表，可随时添加内容';
  if(m.type==='record') return '点击「记录一次」，留下发生的时间';
  return m.text;
}
export function validateModule(m, now=new Date()) {
  if(m.type==='date') {
    if(!m.mode) return '请选择日期的用途';
    const parsed=new Date(`${m.date}T00:00:00`);
    if(!/^\d{4}-\d{2}-\d{2}$/.test(m.date || '') || Number.isNaN(parsed.getTime()) || localDate(parsed)!==m.date) return '请选择有效日期';
    if(m.mode==='elapsed' && m.date>localDate(now)) return '起始日期不能晚于今天';
    if(m.mode==='deadline' && m.withTime && !m.time) return '请选择具体时间';
  }
  if(m.type==='counter') {
    if(m.value === '' || !Number.isFinite(Number(m.value)) || Number(m.value)<0) return '初始数值必须是大于或等于 0 的数字';
    if(m.step === '' || !Number.isFinite(Number(m.step)) || Number(m.step)<=0) return '每次增加必须大于 0';
  }
  if(m.type==='note' && !m.text.trim()) return '请填写备注内容';
  return '';
}
export function upsert(records, matter) { const next=structuredClone(matter); return records.some(r=>r.id===matter.id) ? records.map(r=>r.id===matter.id?next:r) : [...records,next]; }
export function makeModule(type) {
  return { id:uid(), type, name:'', ...(type==='date'?{mode:'',date:'',time:'18:00',withTime:false}:type==='counter'?{value:0,unit:'次',step:1}:type==='list'?{items:[],pending:''}:type==='note'?{text:''}:{}) };
}
export function validateDraft(draft) {
  if(!draft.title.trim()) return '请先填写事项名称';
  if(new Set(draft.modules.map(m=>m.type)).size!==draft.modules.length) return '同一种信息只能启用一次，请关闭重复的信息后重新开启';
  for(const m of draft.modules) { const error=validateModule(m); if(error) return `${moduleName(m)}：${error}`; }
  return '';
}

// Enabled state is distinct from expansion. Disabled settings remain in scratch.
export function setModuleEnabled(draft, type, enabled) {
  if(!types[type]) throw new Error('未知的信息类型');
  const existing=draft.modules.find(m=>m.type===type);
  const scratch={...draft.scratch};
  if(enabled) {
    const module=existing || structuredClone(scratch[type] || makeModule(type));
    delete scratch[type];
    return {...draft, scratch, modules:existing ? draft.modules.filter(m=>m.type!==type || m===existing) : [...draft.modules,module]};
  }
  if(existing) scratch[type]=structuredClone(existing);
  return {...draft, scratch, modules:draft.modules.filter(m=>m.type!==type)};
}

export function finalizeModules(modules) {
  return modules.map(original=>{
    const m=structuredClone(original);
    if(m.type==='list' && m.pending?.trim()) m.items.push({id:uid(),title:m.pending.trim()});
    if(m.type==='list') m.pending='';
    if(m.type==='counter') {m.value=Number(m.value);m.step=Number(m.step);}
    return m;
  });
}
