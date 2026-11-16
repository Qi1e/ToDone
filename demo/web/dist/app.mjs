import {types,modes,uid,newDraft,localDate,dateResult,moduleName,summary,validateModule,makeModule,validateDraft,upsert,setModuleEnabled,finalizeModules} from './model.mjs';

const $=selector=>document.querySelector(selector);
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const KEY='todone-creation-lab-v1';
let state={records:[],draft:null},storageProblem='';
try {
  const saved=JSON.parse(localStorage.getItem(KEY)||'null');
  if(saved && Array.isArray(saved.records)) state={...state,...saved};
} catch { storageProblem='无法读取本地数据。本次输入暂存在内存中。'; }
let draft=state.draft || newDraft();
let resume=Boolean(state.draft && (draft.title.trim() || draft.modules.length || Object.keys(draft.scratch||{}).length));
let screen='new',expandedType='',viewing=null,saving=false,saveError='',failNext=false,showValidation=false,toastTimer;
const panel=$('#panel');

function persist() {
  try {localStorage.setItem(KEY,JSON.stringify({...state,draft}));return true;}
  catch {toast('浏览器本地存储不可用，当前输入仍保留。');return false;}
}
function toast(message) {
  $('#toast').textContent=message;$('#toast').classList.add('visible');clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),3500);
}
function moduleOf(type) {return draft.modules.find(m=>m.type===type);}
function activeModule() {return moduleOf(expandedType);}
function field(label,key,value,extra='type="text"') {
  return `<label class="field">${label}<input ${extra} data-field="${key}" value="${escape(value)}"></label>`;
}
function moduleSummary(m) {
  return hasResult(m) ? summary(m) : '';
}
function hasResult(m) {
  if(validateModule(m))return false;
  if(m.type==='list')return m.items.length>0;
  if(m.type==='record')return Boolean(m.name?.trim());
  return true;
}
function resultText(m) {
  if(m.type==='date')return dateResult(m);
  if(m.type==='counter')return `当前为 ${m.value||0}，每次点击增加 ${m.step||0}`;
  if(m.type==='list')return `列表包含 ${m.items.length} 项，移除关联不会删除原事项`;
  if(m.type==='record')return '保留每次发生的时间，方便以后回看';
  return m.text ? '这段文字将保存在事项中' : '填写的文字会随事项一起保存';
}

