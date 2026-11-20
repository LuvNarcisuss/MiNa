import {newId} from './ids';
import React, {ReactNode} from 'react';

export type Route = {name: string; id?: string};
export type ScreenProps = {route: Route; go: (name: string, id?: string) => void; back: () => void};
export const art = (group: string, index: number) => './art/' + group + '/' + index + '.webp';
export function Header({title,back,action}: {title:string;back?:()=>void;action?:ReactNode}) {
  return <header className="screen-header">{back ? <button aria-label="Back" onClick={back}><img src={art('edit',2)} alt=""/></button> : <span/>}<h1>{title}</h1><div>{action}</div></header>;
}
export function Empty({title,detail,children}: {title:string;detail?:string;children?:ReactNode}) {
  return <section className="empty-state"><img src={art('search',10)} alt=""/><h3>{title}</h3>{detail && <p>{detail}</p>}{children}</section>;
}
declare global {interface Window {ReactNativeWebView?:{postMessage:(message:string)=>void}}}
type Reply = {id:string;result?:unknown;error?:string};
const pending = new Map<string,(reply:Reply)=>void>();
window.addEventListener('mina:native',event=>{
  const reply=(event as CustomEvent<Reply>).detail;
  if (reply && typeof reply.id==='string') pending.get(reply.id)?.(reply);
});
export function native<T=unknown>(method:string,params:Record<string,unknown>={}):Promise<T> {
  if (!window.ReactNativeWebView) return Promise.reject(new Error('Open MiNa on your iPhone to use this feature.'));
  const id=newId();
  return new Promise((resolve,reject)=>{
    const timer=window.setTimeout(()=>{pending.delete(id);reject(new Error('This request timed out. Please try again.'));},method==='pickMedia'?300000:120000);
    pending.set(id,reply=>{
      clearTimeout(timer);pending.delete(id);
      if(reply.error) reject(new Error(typeof reply.error==='string'?reply.error:'The request could not be completed.'));
      else resolve(reply.result as T);
    });
    window.ReactNativeWebView!.postMessage(JSON.stringify({id,method,params}));
  });
}
let namespace='welcome';
let snapshot:Record<string,unknown>={};
let saving=Promise.resolve();
let backupFailed=false;
export async function useLibrary(id:string) {
  await saving;
  const saved=await native<{state:Record<string,unknown>|null}>('loadState');
  namespace=id;
  const local=localStorage.getItem('mina.v1.'+id);
  snapshot=saved.state || {};
  if(local){try{snapshot=JSON.parse(local);}catch{localStorage.removeItem('mina.v1.'+id);}}
  backupFailed=false;
}
export function read<T>(key:string,fallback:T):T {return (snapshot[key] as T)??fallback;}
export function write<T>(key:string,value:T) {
  const next={...snapshot,[key]:value};
  localStorage.setItem('mina.v1.'+namespace,JSON.stringify(next));snapshot=next;
  saving=saving.then(()=>native('saveState',{state:next})).then(()=>{backupFailed=false;}).catch(()=>{backupFailed=true;});
}
export async function flushLibrary(){await saving;if(backupFailed){await native('saveState',{state:snapshot});backupFailed=false;}}
export function clearLibrary(){localStorage.removeItem('mina.v1.'+namespace);snapshot={};}
export function errorText(error:unknown){return error instanceof Error?error.message:'Something went wrong. Please try again.';}
