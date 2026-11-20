import React, {useEffect,useRef,useState} from 'react';
import {art,Header,ScreenProps,native,read,write,errorText} from './shared';

import {rest} from './cloud';

type Line={role:'user'|'assistant';text:string};
const topics=[
  {name:'Sleep Tips',group:'sleepTips',art:1,button:2,icon:11,summary:'Keep a regular sleep schedule, reduce screen time, relax before bed, and make your bedroom comfortable.'},
  {name:'Emotion',group:'emotion',art:1,button:2,icon:8,summary:'Allow your emotions, try relaxation techniques, talk about your feelings, notice positive moments, and get enough rest.'},
  {name:'Life Advice',group:'life',art:2,button:3,icon:9,summary:'Be kind to yourself, take breaks, notice positive moments, stay hydrated, move regularly, and make time for what you enjoy.'},
];
const suggestions=['Help me wind down','Give me a gentle writing prompt','Tell me a short bedtime story'];
export default function Companion({route,go,back}:ScreenProps) {
  const [topic,setTopic]=useState<number|null>(null);
  const [lines,setLines]=useState<Line[]>(()=>read('companion.history',[]));
  const [prompt,setPrompt]=useState(()=>read('companion.draft',''));
  const [busy,setBusy]=useState(false),[error,setError]=useState('');
  const [status,setStatus]=useState<{available:boolean;message?:string}|null>(null);
  const [expires,setExpires]=useState(0),[now,setNow]=useState(Date.now()),[dismissed,setDismissed]=useState(false);
  const remaining=Math.max(0,Math.ceil((expires-now)/1000));
  async function activate(){
    setError('');setBusy(true);
    try{const date=await rest<string>('rpc/open_companion_session',{method:'POST',body:'{}'});if(mounted.current){setExpires(Date.parse(date));setNow(Date.now());setDismissed(false)}}
    catch(e){if(mounted.current)setError(errorText(e))}finally{if(mounted.current)setBusy(false)}
  }
  useEffect(()=>{if(!expires)return;const timer=window.setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer)},[expires]);
  const [help,setHelp]=useState(false);
  const mounted=useRef(true),sending=useRef(false),end=useRef<HTMLDivElement>(null);
  useEffect(()=>{mounted.current=true;
    if(route.name==='ai.chat')native<{available:boolean;message?:string}>('companionStatus').then(s=>{if(mounted.current)setStatus(s)}).catch(e=>{if(mounted.current)setStatus({available:false,message:errorText(e)})});
    return ()=>{mounted.current=false};
  },[route.name]);
  useEffect(()=>{end.current?.scrollIntoView({block:'nearest'});},[lines,busy]);
  async function send(text:string){
    const message=text.trim();if(!message||sending.current||!status?.available||Date.now()>=expires)return;
    sending.current=true;setBusy(true);setError('');
    try {
      const reply=await native<{text:string}>('companionReply',{prompt:message,history:lines.slice(-8)});
      if(!mounted.current)return;
      if(!reply.text?.trim())throw new Error('No reply arrived. Try again.');
      const updated:Line[]=[...lines,{role:'user',text:message},{role:'assistant',text:reply.text}];
      write('companion.history',updated);write('companion.draft','');setLines(updated);setPrompt('');
    }catch(e){if(mounted.current)setError(errorText(e));}finally{sending.current=false;if(mounted.current)setBusy(false);}
  }
  if(route.name==='ai.chat')return <section className="companion-chat">
    <Header title="MiNa Companion" back={back} action={<button onClick={()=>setHelp(!help)} aria-label="About this conversation">?</button>}/>
    <img className="companion-heading" src={art('aiChat',2)} alt="AI companionship"/>
    {status?.available&&<div className="note">{remaining>0?<span>Time remaining · {Math.floor(remaining/60)}:{String(remaining%60).padStart(2,'0')}</span>:<button disabled={busy} onClick={activate}>{expires?'Start another free hour':'Begin a free 60-minute session'}</button>}</div>}
    {remaining>0&&remaining<600&&!dismissed&&<aside className="note">Less than 10 minutes remain. Your conversation will stay here.<button onClick={()=>setDismissed(true)}>Got it</button></aside>}
    {help&&<aside className="note">Replies are generated on this iPhone with Apple Intelligence. Your conversation stays on this device.</aside>}
    <div className="chat-lines">{!lines.length&&<p className="chat-intro">What’s on your mind tonight?</p>}{lines.map((line,i)=><p key={i} className={'bubble '+line.role}>{line.text}</p>)}{busy&&<p className="bubble assistant" role="status">Thinking…</p>}<div ref={end}/></div>
    {status?.available===false&&<div className="note">{status.message||'On-device AI is unavailable on this iPhone.'} <button onClick={back}>Browse topics</button></div>}
    {error&&<p className="error" role="alert">{error}</p>}
    <div className="prompts">{suggestions.map(s=><button key={s} disabled={!status?.available||busy||!remaining} onClick={()=>{setPrompt(s);write('companion.draft',s)}}>{s}</button>)}</div>
    <form className="compose-bar" onSubmit={e=>{e.preventDefault();void send(prompt)}}><input aria-label="Message to MiNa" value={prompt} maxLength={1600} placeholder="Share a thought…" onChange={e=>{setPrompt(e.target.value);write('companion.draft',e.target.value)}}/><button disabled={busy||!prompt.trim()||!status?.available||!remaining} aria-label="Send message"><img src={art('aiChat',6)} alt=""/></button></form>
  </section>;
  return <section className="companion-landing" aria-label="Talk to AI">
    <div className="companion-actions"><button className="art-button start-chat" onClick={()=>go('ai.chat')}><img src={art('ai',7)} alt="Start chat"/></button>
    <h2>Popular topics</h2><div className="topic-grid">{topics.map((t,i)=><button className="art-button" key={t.name} onClick={()=>setTopic(i)}><img src={art('ai',t.icon)} alt={t.name}/></button>)}</div></div>
    {topic!==null&&<div className="topic-overlay" role="dialog" aria-modal="true" aria-label={topics[topic].name}><img className="topic-poster" src={art(topics[topic].group,topics[topic].art)} alt={topics[topic].summary}/><button className="art-button topic-affirm" aria-label="Done" onClick={()=>setTopic(null)}><img src={art(topics[topic].group,topics[topic].button)} alt=""/></button><button className="topic-close" aria-label="Close topic" onClick={()=>setTopic(null)}>×</button></div>}
  </section>;
}