function pickerField(label,kind,value) {
  return `<div class="field">${label}<button class="picker-trigger" aria-haspopup="dialog" aria-label="${label}：${escape(value||'未选择')}" data-action="pick-${kind}">${escape(value||'请选择')} <span aria-hidden="true">⌄</span></button></div>`;
}
const pad=n=>String(n).padStart(2,'0');
function options(min,max,selected) {
  return Array.from({length:max-min+1},(_,i)=>`<option value="${i+min}" ${i+min===selected?'selected':''}>${pad(i+min)}</option>`).join('');
}
function column(label,id,min,max,value) {
  return `<label>${label}<select size="5" id="pick-${id}">${options(min,max,value)}</select></label>`;
}
function dateLimit(m){return m.mode==='elapsed'?localDate():'2100-12-31';}
function showPicker(kind,m) {
  let columns;
  if(kind==='date'){
    const limit=dateLimit(m),initial=m.date&&m.date<=limit?m.date:localDate();
    const [y,mo,d]=initial.split('-').map(Number),[ly,lm,ld]=limit.split('-').map(Number);
    columns=column('年','year',1900,ly,y)+column('月','month',1,y===ly?lm:12,mo)+column('日','day',1,y===ly&&mo===lm?ld:new Date(y,mo,0).getDate(),d);
  }else{
    const [h,min]=(m.time||'18:00').split(':').map(Number);
    columns=column('时','hour',0,23,h)+column('分','minute',0,59,min);
  }
  open(header(kind==='date'?'选择日期':'选择时间','close',false)+`<div class="panel-body picker-columns">${columns}</div><div class="panel-footer"><button class="primary" data-action="confirm-${kind}">确定</button></div>`);
}
function updateDateColumns(){
  const [ly,lm,ld]=dateLimit(activeModule()).split('-').map(Number);
  const y=Number($('#pick-year').value),month=$('#pick-month'),day=$('#pick-day');
  const maxMonth=y===ly?lm:12,mo=Math.min(Number(month.value),maxMonth);
  const maxDay=y===ly&&mo===lm?ld:new Date(y,mo,0).getDate();
  month.innerHTML=options(1,maxMonth,mo);day.innerHTML=options(1,maxDay,Math.min(Number(day.value),maxDay));
}
function formContent(m) {
  let content='';

 if(m.type==='date') {
   content=`<p class="panel-subtitle">你想怎样使用这个日期？</p>${Object.entries(modes).map(([mode,name])=>`<label class="mode-option"><input type="radio" name="date-mode" value="${mode}" ${m.mode===mode?'checked':''}><span><strong>${name}</strong><small>${mode==='countdown'?'看距离某一天还有多少天':mode==='elapsed'?'看从某一天起已经过多少天':'标记最晚何时完成'}</small></span></label>`).join('')}`;
   if(m.mode) content+=`<div style="margin-top:24px">${pickerField(m.mode==='elapsed'?'起始日期':m.mode==='deadline'?'截止日期':'目标日期','date',m.date)}${m.mode==='deadline'?`<label class="field"><input type="checkbox" data-field="withTime" ${m.withTime?'checked':''}>设置具体时间</label>${m.withTime?pickerField('具体时间','time',m.time):''}`:''}${field('日期名称（可选）','name',m.name,' maxlength="30"')}</div>`;
 }else if(m.type==='counter') content=`${field('计数名称（可选）','name',m.name,' maxlength="30"')}${field('初始数值','value',m.value,'type="number" min="0" step="any"')}${field('每次增加','step',m.step,'type="number" min="0.001" step="any"')}`;
 else if(m.type==='note')content=`<label class="field">备注内容<textarea data-field="text" maxlength="5000">${escape(m.text)}</textarea></label>`;
 else if(m.type==='record')content=`${field('记录名称（可选）','name',m.name,' maxlength="30"')}`;
 else content=`<div class="inline-input"><input data-field="pending" aria-label="列表内容" maxlength="120" value="${escape(m.pending)}"><button data-action="add-item">添加</button></div><button class="text-button" style="margin:17px 0" data-action="link">↗ 关联已有事项</button>${m.items.length?m.items.map((i,index)=>`<div class="list-row" data-list-index="${index}"><span>${escape(i.title)}<small>${i.ref?'关联事项':'文字项'}</small></span>${!i.ref?`<button data-action="rename-item" data-index="${index}">修改</button>`:''}<button data-action="remove-item" data-index="${index}" aria-label="移除 ${escape(i.title)}">移除</button></div>`).join(''):''}`;
  return content;
}

