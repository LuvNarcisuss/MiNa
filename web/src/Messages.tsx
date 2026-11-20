import React, {useCallback, useEffect, useRef, useState} from 'react';
import {art, Empty, errorText, Header, native, read, ScreenProps, write} from './shared';
import {mediaUrl, rest, subscribeInbox, userId} from './cloud';
import {isUuid, makeId} from './roomSession';
import './messages.css';

type Person = {id:string;name:string;avatar_path:string;allow_calls:boolean;allow_messages:boolean};
type Message = {id:string;sender_id:string;recipient_id:string;body:string;created_at:string};
type Summary = {peer_id:string;latest_id:string;body:string;created_at:string;unread:number};
type Notice = {id:string;kind:'platform'|'follow'|'ranking';title:string;body:string;actor_id:string|null;created_at:string;read_at:string|null};
type Call = {id:string;caller_id:string;callee_id:string;state:string;offer:string|null;answer:string|null;created_at:string};
type Draft = {id:string;body:string};
const syncEvent = 'mina:inbox-refresh';
const json = (body:object):RequestInit => ({method:'POST',body:JSON.stringify(body)});
const rpc = <T,>(name:string,body:object={}) => rest<T>('rpc/'+name,json(body));
const refreshInbox = () => window.dispatchEvent(new Event(syncEvent));
const dateLabel = (value:string) => new Intl.DateTimeFormat('en',{month:'short',day:'numeric',hour:'numeric',minute:'2-digit'}).format(Date.parse(value));
const roomId = (body:string) => body.startsWith('mina:room:') && isUuid(body.slice(10)) ? body.slice(10) : '';
const preview = (body:string) => roomId(body) ? 'Voice room invitation' : body;
const mark = (peer:string,id:string,clear=false) => rpc('mark_conversation',{p_peer:peer,p_latest:id,p_clear:clear});
const action = (id:string,verb:string,sdp?:string) => rpc<string>('voice_action',{p_id:id,p_action:verb,p_sdp:sdp ?? null});
const personFields='id,name,avatar_path,allow_calls,allow_messages';
async function people(ids:string[]) {
  const values=[...new Set(ids.filter(isUuid))];
  const result:Record<string,Person>={};
  for(let i=0;i<values.length;i+=100) {
    const rows=await rest<Person[]>('profiles?select='+personFields+'&id=in.('+values.slice(i,i+100).join(',')+')');
    for(const row of rows)result[row.id]=row;
  }
  return result;
}
function useInboxData<T>(key:string,readServer:()=>Promise<T>,milliseconds=15000): {key:string;data?:T;error?:string} {
  const run=useRef(readServer);run.current=readServer;
  const [state,setState]=useState<{key:string;data?:T;error?:string}>({key:''});
  useEffect(()=>{
    let active=true,busy=false,pending=false;
    async function refresh() {
      if(!active || document.hidden)return;
      if(busy){pending=true;return;}
      busy=true;
      try{const data=await run.current();if(active)setState({key,data});}
      catch(e){if(active)setState({key,error:errorText(e)});}
      finally {busy=false;if(pending && active){pending=false;void refresh();}}
    }
    void refresh();
    const timer=window.setInterval(refresh,milliseconds);
    window.addEventListener(syncEvent,refresh);window.addEventListener('online',refresh);
    document.addEventListener('visibilitychange',refresh);
    return ()=>{active=false;clearInterval(timer);window.removeEventListener(syncEvent,refresh);
      window.removeEventListener('online',refresh);document.removeEventListener('visibilitychange',refresh);};
  },[key,milliseconds]);
  return state.key===key ? state : {key};
}
function Avatar({person,size=44}: {person?:Person;size?:number}) {
  const [image,setImage]=useState<{path:string;url:string}|null>(null);
  const path=person?.avatar_path;
  useEffect(()=>{
    let alive=true;
    if(path)mediaUrl(path).then(url=>{if(alive)setImage({path,url});}).catch(()=>{});
    return ()=>{alive=false;};
  },[path]);
  return <span className="im-avatar" style={{width:size,height:size}}>{path && image?.path===path ?
    <img src={image.url} alt=""/> : (person?.name?.slice(0,1) || '☾')}</span>;
}
function Img({group,index}: {group:string;index:number}) {return <img className="im-icon" src={art(group,index)} alt=""/>;}
function Status({error}: {error?:string}) {return <div className="im-status" role="status">{error ? <>{error}<button onClick={refreshInbox}>Try again</button></> : 'Loading…'}</div>;}
function incoming() {
  const cutoff=encodeURIComponent(new Date(Date.now()-50000).toISOString());
  return rest<Pick<Call,'id'|'caller_id'>[]>('voice_calls?select=id,caller_id&callee_id=eq.'+userId()+'&state=eq.ringing&created_at=gte.'+cutoff+'&order=created_at.desc&limit=1');
}
export function IncomingCallNotice({route,go}: Pick<ScreenProps,'route'|'go'>) {
  const me=userId();
  const [ring,setRing]=useState<{id:string;caller:string}|null>(null);
  const [error,setError]=useState('');
  useEffect(()=>{
    let alive=true,swapping=false,ringBusy=false,disposer:(()=>void)|undefined;
    let revision=0;
    async function connect(){
      if(!alive || document.hidden || swapping)return;
      swapping=true;
      const epoch=++revision;
      disposer?.();disposer=undefined;
      try{const off=await subscribeInbox(()=>{if(alive && revision===epoch)refreshInbox();});
        if(!alive || epoch!==revision)off();else disposer=off;
      }catch{}finally{swapping=false;}
    }
    async function check(){
      if(!alive || document.hidden || ringBusy)return;
      ringBusy=true;
      try{
        const [row]=await incoming();
        const person=row ? (await people([row.caller_id]))[row.caller_id] : undefined;
        if(alive)setRing(row ? {id:row.id,caller:person?.name || 'Night listener'} : null);
      }catch{if(alive)setRing(null);}
      finally{ringBusy=false;}
    }
    const wake=()=>{
      if(document.hidden){revision++;disposer?.();disposer=undefined;}
      else {void connect();void check();refreshInbox();}
    };
    void connect();void check();
    const timer=setInterval(check,4500),reconnect=setInterval(connect,180000);
    window.addEventListener('online',wake);document.addEventListener('visibilitychange',wake);
    return ()=>{alive=false;revision++;clearInterval(timer);clearInterval(reconnect);disposer?.();
      window.removeEventListener('online',wake);document.removeEventListener('visibilitychange',wake);};
  },[me]);
  if(!ring || route.name==='messages.call')return null;
  const inAudio=route.name.startsWith('rooms.live') || route.name==='dreams.record';
  return <aside className="im-ring" aria-live="polite"><strong>{ring.caller} is calling</strong>
    {inAudio && <p>Opening the call will leave your current audio session.</p>}
    {error && <p>{error}</p>}<div><button onClick={async()=>{try{await action(ring.id,'decline');setRing(null);setError('');}catch(e){setError(errorText(e));}}}>Decline</button>
      <button onClick={()=>{setError('');go('messages.call',ring.id);}}>Open call</button></div></aside>;
}
function Inbox({go}: ScreenProps) {
  const [query,setQuery]=useState('');
  const [selected,setSelected]=useState<Summary|null>(null);
  const [error,setError]=useState('');
  const startX=useRef(0);
  const [revealed,setRevealed]=useState('');
  const me=userId();
  const result=useInboxData('inbox:'+me,async()=>{
    const [rows,following,newNotices]=await Promise.all([rpc<Summary[]>('inbox_summary'),
      rest<{followed_id:string}[]>('follows?select=followed_id&follower_id=eq.'+me+'&order=created_at.desc&limit=25'),
      rest<{id:string}[]>('account_notices?select=id&read_at=is.null&limit=1000')]);
    const members=await people([...rows.map(r=>r.peer_id),...following.map(f=>f.followed_id)]);
    return {rows,members,following,newNotices:newNotices.length};
  });
  const data=result.data;
  const term=query.trim().toLowerCase();
  const filtered=data?.rows.filter(row=>(data.members[row.peer_id]?.name||'Night listener').toLowerCase().includes(term) || preview(row.body).toLowerCase().includes(term)) || [];
  async function markAll(){
    if(!data)return;
    try{
      for(const row of data.rows.filter(r=>r.unread>0))await mark(row.peer_id,row.latest_id);
      await rest('account_notices?owner_id=eq.'+me+'&read_at=is.null',{method:'PATCH',body:JSON.stringify({read_at:new Date().toISOString()})});
      refreshInbox();
    }catch(e){setError(errorText(e));refreshInbox();}
  }
  return <><div className="im-inbox-head"><div><h1>Messages</h1><button className="im-recent-calls" onClick={()=>go('messages.calls')}>Calls</button><button aria-label="Mark all as read" onClick={markAll}><Img group="inbox" index={2}/></button></div>
    <label className="im-search"><Img group="inbox" index={11}/><input value={query} onChange={e=>setQuery(e.target.value)} type="search" placeholder="Search conversations" aria-label="Search conversations"/></label>
    {!!data?.following.length && <div className="im-strip">{data.following.filter(f=>data.members[f.followed_id]).map(f=><button key={f.followed_id} onClick={()=>go('messages.thread',f.followed_id)}>
      <Avatar person={data.members[f.followed_id]} size={48}/><small>{data.members[f.followed_id].name}</small></button>)}</div>}</div>
    <button className="im-summary im-notice-shortcut" onClick={()=>go('messages.notices')}><Img group="inbox" index={5}/><span><strong>System notifications</strong><small>Announcements, follows and rankings</small></span>
      {!!data?.newNotices && <b className="im-badge">{data.newNotices}</b>}</button>
    {(!data || result.error) && <Status error={result.error}/>}
    {filtered.map(row=><div className="im-thread-row" key={row.peer_id} onTouchStart={e=>{startX.current=e.touches[0].clientX;}}
      onTouchEnd={e=>{const dx=e.changedTouches[0].clientX-startX.current;if(dx< -38)setRevealed(row.peer_id);else if(dx>38)setRevealed('');}}>
      <button className="im-summary" onClick={()=>go('messages.thread',row.peer_id)}><Avatar person={data?.members[row.peer_id]}/>
        <span><strong>{data?.members[row.peer_id]?.name || 'Night listener'}</strong><small>{preview(row.body)}</small></span>
        <span className="im-row-meta"><time>{dateLabel(row.created_at)}</time>{row.unread>0 && <b className="im-badge">{row.unread}</b>}</span></button>
      <button className="im-row-option" aria-label="Conversation options" aria-expanded={revealed===row.peer_id} onClick={()=>setRevealed(revealed===row.peer_id ? '' : row.peer_id)}>⋯</button>
      {revealed===row.peer_id && <button className="im-delete" aria-label="Delete my copy" onClick={()=>setSelected(row)}><Img group="inbox" index={4}/></button>}</div>)}
    {data && !filtered.length && <Empty title={term?'No matching conversations':'No conversations yet'} detail={term?'Try another name or message.':'Open a profile to start a conversation.'}/>}
    {selected && <div className="im-sheet" role="dialog" aria-label="Delete conversation"><strong>Delete your copy?</strong><p>This clears your conversation through the selected message. The other person keeps their copy.</p>
      <button onClick={async()=>{try{await mark(selected.peer_id,selected.latest_id,true);setSelected(null);setRevealed('');refreshInbox();}catch(e){setError(errorText(e));}}}>Delete my copy</button>
      <button onClick={()=>setSelected(null)}>Keep conversation</button></div>}
    {error && <button className="im-error" onClick={()=>setError('')}>{error} · Dismiss</button>}</>;
}
function Thread({route,go,back}:ScreenProps) {
  const peer=route.id || '',me=userId(),draftKey='chat.draft.'+peer;
  const fresh=()=>({id:makeId(),body:''});
  const [draft,setDraft]=useState<Draft>(()=>read(draftKey,fresh()));
  const [error,setError]=useState(''),[busy,setBusy]=useState(false),[emoji,setEmoji]=useState(false),[options,setOptions]=useState(false);
  const [older,setOlder]=useState<Message[]>([]);
  const previous=useRef<{recent:Message[];cleared:string}>({recent:[],cleared:''});
  const [olderEnd,setOlderEnd]=useState(false);
  const [callConsent,setCallConsent]=useState(false);
  const lastBubble=useRef<HTMLDivElement>(null);
  const nearEnd=useRef(true);
  const callIntent=useRef('');
  const lastRead=useRef('');
  const op=useRef(false);
  const result=useInboxData('chat:'+me+':'+peer,async()=>{
    if(!isUuid(peer) || peer===me)throw new Error('Conversation unavailable.');
    const [profiles,recent,markers]=await Promise.all([people([peer]),rpc<Message[]>('chat_history',{p_peer:peer,p_take:50}),
      rest<{cleared_at:string;cleared_id:string}[]>('conversation_state?select=cleared_at,cleared_id&owner_id=eq.'+me+'&peer_id=eq.'+peer)]);
    const marker=markers[0];
    const cleared=marker && marker.cleared_at!=='-infinity' ? marker.cleared_at+'|'+marker.cleared_id : '';
    if(previous.current.cleared!==cleared){setOlder([]);setOlderEnd(false);}
    else if(previous.current.recent.length && recent.some(m=>previous.current.recent.some(old=>old.id===m.id))){
      const displaced=previous.current.recent.filter(old=>!recent.some(m=>m.id===old.id));
      if(displaced.length)setOlder(rows=>Array.from(new Map([...rows,...displaced].map(m=>[m.id,m])).values()));
    }else if(previous.current.recent.length){setOlder([]);setOlderEnd(false);}
    previous.current={recent,cleared};
    const person=profiles[peer];
    if(!person)throw new Error('This profile is unavailable.');
    return {person,recent};
  },10000);
  const person=result.data?.person;
  const list=Array.from(new Map([...older,...(result.data?.recent || [])].map(m=>[m.id,m])).values()).sort((a,b)=>a.created_at.localeCompare(b.created_at)||a.id.localeCompare(b.id));
  useEffect(()=>{
    const screen=lastBubble.current?.closest('main');
    if(!screen)return;
    const detect=()=>{nearEnd.current=screen.scrollHeight-screen.scrollTop-screen.clientHeight<150;};
    screen.addEventListener('scroll',detect,{passive:true});
    return ()=>screen.removeEventListener('scroll',detect);
  },[!!result.data]);
  useEffect(()=>{
    const latest=result.data?.recent[0];
    if(!latest)return;
    if(nearEnd.current || latest.sender_id===me)lastBubble.current?.scrollIntoView({block:'end'});
    const screen=lastBubble.current?.closest('main');
    let current=true,inflight=false;
    const acknowledge=()=>{
      if(!current || document.hidden || !nearEnd.current || inflight || lastRead.current===latest.id)return;
      inflight=true;
      void mark(peer,latest.id).then(()=>{if(current)lastRead.current=latest.id;}).catch(e=>{
        if(current)setError(errorText(e));
      }).finally(()=>{inflight=false;});
    };
    const frame=requestAnimationFrame(acknowledge);
    screen?.addEventListener('scroll',acknowledge,{passive:true});
    document.addEventListener('visibilitychange',acknowledge);
    return ()=>{current=false;cancelAnimationFrame(frame);screen?.removeEventListener('scroll',acknowledge);
      document.removeEventListener('visibilitychange',acknowledge);};
  },[result.data?.recent[0]?.id,me,peer]);
  function edit(next:Draft){
    try{write(draftKey,next);setDraft(next);return true;}catch{setError('Your draft could not be saved on this iPhone.');return false;}
  }
  async function send(){
    if(op.current || !draft.body.trim() || !person?.allow_messages)return;
    op.current=true;setBusy(true);setError('');
    try{
      const saved=await rpc<string>('send_message',{p_id:draft.id,p_peer:peer,p_body:draft.body.trim()});
      if(saved!==draft.id)throw new Error('The message could not be confirmed.');
      edit(fresh());setEmoji(false);refreshInbox();
    }catch(e){setError(errorText(e));}finally{op.current=false;setBusy(false);}
  }
  async function dial(){
    if(op.current || !person?.allow_calls)return;
    op.current=true;setBusy(true);setError('');
    try{callIntent.current ||= makeId();const id=await rpc<string>('start_voice_call',{p_id:callIntent.current,p_peer:peer});callIntent.current='';go('messages.call',id);}
    catch(e){setError(errorText(e));}finally{op.current=false;setBusy(false);setCallConsent(false);}
  }
  return <><Header title={person?.name || 'Conversation'} back={back} action={<button aria-label="Conversation options" onClick={()=>setOptions(!options)}><Img group="chat" index={3}/></button>}/>
    {options && <div className="im-tools"><button onClick={()=>go('person',peer)}>Profile and safety</button></div>}
    {(!result.data || result.error) && <Status error={result.error}/>}
    {person && <div className="im-profile"><button aria-label="Open profile" onClick={()=>go('person',peer)}><Avatar person={person} size={84}/></button>
      <button className="im-phone" disabled={!person.allow_calls || busy} aria-label="Start voice call" onClick={()=>setCallConsent(true)}><Img group="chat" index={4}/></button>
      {!person.allow_calls && <small>Voice calls are off</small>}</div>}
    {result.data && <div className="im-history">{!olderEnd && result.data.recent.length===50 && <button onClick={async()=>{
      const first=list[0];if(!first)return;
      try{const rows=await rpc<Message[]>('chat_history',{p_peer:peer,p_take:50,p_before:first.created_at,p_id:first.id});
        setOlder(prev=>[...rows,...prev]);setOlderEnd(rows.length<50);}catch(e){setError(errorText(e));}
    }}>Earlier messages</button>}
      {list.map(m=><div key={m.id} className={'im-bubble '+(m.sender_id===me?'im-outgoing':'')}><small>{dateLabel(m.created_at)}</small>
        {roomId(m.body)?<button onClick={()=>go('rooms.live',roomId(m.body))}>Voice room invitation · Open room ›</button>:<p>{m.body}</p>}</div>)}
      {!list.length && <p className="im-first">Start your conversation.</p>}<div ref={lastBubble}/></div>}
    {callConsent && <div className="im-sheet" role="dialog" aria-label="Start voice call"><strong>Call {person?.name}?</strong><p>The call uses your microphone when both of you join.</p><button disabled={busy} onClick={dial}>Start voice call</button><button disabled={busy} onClick={()=>setCallConsent(false)}>Cancel</button></div>}
    {error && <button className="im-error" onClick={()=>setError('')}>{error} · Dismiss</button>}
    {person && <div className="im-input-area">{emoji && <div className="im-tools">{['🌙','✨','💚','😴','🌟','🫶'].map(v=><button disabled={busy} key={v} onClick={()=>edit({id:makeId(),body:(draft.body+v).slice(0,2000)})}>{v}</button>)}</div>}
      <form onSubmit={e=>{e.preventDefault();void send();}}><button type="button" aria-label="Choose an emoji" disabled={!person.allow_messages || busy} onClick={()=>setEmoji(!emoji)}><Img group="chat" index={5}/></button>
        <input aria-label="Message" value={draft.body} maxLength={2000} disabled={!person.allow_messages || busy} placeholder={person.allow_messages?'Message…':'Messages are off'} onChange={e=>edit({id:makeId(),body:e.target.value})}/>
        <button aria-label="Send message" disabled={!person.allow_messages || !draft.body.trim() || busy}><Img group="chat" index={6}/></button></form>
      {busy && <small>Connecting…</small>}</div>}</>;
}
function RecentCalls({go,back}:ScreenProps) {
  const me=userId();
  const result=useInboxData('calls:'+me,async()=>{
    const calls=await rest<Call[]>('voice_calls?select=id,caller_id,callee_id,state,created_at&or=(caller_id.eq.'+me+',callee_id.eq.'+me+')&order=created_at.desc&limit=100');
    const profiles=await people(calls.map(c=>c.caller_id===me ? c.callee_id : c.caller_id));
    return {calls,profiles};
  });
  return <><Header title="Recent calls" back={back}/>
    {(!result.data || result.error) && <Status error={result.error}/>}
    {result.data?.calls.map(c=>{
      const outgoing=c.caller_id===me,peer=outgoing?c.callee_id:c.caller_id;
      const name=result.data?.profiles[peer]?.name || 'Night listener';
      const stale=c.state==='ringing' && Date.now()-Date.parse(c.created_at)>45000;
      const label=stateTitles[c.state] || (stale?'Invitation expired':c.state==='accepted'?'Accepted':outgoing?'Calling':'Incoming call');
      return <button className="im-summary" key={c.id} onClick={()=>
        activeCall(c.state) && !stale ? go('messages.call',c.id) : go('messages.thread',peer)}>
        <Avatar person={result.data?.profiles[peer]}/><span><strong>{name}</strong><small>{outgoing?'Outgoing':'Incoming'} · {label}</small></span>
        <time>{dateLabel(c.created_at)}</time></button>;
    })}
    {result.data && !result.data.calls.length && <Empty title="No calls yet" detail="Start a voice call from a conversation."/>}</>;
}
const categories = [
  {id:'platform',title:'Platform notifications',description:'News and announcements from MiNa',icon:4},
  {id:'follow',title:'New followers',description:'People who started following you',icon:6},
  {id:'ranking',title:'Ranking updates',description:'Changes to your room rankings',icon:7},
];
function Notices({route,go,back}:ScreenProps) {
  const me=userId(), category=categories.find(v=>v.id===route.id);
  const [opened,setOpened]=useState('');
  const [error,setError]=useState('');
  const result=useInboxData('notices:'+me+':'+(category?.id || ''),async()=>{
    const rows=await rest<Notice[]>('account_notices?select=*&owner_id=eq.'+me+(category?'&kind=eq.'+category.id:'')+'&order=created_at.desc,id.desc&limit=200');
    return {rows,byId:await people(rows.map(v=>v.actor_id || ''))};
  });
  async function markRead(id?:string){
    await rest('account_notices?owner_id=eq.'+me+'&read_at=is.null'+(id?'&id=eq.'+id:category?'&kind=eq.'+category.id:''),{method:'PATCH',body:JSON.stringify({read_at:new Date().toISOString()})});
    refreshInbox();
  }
  const rows=result.data?.rows || [];
  return <><Header title={category?.title || 'System notifications'} back={back} action={<button aria-label="Mark notices as read" onClick={()=>void markRead().catch(e=>setError(errorText(e)))}><Img group="notice" index={3}/></button>}/>
    {(!result.data || result.error) && <Status error={result.error}/>}
    {!category ? categories.map(cat=><button className="im-summary" key={cat.id} onClick={()=>go('messages.notices.category',cat.id)}><Img group="notice" index={cat.icon}/><span><strong>{cat.title}</strong><small>{cat.description}</small></span>
      {rows.some(n=>n.kind===cat.id && !n.read_at) && <b className="im-badge">{rows.filter(n=>n.kind===cat.id && !n.read_at).length}</b>}</button>) :
      rows.map(n=><div className="im-notice" key={n.id}><button onClick={async()=>{
        try{await markRead(n.id);setOpened(opened===n.id?'':n.id);if(n.kind==='follow' && n.actor_id)go('person',n.actor_id);if(n.kind==='ranking')go('rooms.ranks');}
        catch(e){setError(errorText(e));}
      }}><span><strong>{n.kind==='follow' ? result.data?.byId[n.actor_id || '']?.name || n.title : n.title}</strong>{!n.read_at && <b>New</b>}</span>
        <time>{dateLabel(n.created_at)}</time><small>{n.body}</small></button>{opened===n.id && n.kind==='platform' && <article><h2>{n.title}</h2><p>{n.body}</p></article>}</div>)}
    {category && result.data && !rows.length && <Empty title="No notifications yet"/>}
    {error && <button className="im-error" onClick={()=>setError('')}>{error} · Dismiss</button>}</>;
}
async function gatherIce(pc:RTCPeerConnection,description:RTCSessionDescriptionInit) {
  await pc.setLocalDescription(description);
  if(pc.iceGatheringState!=='complete')await new Promise<void>(resolve=>{
    const finish=()=>{clearTimeout(timer);pc.removeEventListener('icegatheringstatechange',onState);resolve();};
    const onState=()=>{if(pc.iceGatheringState==='complete')finish();};
    const timer=window.setTimeout(finish,5500);
    pc.addEventListener('icegatheringstatechange',onState);
  });
  if(!pc.localDescription?.sdp)throw new Error('Voice negotiation was interrupted.');
  return pc.localDescription.sdp;
}
const activeCall=(state?:string)=>state==='ringing' || state==='accepted';
const stateTitles:Record<string,string>={busy:'Line busy',missed:'Missed call',ended:'Call ended',disconnected:'Call disconnected',declined:'Call declined'};
function VoiceCall({route,back}:ScreenProps) {
  const me=userId(),id=route.id || '';
  const [call,setCall]=useState<Call|null>(null),[person,setPerson]=useState<Person>();
  const [error,setError]=useState(''),[connectedAt,setConnectedAt]=useState(0),[seconds,setSeconds]=useState(0);
  const [muted,setMuted]=useState(false),[speaker,setSpeaker]=useState(false),[joining,setJoining]=useState(false);
  const [blockedAudio,setBlockedAudio]=useState(false);
  const audioElement=useRef<HTMLAudioElement>(null);
  const stream=useRef<MediaStream|null>(null),pcRef=useRef<RTCPeerConnection|null>(null);
  const status=useRef(''),alive=useRef(true),micRequest=useRef<Promise<MediaStream>|null>(null);
  const wake=useRef<()=>void>(()=>{});
  const closing=useRef(false);
  function stopAudio() {
    if(pcRef.current){pcRef.current.onconnectionstatechange=null;pcRef.current.ontrack=null;pcRef.current.close();pcRef.current=null;}
    stream.current?.getTracks().forEach(t=>t.stop());stream.current=null;
    if(audioElement.current){audioElement.current.pause();audioElement.current.srcObject=null;}
    void native('setCallSpeaker',{enabled:false,ending:true}).catch(()=>{});
  }
  async function microphone() {
    if(stream.current)return stream.current;
    if(!navigator.mediaDevices?.getUserMedia || !window.RTCPeerConnection)throw new Error('Voice calling is unavailable on this device.');
    micRequest.current ||= navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:false}).finally(()=>{micRequest.current=null;});
    const s=await micRequest.current;
    if(!alive.current || closing.current || document.hidden || !activeCall(status.current)){
      s.getTracks().forEach(t=>t.stop());throw new Error('The call is no longer active.');
    }
    if(!s.getAudioTracks().length){s.getTracks().forEach(t=>t.stop());throw new Error('Microphone unavailable.');}
    stream.current=s;
    return s;
  }
  useEffect(()=>{
    alive.current=true;closing.current=false;
    let busy=false,timer=0,peerName='',lastBeat=0,deadline=0,networkFailureAt=0;
    let sentOffer=false,sentAnswer=false,readAnswer=false;
    let endTimer=0;
    function endLocally(reason:string){
      if(closing.current)return;
      closing.current=true;stopAudio();setConnectedAt(0);setError(reason);
      void action(id,'disconnect').then(wake.current).catch(()=>{});
    }
    function ensurePeer(local:MediaStream) {
      if(pcRef.current)return pcRef.current;
      const config=window as Window & {MiNaIceServers?:RTCIceServer[]};
      const pc=new RTCPeerConnection({iceServers:config.MiNaIceServers || []});
      pcRef.current=pc;
      local.getAudioTracks().forEach(t=>{
        pc.addTrack(t,local);
        t.onended=()=>{if(alive.current && !closing.current)endLocally('Your microphone was disconnected.');};
      });
      pc.ontrack=e=>{
        if(!audioElement.current || closing.current)return;
        audioElement.current.srcObject=new MediaStream([e.track]);
        void audioElement.current.play().then(()=>setBlockedAudio(false)).catch(()=>setBlockedAudio(true));
      };
      pc.onconnectionstatechange=()=>{
        if(pc.connectionState==='connected'){clearTimeout(endTimer);setConnectedAt(t=>t || Date.now());}
        else if(pc.connectionState==='failed'){endLocally('A voice connection could not be established.');}
        else if(pc.connectionState==='disconnected'){setConnectedAt(0);clearTimeout(endTimer);endTimer=window.setTimeout(()=>endLocally('The voice connection was lost.'),9000);}
      };
      return pc;
    }
    async function poll(){
      if(!alive.current || busy || document.hidden)return;
      busy=true;
      try{
        if(!isUuid(id))throw new Error('Call unavailable.');
        const [c]=await rest<Call[]>('voice_calls?id=eq.'+id+'&limit=1');
        if(!alive.current)return;
        if(!c){closing.current=true;stopAudio();setCall(null);setError('This call is unavailable.');return;}
        status.current=c.state;setCall(c);
        if(!activeCall(c.state)){if(!closing.current){stopAudio();closing.current=true;}return;}
        if(closing.current)return;
        const peer=c.caller_id===me ? c.callee_id : c.caller_id;
        if(peerName!==peer){
          const p=(await people([peer]))[peer];if(!alive.current || closing.current)return;
          setPerson(p);peerName=peer;
        }
        if(Date.now()-lastBeat>6500){
          const current=await action(id,'heartbeat');lastBeat=Date.now();
          if(!alive.current || closing.current)return;
          if(current!==c.state){status.current=current;setCall({...c,state:current});if(!activeCall(current)){stopAudio();closing.current=true;}return;}
        }
        networkFailureAt=0;
        if(c.state!=='accepted')return;
        if(!deadline)deadline=Date.now()+36000;
        if(Date.now()>deadline && pcRef.current?.connectionState!=='connected'){endLocally('Neither device could establish an audio connection.');return;}
        try{
          const local=await microphone();
          if(!alive.current || closing.current)return;
          const pc=ensurePeer(local);
          if(c.caller_id===me && !sentOffer){
            if(c.offer && !pc.localDescription){endLocally('The prior call session has ended.');return;}
            const offer=pc.localDescription?.sdp || await gatherIce(pc,await pc.createOffer());
            if(!alive.current || closing.current)return;
            await action(id,'offer',offer);sentOffer=true;
          }else if(c.caller_id!==me && c.offer && !sentAnswer){
            if(c.answer && !pc.localDescription){endLocally('The prior call session has ended.');return;}
            if(!pc.remoteDescription)await pc.setRemoteDescription({type:'offer',sdp:c.offer});
            const answer=pc.localDescription?.sdp || await gatherIce(pc,await pc.createAnswer());
            if(!alive.current || closing.current)return;
            await action(id,'answer',answer);sentAnswer=true;
          }else if(c.caller_id===me && c.answer && !readAnswer){
            await pc.setRemoteDescription({type:'answer',sdp:c.answer});readAnswer=true;
          }
        }catch(e){if(alive.current && !closing.current)endLocally(errorText(e));}
      }catch(e){
        if(alive.current){
          if(!networkFailureAt)networkFailureAt=Date.now();
          setError(errorText(e));
          if(activeCall(status.current) && Date.now()-networkFailureAt>8000)endLocally('The call service disconnected.');
        }
      }finally{
        busy=false;
        if(alive.current && !document.hidden){clearTimeout(timer);timer=window.setTimeout(poll,activeCall(status.current)?1800:7500);}
      }
    }
    wake.current=()=>{clearTimeout(timer);void poll();};
    const visibility=()=>{if(document.hidden && activeCall(status.current)){endLocally('The call stopped when MiNa left the foreground.');}
      else if(!document.hidden)wake.current();};
    document.addEventListener('visibilitychange',visibility);void poll();
    return ()=>{
      alive.current=false;clearTimeout(timer);clearTimeout(endTimer);document.removeEventListener('visibilitychange',visibility);
      if(!closing.current && activeCall(status.current))void action(id,'end').catch(()=>{});
      closing.current=true;stopAudio();wake.current=()=>{};
    };
  },[id,me]);
  useEffect(()=>{
    if(!connectedAt){setSeconds(0);return;}
    const tick=()=>setSeconds(Math.floor((Date.now()-connectedAt)/1000));tick();const timer=setInterval(tick,1000);return ()=>clearInterval(timer);
  },[connectedAt]);
  async function end(){
    if(!call || !activeCall(call.state)){back();return;}
    closing.current=true;stopAudio();setConnectedAt(0);
    try{const current=await action(id,call.state==='ringing' && call.callee_id===me?'decline':'end');status.current=current;setCall({...call,state:current});}
    catch(e){setError(errorText(e));}finally{wake.current();}
  }
  async function accept(){
    if(joining || !call)return;
    setJoining(true);setError('');
    try{
      await microphone();
      const current=await action(id,'accept');
      if(!alive.current)return;
      setCall({...call,state:current});status.current=current;wake.current();
    }catch(e){stopAudio();setError(errorText(e));}finally{setJoining(false);}
  }
  const live=call?.state==='accepted' && !!connectedAt && !closing.current;
  const incoming=call?.state==='ringing' && call.callee_id===me;
  const label=live ? Math.floor(seconds/60)+':'+String(seconds%60).padStart(2,'0') :
    call ? stateTitles[call.state] || (call.state==='accepted' ? closing.current?'Disconnected':'Connecting audio…' : incoming?'Incoming voice call':'Calling…') : 'Opening call…';
  return <><Header title="Voice call" back={()=>{if(call && activeCall(call.state))void end();else back();}}/><div className="im-call">
    <div className="im-call-photo" style={{backgroundImage:'url('+art('call',4)+')'}}><Avatar person={person} size={135}/></div>
    <h2>{person?.name || 'Voice call'}</h2><strong role="status" className="im-call-status">{label}</strong>
    <audio ref={audioElement} autoPlay/>
    {error && <p role="alert">{error}</p>}{blockedAudio && <button onClick={()=>audioElement.current?.play().then(()=>setBlockedAudio(false)).catch(e=>setError(errorText(e)))}>Enable call audio</button>}
    <div className="im-call-actions">
      {incoming && <button className="im-answer" disabled={joining} onClick={accept}>{joining?'Joining…':'Answer'}</button>}
      {call?.state==='accepted' && !closing.current && <button aria-label={speaker?'Switch to earpiece':'Use speaker'} aria-pressed={speaker} onClick={async()=>{
        try{setSpeaker((await native<{speaker:boolean}>('setCallSpeaker',{enabled:!speaker})).speaker);}catch(e){setError(errorText(e));}
      }}><Img group="call" index={speaker?6:7}/></button>}
      {call && activeCall(call.state) ? <button aria-label={incoming?'Decline call':'End call'} onClick={end}><Img group="call" index={5}/></button> :
        <button className="im-answer" onClick={back}>Close</button>}
      {call?.state==='accepted' && !closing.current && <button aria-pressed={muted} aria-label={muted?'Unmute microphone':'Mute microphone'} onClick={()=>{
        const track=stream.current?.getAudioTracks()[0];if(track){track.enabled=!track.enabled;setMuted(!track.enabled);}
      }}><Img group="call" index={muted?9:8}/></button>}</div></div></>;
}
export default function Messages(props:ScreenProps) {
  const name=props.route.name;
  const key=name+':'+(props.route.id || '');
  return <section className={'im-page '+(name==='messages'?'im-home':'')} style={{backgroundImage:'url('+art(name==='messages'?'inbox':'chat',1)+')'}}>
    {name==='messages.thread' ? <Thread key={key} {...props}/> : name==='messages.call' ? <VoiceCall key={key} {...props}/> :
      name==='messages.calls' ? <RecentCalls {...props}/> : name.startsWith('messages.notice') ? <Notices key={key} {...props}/> : <Inbox {...props}/>}</section>;
}
