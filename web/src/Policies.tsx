import React,{useState} from 'react';
import policies from './policies.json';
import {Header,ScreenProps,native,errorText} from './shared';
import {rest} from './cloud';

export function Legal({route,back}:ScreenProps){
  const key=route.name.split('.')[1] as keyof typeof policies,policy=policies[key]||policies.terms;
  const [error,setError]=useState('');
  return <section className="light-page"><Header title={policy.title} back={back}/><article className="policy white-card"><small>Effective November 20, 2026</small>{policy.sections.map(([label,text])=><section key={label}><h2>{label}</h2><p>{text}</p></section>)}{key!=='guidelines'&&<button className="outline" onClick={()=>native('showPolicy',{document:key}).catch(e=>setError(errorText(e)))}>Open PDF</button>}{error&&<p role="alert">{error}</p>}</article></section>;
}
export function Support({back}:ScreenProps){
  const [message,setMessage]=useState(''),[status,setStatus]=useState(''),[busy,setBusy]=useState(false);
  async function submit(){if(busy)return;setBusy(true);try{await rest('support_requests',{method:'POST',body:JSON.stringify({body:message.trim()})});setMessage('');setStatus('Your request has been received.')}catch(e){setStatus(errorText(e))}finally{setBusy(false)}}
  return <section className="light-page"><Header title="Contact us" back={back}/><form className="white-card" onSubmit={e=>{e.preventDefault();void submit()}}><label htmlFor="feedback">How can we help?</label><textarea id="feedback" className="support-body" required minLength={5} maxLength={2000} value={message} onChange={e=>setMessage(e.target.value)} placeholder="Describe your question or concern"/><button className="primary" disabled={busy||message.trim().length<5}>{busy?'Sending…':'Send request'}</button>{status&&<p role="status">{status}</p>}</form></section>;
}