function informationOptions() {
  const card=([type,definition])=>{
    const m=moduleOf(type),expanded=Boolean(m)&&expandedType===type;
    if(!m)return `<div class="information-slot available-slot" data-slot="${type}"><button class="available-option" data-action="expand" data-type="${type}" aria-label="启用${definition.name}"><span><strong>${definition.name}</strong><small>${definition.shortHelp||definition.help}</small></span><span class="disclosure" aria-hidden="true">⌄</span></button></div>`;
    return `<div class="information-slot" data-slot="${type}"><section class="information-item enabled ${showValidation&&validateModule(m)?'invalid-information':''}" data-card="${type}">
      <div class="information-row">
        <button class="information-heading" data-action="expand" data-type="${type}" aria-expanded="${expanded}" aria-controls="config-${type}">
          <span><span class="selected-label">已启用</span><strong id="heading-${type}">${definition.name}</strong><small id="summary-${type}" ${hasResult(m)?'':'hidden'}>${escape(moduleSummary(m))}</small></span>
          <span class="disclosure" aria-hidden="true">${expanded?'⌃':'⌄'}</span>
        </button>
        <label class="information-switch"><input type="checkbox" role="switch" data-enable="${type}" aria-label="启用${definition.name}" checked><span aria-hidden="true"></span></label>
      </div>
      <div id="config-${type}" class="inline-config" data-config-type="${type}" ${expanded?'':'hidden'}>${expanded?`
        <fieldset>${formContent(m)}</fieldset>
        <div class="preview" ${hasResult(m)?'':'hidden'}><span>设置结果</span><div data-result>${escape(resultText(m))}</div></div>`:''}</div>
      ${expanded?`<footer class="focus-footer"><span>修改自动保留</span><button class="quiet" data-action="expand" data-type="${type}">收起设置 ⌃</button></footer>`:''}
    </section></div>`;
  };
  const selected=draft.modules.map(m=>[m.type,types[m.type]]).filter(([,definition])=>definition);
  const available=Object.entries(types).filter(([type])=>!moduleOf(type));
  return `<div class="selected-stack">${selected.map(card).join('')}</div>${available.length?`<section class="available-tray" aria-label="待选信息"><div class="tray-heading"><span>${selected.length?'还可以启用':'选择需要的信息'}</span><span>可多选</span></div><div class="available-list">${available.map(card).join('')}</div></section>`:''}`;
}
function cards(modules) {
  return modules.map(m=>m.type==='list'?`<section class="content-card detail-list"><h3>${escape(moduleName(m))}</h3><p class="subtle-note">共 ${m.items.length} 项</p>${m.items.length?m.items.map(i=>`<div class="list-row"><span>${escape(i.title)}<small>${i.ref?'关联事项，独立保留':'文字项'}</small></span>${i.ref?`<button data-action="view" data-id="${i.ref}">打开</button>`:''}</div>`).join(''):'<p class="subtle-note">暂无列表内容</p>'}</section>`:`<div class="info-card"><span></span><span><strong>${escape(moduleName(m))}</strong><small>${escape(summary(m))}</small></span></div>`).join('');
}
function render() {
  const app=$('#app'),previousType=$('.focus-card')?.dataset.card;
  const currentScroll=app.scrollTop;
  const previousTop=$('.focus-card')?.getBoundingClientRect().top-app.getBoundingClientRect().top;
  const focused=document.activeElement;
  const restoreField=focused?.dataset.field;
  const restoreMode=focused?.name==='date-mode'?focused.value:null;
  $('#saved-count').textContent=state.records.length;
  if(screen==='new') {
    $('#app').innerHTML=`<div class="sheet"><header class="sheet-header"><button class="quiet" data-action="cancel" ${saving?'disabled':''}>返回</button><h2>新建事项</h2></header><div class="sheet-body">
      ${resume?'<div class="draft-banner">已恢复未完成的草稿<button data-action="discard-question">重新开始</button></div>':''}
      <div class="title-area"><label class="field-caption" for="matter-title">事项名称</label><input class="title-input" id="matter-title" maxlength="80" value="${escape(draft.title)}" ${saving?'disabled':''} autocomplete="off" aria-invalid="${showValidation&&!draft.title.trim()}"></div>
      <section class="information-settings"><h3 class="section-heading">事项信息<span class="section-count">${draft.modules.length?`已启用 ${draft.modules.length} 项`:'可选'}</span></h3><div class="information-options">${informationOptions()}</div></section>
      <button class="primary create-action" id="create" data-action="save" ${saving?'disabled':''}>${saving?'正在保存':state.records.some(r=>r.id===draft.id)?'保存修改':'创建事项'}</button>
      ${saveError?`<p class="error" role="alert">${escape(saveError)}</p>`:''}
    </div></div>`;
  } else if(screen==='library') {
    $('#app').innerHTML=`<div class="sheet"><header class="sheet-header"><h2>事项</h2><button class="primary" data-action="new">新建</button></header><div class="sheet-body">${state.records.length?state.records.slice().reverse().map(r=>`<button class="info-card" data-action="view" data-id="${r.id}"><span></span><span><strong>${escape(r.title)}</strong><small>${r.modules.length?r.modules.map(m=>escape(moduleName(m))).join(' · '):'暂无附加信息'}</small></span><span class="arrow">›</span></button>`).join(''):'<div class="blank">暂无事项，点击「新建」创建。</div>'}</div></div>`;
  } else {
    const r=state.records.find(r=>r.id===viewing);
    if(!r){screen='library';render();return;}
    $('#app').innerHTML=`<div class="sheet"><header class="sheet-header"><button class="quiet" data-action="library">返回</button><h2>事项详情</h2><button class="quiet" data-action="edit-matter">编辑</button></header><div class="sheet-body">${screen==='success'?'<div class="success"><h3>保存成功</h3><p>事项已保存。</p></div>':''}<div class="content-card"><h2 class="library-title">${escape(r.title)}</h2></div><div class="module-cards">${cards(r.modules)}</div>${!r.modules.length?'<p class="subtle-note">暂无附加信息，可在编辑中开启。</p>':''}<button class="primary small-primary" data-action="new">新建事项</button></div></div>`;
  }
  const active=screen==='new'&&expandedType&&$(`[data-card="${expandedType}"]`);
  // Keep ordinary edits where the user left them. Only opening/switching a
  // module explicitly aligns its heading; no scroll listener pulls users back.
  app.scrollTop=currentScroll;
  if(active){
    active.classList.add('focus-card');
    active.setAttribute('role','region');active.setAttribute('aria-labelledby',`heading-${expandedType}`);
    if(previousType!==expandedType){
      alignCard(active,16);
      active.querySelector('.information-heading').focus({preventScroll:true});
    }else{
      const control=restoreField?active.querySelector(`[data-field="${restoreField}"]`):restoreMode?active.querySelector(`[name="date-mode"][value="${restoreMode}"]`):null;
      control?.focus({preventScroll:true});
    }
  }else if(previousType&&screen==='new'){
    const summary=$(`[data-card="${previousType}"] .information-heading`)||$(`[data-type="${previousType}"]`);
    if(summary){
      // Keep the summary at its previous visible position, or bring it back
      // from above the viewport when collapsing from a long form's footer.
      alignCard(summary.closest('[data-card]')||summary,Math.max(16,Math.min(previousTop,app.clientHeight-summary.offsetHeight-16)));
      summary.focus({preventScroll:true});
    }
  }
}
function alignCard(card,inset){
  const app=$('#app');
  const top=card.getBoundingClientRect().top-app.getBoundingClientRect().top+app.scrollTop;
  // One atomic positioning step avoids animating through the old card's
  // removed height when switching between modules.
  app.scrollTo({top:Math.max(0,top-inset),behavior:'instant'});
}

