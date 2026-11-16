import http from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {themePath,readThemeCss} from './theme-sync.mjs';
const root=fileURLToPath(new URL('./dist/',import.meta.url));
const port=Number(process.env.PORT||4173);
const files=['index.html','style.css','app.mjs','model.mjs'];
const server=http.createServer(async(req,res)=>{
 try{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/native-theme.css'){res.writeHead(200,{'Content-Type':'text/css; charset=utf-8','Cache-Control':'no-store'});res.end(await readThemeCss());return;}
 if(url.pathname==='/__revision'){const times=await Promise.all(files.map(async f=>(await stat(path.join(root,f))).mtimeMs));res.writeHead(200,{'Content-Type':'text/plain','Cache-Control':'no-store'});times.push((await stat(themePath)).mtimeMs);res.end(times.join(','));return;}
 const name=url.pathname==='/'?'index.html':decodeURIComponent(url.pathname.slice(1));
 if(!files.includes(name)){res.writeHead(404);res.end('Not found');return;}
 const body=await readFile(path.join(root,name));res.writeHead(200,{'Content-Type':name.endsWith('.html')?'text/html; charset=utf-8':name.endsWith('.css')?'text/css; charset=utf-8':'text/javascript; charset=utf-8','Cache-Control':'no-store'});res.end(body);
 }catch{res.writeHead(500);res.end('Unable to read demo file');}
});
server.listen(port,'127.0.0.1',()=>console.log(`ToDone Demo: http://127.0.0.1:${port}\n仅本机访问；Ctrl+C 停止。`));
server.on('error',e=>{console.error(e.code==='EADDRINUSE'?`端口 ${port} 已占用，请使用 PORT=4174 node demo/web/server.mjs`:e.message);process.exitCode=1;});
