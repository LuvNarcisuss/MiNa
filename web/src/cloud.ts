import {newId} from './ids';
import {native,flushLibrary} from './shared';

export const origin='https://nojpfyqctfwdshqnzudp.supabase.co';
const key='sb_publishable_XP-vFncNWgaYBdISstgW6w_2GjLgMDE';
type Session={access_token:string;refresh_token:string;expires_at?:number;expires_in:number;user:{id:string}};
let session:Session|null=null;
let renewal:Promise<Session>|undefined;
const errorMessage=(data:Record<string,string>)=>data.message||data.msg||data.error_description||data.error||'The service could not complete this request.';
async function auth(path:string,body:object):Promise<Session> {
  const res=await fetch(origin+'/auth/v1/'+path,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify(body)});
  const data=await res.json();
  if(!res.ok || !data.access_token || !data.user?.id)throw new Error(errorMessage(data));
  const fresh:Session={...data,expires_at:data.expires_at??Math.floor(Date.now()/1000)+data.expires_in};
  await native('setSession',{session:fresh});session=fresh;return fresh;
}
export function userId(){if(!session)throw new Error('Sign in to continue.');return session.user.id;}
export async function storedSession(){session=(await native<{session:Session|null}>('getSession')).session;return session;}
async function token() {
  if(!session) throw new Error('Sign in to continue.');
  if((session.expires_at||0)>Date.now()/1000+45) return session.access_token;
  renewal??=auth('token?grant_type=refresh_token',{refresh_token:session.refresh_token}).finally(()=>{renewal=undefined});
  return (await renewal).access_token;
}
export async function signIn(existing:boolean) {
  if(!existing && !session)await auth('signup',{data:{}});
  await rest('rpc/bootstrap',{method:'POST',body:'{}'});
  localStorage.removeItem('mina.locked');
  return userId();
}
export async function signOut() {
  await flushLibrary(); localStorage.setItem('mina.locked','1');session=null;
}
export async function request<T>(path:string,options:RequestInit={}):Promise<T>{
  const headers=new Headers(options.headers);
  headers.set('apikey',key);headers.set('Authorization','Bearer '+await token());
  if(typeof options.body==='string'&&!headers.has('Content-Type'))headers.set('Content-Type','application/json');
  const res=await fetch(origin+path,{...options,headers});
  if(!res.ok){const data=await res.json().catch(()=>({}));throw new Error(errorMessage(data));}
  const body=await res.text();return (body?JSON.parse(body):null) as T;
}
export function rest<T>(path:string,options:RequestInit={}):Promise<T>{return request('/rest/v1/'+path,options);}
export async function mediaUrl(path:string) {
  const data=await request<{signedURL:string}>('/storage/v1/object/sign/mina-media/'+path,{method:'POST',body:JSON.stringify({expiresIn:900})});
  return origin+'/storage/v1'+data.signedURL;
}
export async function uploadMedia(file:Blob,extension:string,stableId=newId() as string) {
  if(!/^[a-z0-9-]{1,70}$/i.test(stableId)||!/^\w{1,7}$/.test(extension))throw new Error('Invalid media name.');
  const path=userId()+'/'+stableId+'.'+extension;
  try{await request('/storage/v1/object/mina-media/'+path,{method:'POST',headers:{'Content-Type':file.type||'application/octet-stream'},body:file});}
  catch(error){if(!/already exists|duplicate/i.test(String(error)))throw error;}
  return path;
}
export async function removeAccount() {
  await request('/functions/v1/delete-account',{method:'POST',body:JSON.stringify({confirm:true})});
  await flushLibrary();await native('clearLocalData');await native('setSession',{session:null});session=null;
}
export async function subscribeInbox(onChange:()=>void) {
  const access=await token();
  const socket=new WebSocket(origin.replace('https:','wss:')+'/realtime/v1/websocket?apikey='+encodeURIComponent(key)+'&vsn=1.0.0');
  const channel='realtime:mina-inbox';
  socket.onopen=()=>socket.send(JSON.stringify({topic:channel,event:'phx_join',payload:{config:{postgres_changes:[{event:'INSERT',schema:'public',table:'messages'}]},access_token:access},ref:'1'}));
  socket.onmessage=event=>{try{const data=JSON.parse(event.data); if(data.event==='postgres_changes'||data.event==='phx_reply')onChange();}catch{}};
  const tick=window.setInterval(()=>{if(socket.readyState===1)socket.send(JSON.stringify({topic:'phoenix',event:'heartbeat',payload:{},ref:String(Date.now())}));},25000);
  return ()=>{clearInterval(tick);socket.close();};
}