// Auxiliary dialogs are only for data inspection, exit confirmation and picking a
// related matter. Information selection and all its configuration stay inline.
function positionPanel() {
  if(!panel.open)return;
  const rect=$('#viewport').getBoundingClientRect();
  panel.style.width=`${rect.width-2}px`;panel.style.left=`${rect.left+1}px`;
  panel.style.bottom=`${Math.max(0,window.innerHeight-rect.bottom+1)}px`;
  panel.style.maxHeight=`${Math.min(rect.height-32,window.innerHeight-32)}px`;
}
function open(html) {$('#panel-content').innerHTML=html;if(!panel.open)panel.showModal();$('#modal-shade').hidden=false;positionPanel();}
function header(title,back='close',showBack=true) {return `<header class="panel-head">${showBack?`<button data-action="${back}" aria-label="返回">‹</button>`:''}<h2 id="panel-title">${title}</h2><button data-action="close" aria-label="关闭面板">×</button></header>`;}
function close() {panel.close();$('#modal-shade').hidden=true;}
function refreshInline(m) {
  const area=$(`[data-config-type="${m.type}"]`);
  const brief=$(`#summary-${m.type}`);if(brief){brief.textContent=moduleSummary(m);brief.hidden=!hasResult(m);}
  if(area?.querySelector('[data-result]'))area.querySelector('[data-result]').textContent=resultText(m);
  if(area?.querySelector('.preview'))area.querySelector('.preview').hidden=!hasResult(m);
  if(showValidation&&area){
    $(`[data-card="${m.type}"]`)?.classList.toggle('invalid-information',Boolean(validateModule(m)));
  }
}
function toggleInformation(type,enabled) {
  draft=setModuleEnabled(draft,type,enabled);
  if(enabled)expandedType=type;else if(expandedType===type)expandedType='';
  saveError='';persist();render();
  $(`[data-enable="${type}"]`)?.focus({preventScroll:true});
}
function expand(type) {
  if(!moduleOf(type)){toggleInformation(type,true);return;}
  expandedType=expandedType===type?'':type;render();
}
function renderInline() {persist();render();}
function addItem() {
  const m=activeModule();if(!m||m.type!=='list'||!m.pending.trim())return;
  m.items.push({id:uid(),title:m.pending.trim()});m.pending='';renderInline();
  $('[data-field="pending"]')?.focus();
}
function linkPicker() {
  const m=activeModule();if(!m)return;
  const choices=state.records.filter(r=>r.id!==draft.id&&!r.modules.some(m=>m.type==='list'));
  open(`${header('关联已有事项')}<div class="panel-body">${choices.length?choices.map(r=>`<button class="option" data-action="pick-link" data-id="${r.id}" ${m.items.some(i=>i.ref===r.id)?'disabled':''}><span><strong>${escape(r.title)}</strong><small>${m.items.some(i=>i.ref===r.id)?'已关联':'点击加入当前列表'}</small></span></button>`).join(''):'<div class="blank">还没有可关联的事项。<br>先创建一个不含列表的事项，再回来关联。</div>'}</div>`);
}
function exitQuestion(next='library') {
  if(!draft.title.trim()&&!draft.modules.length&&!Object.keys(draft.scratch).length){screen=next;render();return;}
  open(`${header('保留这次未完成的创建？','close',false)}<div class="panel-body"><p class="panel-subtitle">${escape(draft.title||'未命名事项')}</p><div class="resume-actions"><button class="primary" data-action="keep" data-next="${next}">保留草稿</button><button class="quiet danger" data-action="discard" data-next="${next}">放弃</button></div></div>`);
}
async function save() {
  showValidation=true;
  const invalid=draft.modules.find(m=>validateModule(m));
  const relationError=moduleOf('list')&&state.records.some(r=>r.modules.some(m=>m.type==='list'&&m.items.some(i=>i.ref===draft.id)));
  const error=validateDraft(draft)||(relationError?'这个事项已被其他列表关联，不能再启用列表。':'');
  if(error){
    saveError='';expandedType=!draft.title.trim()?'':invalid?.type||(relationError?'list':'');render();
    if(relationError)$('[data-card="list"]')?.classList.add('invalid-information');
    if(!draft.title.trim()){$('#matter-title').focus();$('#app').scrollTop=0;}

    return;
  }
  saving=true;saveError='';render();await new Promise(r=>setTimeout(r,450));
  if(failNext){failNext=false;saving=false;saveError='模拟保存失败，输入已保留。点击「重试保存」继续，不会重复生成事项。';render();return;}
  const matter={id:draft.id,title:draft.title.trim(),modules:finalizeModules(draft.modules),createdAt:draft.createdAt||new Date().toISOString()};
  const records=upsert(state.records,matter).map(r=>({...r,modules:r.modules.map(m=>m.type==='list'?{...m,items:m.items.map(i=>i.ref===matter.id?{...i,title:matter.title}:i)}:m)}));
  try{localStorage.setItem(KEY,JSON.stringify({...state,records,draft:null}));}
  catch{saving=false;saveError='本地保存失败，请检查浏览器存储权限后重试。内容仍保留在当前页面。';render();return;}
  state.records=records;draft=newDraft();viewing=matter.id;screen='success';saving=false;resume=false;expandedType='';showValidation=false;render();
}
function example() {
  const date=new Date();date.setDate(date.getDate()+14);draft=newDraft();draft.title='周末去旅行';
  draft.modules=[{...makeModule('date'),mode:'countdown',date:localDate(date),name:'出发'},{...makeModule('list'),items:['订好车票','带上相机','选一家想去的小店'].map(title=>({id:uid(),title}))}];
  resume=false;saveError='';showValidation=false;expandedType='date';screen='new';persist();render();
}
function tools() {
  open(`${header('演示工具')}<div class="panel-body"><p class="panel-subtitle">这里的设置仅用于体验原型，数据保存在当前浏览器中。</p><label class="tool-row"><input id="fail-next" type="checkbox" ${failNext?'checked':''}>下一次保存模拟失败</label><button class="tool-row" data-action="seed">加入 2 个可关联的示例事项</button><button class="tool-row" data-action="export">查看当前草稿数据</button><button class="tool-row danger" data-action="reset-question">清空演示数据</button></div>`);
}
function renameItem(index) {
  const m=activeModule(),item=m?.items[index];if(!item)return;
  // Text editing stays in the same expanded list, with no nested page or dialog.
  const row=$(`[data-list-index="${index}"]`);
  row.innerHTML=`<input class="rename-input" aria-label="修改文字项" value="${escape(item.title)}" maxlength="120"><button data-action="rename-save" data-index="${index}">完成</button><button data-action="rename-cancel">取消</button>`;
  row.querySelector('input').focus();
}

