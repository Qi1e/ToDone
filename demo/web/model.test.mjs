import {test} from 'node:test';
import assert from 'node:assert/strict';
import {dateResult,validateModule,upsert,validateDraft,newDraft,setModuleEnabled,finalizeModules} from './dist/model.mjs';
const today=new Date(2026,10,10,12);
test('日期以日历日计算，同日和到期后语义明确',()=>{
 assert.equal(dateResult({mode:'countdown',date:'2026-11-10'},today),'就是今天');
 assert.equal(dateResult({mode:'countdown',date:'2026-11-08'},today),'已过去 2 天');
 assert.equal(dateResult({mode:'elapsed',date:'2026-11-10'},today),'已过 0 天 · 起始当天为 0 天');
 assert.match(dateResult({mode:'deadline',date:'2026-11-10'},today),/今天截止/);
 assert.match(dateResult({mode:'deadline',date:'2026-11-10',withTime:true,time:'09:00'},today),/已逾期/);
});
test('日期校验不接受未来正数日和缺失时间',()=>{
 assert.ok(validateModule({type:'date',mode:'elapsed',date:'2026-11-11'},today));
 assert.ok(validateModule({type:'date',mode:'deadline',date:'2026-02-30'},today));
 assert.ok(validateModule({type:'date',mode:'deadline',date:'2026-11-10',withTime:true,time:''},today));
});
test('计数不接受空数值、负数和零步长',()=>{
 for(const [value,step] of [['',1],[-1,1],[0,0]])assert.ok(validateModule({type:'counter',value,step,unit:'次'}));
 assert.equal(validateModule({type:'counter',value:0,step:0.5,unit:'公里'}),'');
});
test('重试同一个事项不会重复，修改不改变其他事项',()=>{
 let records=upsert([{id:'b',title:'原事项'}],{id:'a',title:'第一次'});
 records=upsert(records,{id:'a',title:'重试'});
 assert.equal(records.length,2);assert.equal(records.find(r=>r.id==='a').title,'重试');assert.equal(records.find(r=>r.id==='b').title,'原事项');
 assert.deepEqual(upsert(records,{id:'b',title:'修改'}).map(r=>r.id),['b','a']);
});
test('仅名称可创建，空白名称不可创建',()=>{
 assert.equal(validateDraft({title:'读书',modules:[]}), '');assert.ok(validateDraft({title:'  ',modules:[]}));
});

test('各信息唯一，可同时启用；关闭后不参与创建，重新开启保留原输入',()=>{
 let d=setModuleEnabled(newDraft(),'counter',true);
 const id=d.modules[0].id;
 d.modules[0].unit='页'; d.modules[0].value='36';
 d=setModuleEnabled(d,'counter',true);
 assert.equal(d.modules.length,1);
 d=setModuleEnabled(d,'note',true);
 assert.equal(d.modules.length,2);
 d=setModuleEnabled(d,'counter',false);
 assert.equal(d.modules.length,1); assert.equal(d.scratch.counter.unit,'页');
 d=setModuleEnabled(d,'counter',true);
 assert.equal(d.modules.find(m=>m.type==='counter').id,id);
 assert.equal(d.modules.find(m=>m.type==='counter').value,'36');
 assert.equal(d.modules.filter(m=>m.type==='counter').length,1);
});

test('创建纳入列表末项且不修改草稿；数值转换在有效校验后进行',()=>{
 let d=setModuleEnabled(newDraft(),'list',true);
 d.modules[0].pending='带上相机';
 const one=finalizeModules(d.modules),two=finalizeModules(d.modules);
 assert.equal(one[0].items.length,1);assert.equal(two[0].items.length,1);
 assert.equal(d.modules[0].items.length,0);assert.equal(d.modules[0].pending,'带上相机');
 assert.equal(one[0].pending,'');
});

test('未填完的信息关闭后不阻塞创建，隐藏值不提交',()=>{
 let d=setModuleEnabled(newDraft(),'date',true); d.title='旅行';
 assert.ok(validateDraft(d));
 d=setModuleEnabled(d,'date',false);
 assert.equal(validateDraft(d),'');assert.deepEqual(finalizeModules(d.modules),[]);
});