document.addEventListener('input',event=>{
  const target=event.target;
  if(target.id==='matter-title'){draft.title=target.value;saveError='';persist();target.setAttribute('aria-invalid',String(showValidation&&!draft.title.trim()));return;}
  const key=target.dataset.field,m=activeModule();if(!key||!m||saving)return;
  m[key]=target.type==='checkbox'?target.checked:target.value;persist();
  if(key==='withTime'){render();return;}refreshInline(m);
});
document.addEventListener('change',event=>{
  if(saving)return;const target=event.target;
  if(target.dataset.enable){toggleInformation(target.dataset.enable,target.checked);return;}
  if(target.name==='date-mode') {
    const m=activeModule();if(!m)return;m.mode=target.value;renderInline();
  }
  if(target.id==='pick-year'||target.id==='pick-month')updateDateColumns();
  if(target.id==='fail-next')failNext=target.checked;
});
document.addEventListener('keydown',event=>{
  const focus=$('.focus-card');
  if(focus&&!panel.open){
    if(event.key==='Escape'){event.preventDefault();expand(expandedType);return;}

  }
  if(event.key==='Enter'&&event.target.dataset.field==='pending'){event.preventDefault();addItem();}
  if(event.key==='Enter'&&event.target.id==='matter-title')event.target.blur();
});
panel.addEventListener('close',()=>{$('#modal-shade').hidden=true;});
window.addEventListener('resize',positionPanel);window.addEventListener('scroll',positionPanel,true);
document.addEventListener('click',event=>{
  const button=event.target.closest('[data-action]');if(!button||saving)return;
  const action=button.dataset.action,m=activeModule();
  if(action==='expand')expand(button.dataset.type);
  else if(action==='close')close();
  else if(action==='add-item')addItem();
  else if(action==='remove-item'&&m){m.items.splice(Number(button.dataset.index),1);renderInline();}
  else if(action==='rename-item')renameItem(Number(button.dataset.index));
  else if(action==='rename-cancel')render();
  else if(action==='rename-save'&&m){const value=button.closest('.list-row').querySelector('input').value.trim();if(!value){toast('请填写列表内容');return;}m.items[Number(button.dataset.index)].title=value;renderInline();}
  else if((action==='pick-date'||action==='pick-time')&&m)showPicker(action.slice(5),m);
  else if((action==='confirm-date'||action==='confirm-time')&&m){
    const date=action==='confirm-date';
    if(date)m.date=[Number($('#pick-year').value),pad($('#pick-month').value),pad($('#pick-day').value)].join('-');
    else m.time=pad($('#pick-hour').value)+':'+pad($('#pick-minute').value);
    close();renderInline();$(date?'[data-action="pick-date"]':'[data-action="pick-time"]').focus({preventScroll:true});
  }
  else if(action==='link')linkPicker();
  else if(action==='pick-link'&&m){const r=state.records.find(r=>r.id===button.dataset.id);if(!m.items.some(i=>i.ref===r.id))m.items.push({id:uid(),ref:r.id,title:r.title});close();renderInline();}
  else if(action==='save')save();
  else if(action==='cancel')exitQuestion();
  else if(action==='library'){if(screen==='new')exitQuestion();else{screen='library';render();}}
  else if(action==='keep'){persist();resume=true;close();screen=button.dataset.next;render();}
  else if(action==='discard'){draft=newDraft();resume=false;expandedType='';saveError='';showValidation=false;persist();close();screen=button.dataset.next;render();}
  else if(action==='discard-question')open(`${header('重新开始？')}<div class="panel-body"><p class="panel-subtitle">当前草稿将被清空，已创建的事项不受影响。</p><button class="primary" data-action="discard" data-next="new">清空草稿并开始</button></div>`);
  else if(action==='new'){screen='new';render();$('#matter-title')?.focus();}
  else if(action==='view'){viewing=button.dataset.id;screen='detail';render();}
  else if(action==='edit-matter'){
    if(draft.title||draft.modules.length){toast('请先完成或放弃当前草稿，再编辑其他事项');return;}
    draft={...structuredClone(state.records.find(r=>r.id===viewing)),scratch:{}};screen='new';expandedType='';persist();render();
  }
  else if(action==='example'){if(draft.title||draft.modules.length)open(`${header('填入示例？')}<div class="panel-body"><p class="panel-subtitle">这会替换当前草稿，已创建的事项不会改变。</p><button class="primary" data-action="confirm-example">替换并填入</button></div>`);else example();}
  else if(action==='confirm-example'){close();example();}
  else if(action==='mobile'||action==='wide'){$('.stage').classList.toggle('mobile',action==='mobile');document.querySelectorAll('.view-toggle button').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));positionPanel();}
  else if(action==='tools')tools();
  else if(action==='seed'){for(const [id,title] of [['demo-book','读完一本喜欢的书'],['demo-exam','六级考试']])if(!state.records.some(r=>r.id===id))state.records.push({id,title,modules:[]});persist();close();render();toast('已加入可关联的示例事项');}
  else if(action==='export')open(`${header('当前草稿数据','tools')}<div class="panel-body"><p class="panel-subtitle">modules 只包含已启用的信息，scratch 保留关闭的信息配置，不会提交。</p><pre>${escape(JSON.stringify(draft,null,2))}</pre></div>`);
  else if(action==='reset-question')open(`${header('清空演示数据？','tools')}<div class="panel-body"><p class="panel-subtitle">清除本 Demo 的事项和草稿，不影响正式应用。</p><button class="primary" data-action="reset">确认清空</button></div>`);
  else if(action==='reset'){state={records:[],draft:null};draft=newDraft();resume=false;saveError='';failNext=false;expandedType='';showValidation=false;persist();close();screen='new';render();toast('演示数据已清空');}
});
const shade=document.createElement('div');shade.id='modal-shade';shade.className='modal-shade';shade.hidden=true;$('#viewport').append(shade);
render();if(storageProblem)toast(storageProblem);
let revision;setInterval(async()=>{try{const response=await fetch('/__revision');if(!response.ok)return;const next=await response.text();if(revision&&next!==revision){persist();location.reload();}revision=next;}catch{}},2000);
