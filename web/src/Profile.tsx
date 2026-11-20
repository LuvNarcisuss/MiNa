import React,{useEffect,useState} from 'react';
import {art,Empty,errorText,Header,native,read,ScreenProps,write} from './shared';
import {mediaUrl,rest,uploadMedia,userId} from './cloud';

type Person={id:string;name:string;bio:string;country:string;gender:string;language:string;avatar_path:string;private_profile:boolean;show_status:boolean;allow_messages:boolean;allow_calls:boolean};
type Relation={follower_id:string;followed_id:string};
const idLabel=(id:string)=>'Listener '+id.slice(0,6);
const selectPeople='id,name,bio,country,gender,language,avatar_path,private_profile,show_status,allow_messages,allow_calls';
export function Portrait({path,size=76}:{path?:string;size?:number}) {
  const [src,setSrc]=useState('');
  useEffect(()=>{let active=true;setSrc('');if(path)mediaUrl(path).then(url=>{if(active)setSrc(url)}).catch(()=>{});return()=>{active=false};},[path]);
  return <img className="portrait" src={src||art('edit',4)} width={size} height={size} alt=""/>;
}
async function avatarUpload(){
  const picked=await native<{id?:string;cancelled?:boolean}>('pickMedia',{kind:'image'});
  if(!picked.id)return null;
  const data=await native<{base64:string;mimeType:string}>('mediaBytes',{id:picked.id});
  const bytes=Uint8Array.from(atob(data.base64),c=>c.charCodeAt(0));
  return uploadMedia(new Blob([bytes],{type:data.mimeType}),data.mimeType==='image/png'?'png':'jpg');
}
const settings=[['Blocked users','profile.blocked',10],['Privacy settings','profile.privacy',11],['Terms of use','legal.terms',12],['My level','level',13],['Store & backpack','store',14],['Contact us','support',16],['Community guidelines','legal.guidelines',17],['Delete account','delete',15]] as const;
export default function Profile({route,go,back}:ScreenProps){
  const me=userId(), other=route.name==='person' && route.id?route.id:me;
  const [person,setPerson]=useState<Person|null>(null),[relations,setRelations]=useState<Relation[]>([]);
  const [list,setList]=useState<{id:string;name:string;avatar_path?:string}[]>([]);
  const [birthday,setBirthday]=useState(''),[query,setQuery]=useState(''),[search,setSearch]=useState('');
  const [balance,setBalance]=useState(0),[loading,setLoading]=useState(true),[notice,setNotice]=useState(''),[revision,setRevision]=useState(0),[busy,setBusy]=useState(false),[menu,setMenu]=useState(false);
  const refresh=()=>setRevision(n=>n+1);
  useEffect(()=>{let active=true;setLoading(true);setNotice('');
    async function load(){
      const [rows,edges]=await Promise.all([rest<Person[]>('profiles?select='+selectPeople+'&id=eq.'+other),rest<Relation[]>('follows?select=follower_id,followed_id&or=(follower_id.eq.'+other+',followed_id.eq.'+other+')')]);
      if(!active)return;setPerson(rows[0]||null);setRelations(edges);
      if(other===me&&rows[0])write('profile',{name:rows[0].name,avatarId:rows[0].avatar_path});
      if(route.name==='profile'){const wallets=await rest<{balance:number}[]>('wallets?select=balance&owner_id=eq.'+me);if(active)setBalance(wallets[0]?.balance||0);}
      if(route.name==='profile.edit'){const dates=await rest<{birthday:string}[]>('personal_settings?select=birthday&id=eq.'+me);if(active)setBirthday(dates[0]?.birthday||'');}
      const following=edges.filter(f=>f.follower_id===me).map(f=>f.followed_id);
      const followers=edges.filter(f=>f.followed_id===me).map(f=>f.follower_id);
      if(route.name==='profile.blocked'){const b=await rest<{blocked_id:string}[]>('blocks?select=blocked_id&owner_id=eq.'+me);if(active)setList(b.map(x=>({id:x.blocked_id,name:read<Record<string,string>>('people',{})[x.blocked_id]||idLabel(x.blocked_id)})));}
      if(['profile.following','profile.followers','profile.friends','profile.search'].includes(route.name)){
        const ids=route.name.endsWith('friends')?following.filter(x=>followers.includes(x)):route.name.endsWith('followers')?followers:following;
        const filter=route.name.endsWith('search')?(search?'name=ilike.'+encodeURIComponent('*'+search.replace(/[%_*]/g,'')+'*')+'&id=neq.'+me:''):ids.length?'id=in.('+ids.join(',')+')':'';
        const found=filter?await rest<Person[]>('profiles?select=id,name,avatar_path&'+filter+'&order=name&limit=100'):[];if(active)setList(found);
      }
    }
    load().catch(e=>{if(active)setNotice(errorText(e))}).finally(()=>{if(active)setLoading(false)});return()=>{active=false};
  },[route.name,other,me,revision,search]);
  async function run(action:()=>Promise<unknown>){if(busy)return;setBusy(true);setNotice('');try{await action()}catch(e){setNotice(errorText(e))}finally{setBusy(false)}}
  const following=relations.filter(f=>f.follower_id===other),fans=relations.filter(f=>f.followed_id===other),friends=following.filter(f=>fans.some(a=>a.follower_id===f.followed_id));
  const followed=fans.some(f=>f.follower_id===me);
  const alert=notice&&<p className="error" role="alert">{notice} <button onClick={refresh}>Reload</button></p>;
  const patch=(body:Partial<Person>)=>rest('profiles?id=eq.'+me,{method:'PATCH',body:JSON.stringify(body)});
  if(['profile.following','profile.followers','profile.friends','profile.blocked','profile.search'].includes(route.name)){
    const blocked=route.name==='profile.blocked',find=route.name==='profile.search',label=route.name.split('.')[1];
    return <section className="light-page"><Header title={find?'Find people':blocked?'Blocked users':label[0].toUpperCase()+label.slice(1)} back={back}/>
      {find&&<form className="people-search" onSubmit={e=>{e.preventDefault();setSearch(query.trim())}}><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search by nickname" aria-label="Nickname"/><button>Search</button></form>}{alert}
      {list.map(p=><button className="people-row" key={p.id} disabled={busy} onClick={()=>blocked?void run(async()=>{await rest('blocks?owner_id=eq.'+me+'&blocked_id=eq.'+p.id,{method:'DELETE'});refresh()}):go('person',p.id)}><Portrait path={p.avatar_path} size={46}/><b>{p.name}</b><span>{blocked?'Unblock':'View'}</span></button>)}
      {!list.length&&!notice&&<Empty title={loading?'Loading…':find&&!search?'Find a listener':'No '+(find?'matching listeners':label)+' yet'} detail={find?'Look for someone by their MiNa nickname.':undefined}/>}</section>;
  }
  if(!person)return <section className="light-page"><Header title="Profile" back={back}/>{alert||<Empty title={loading?'Loading profile…':'Profile unavailable'} detail={loading?undefined:'This listener’s profile is private or no longer available.'}/>}</section>;
  if(route.name==='profile.privacy'){
    const toggles=[['private_profile','Private profile'],['show_status','Show activity status'],['allow_messages','Allow messages'],['allow_calls','Allow voice calls']] as const;
    return <section className="light-page"><Header title="Privacy settings" back={back}/><div className="white-card">{toggles.map(([key,label])=><label className="setting-row" key={key}>{label}<input type="checkbox" role="switch" checked={person[key]} disabled={busy} onChange={()=>run(async()=>{await patch({[key]:!person[key]});setPerson({...person,[key]:!person[key]})})}/></label>)}</div><div className="white-card">{['terms','privacy'].map(key=><button className="setting-row" key={key} onClick={()=>go('legal.'+key)}>{key==='terms'?'User agreement':'Privacy policy'} <span>›</span></button>)}</div>{alert}</section>;
  }
  if(route.name==='profile.edit'){
    const update=(key:keyof Person,value:string)=>setPerson({...person,[key]:value});
    return <section className="light-page"><Header title="Edit profile" back={back}/><form className="edit-form" onSubmit={e=>{e.preventDefault();void run(async()=>{
      const {name,bio,country,gender,language,avatar_path}=person;
      if(!name.trim()||bio.trim().split(/\s+/).length>50)throw new Error('Enter a nickname and a signature of up to 50 words.');
      await patch({name:name.trim(),bio,country,gender,language,avatar_path});await rest('personal_settings?id=eq.'+me,{method:'PATCH',body:JSON.stringify({birthday:birthday||null})});write('profile',{name:name.trim(),avatarId:avatar_path});back();
    })}}><label>Nickname<input required maxLength={50} value={person.name} onChange={e=>update('name',e.target.value)}/></label><label>Profile picture</label><button type="button" className="avatar-picker" disabled={busy} onClick={()=>run(async()=>{const path=await avatarUpload();if(path)update('avatar_path',path)})}><Portrait path={person.avatar_path} size={112}/><span>Choose photo</span></button>
    <label>Country or region<input maxLength={60} value={person.country} onChange={e=>update('country',e.target.value)}/></label><label>Gender<select value={person.gender} onChange={e=>update('gender',e.target.value)}><option value="">Prefer not to say</option>{['Female','Male','Nonbinary'].map(o=><option key={o}>{o}</option>)}</select></label><label>Date of birth<input type="date" max={new Date().toISOString().slice(0,10)} value={birthday} onChange={e=>setBirthday(e.target.value)}/></label><label>Language<input maxLength={60} value={person.language} onChange={e=>update('language',e.target.value)}/></label><label>Signature<textarea maxLength={500} value={person.bio} placeholder="Share a little about yourself" onChange={e=>update('bio',e.target.value)}/></label>{alert}<button className="primary" disabled={busy}>Save</button></form></section>;
  }
  const own=other===me;
  return <section className="profile-page"><header className="profile-heading">{own?<><h1>Profile</h1><button onClick={()=>go('profile.search')}>Find people <img src={art('profile',3)} alt=""/></button></>:<><button onClick={back}>‹ Back</button><button onClick={()=>setMenu(!menu)}>More</button></>}</header>
    <div className="identity"><button aria-label={own?'Edit profile':'View profile picture'} onClick={()=>own&&go('profile.edit')}><Portrait path={person.avatar_path} size={108}/>{own&&<img className="edit-icon" src={art('profile',4)} alt=""/>}</button><h2>{person.name}</h2>{person.bio&&<p>{person.bio}</p>}</div>
    <div className="social-counts">{[[fans.length,'Followers','followers'],[following.length,'Following','following'],[friends.length,'Friends','friends']].map(([n,label,slug])=><button key={slug} disabled={!own} onClick={()=>go('profile.'+slug)}><strong>{n}</strong>{label}</button>)}</div>{alert}
    {!own&&<><div className="button-pair"><button className="primary" disabled={!person.allow_messages} onClick={()=>go('messages.thread',other)}>Chat</button><button className="primary" disabled={busy} onClick={()=>run(async()=>{await rest(followed?'follows?follower_id=eq.'+me+'&followed_id=eq.'+other:'follows',{method:followed?'DELETE':'POST',...(!followed?{body:JSON.stringify({followed_id:other})}:{})});refresh()})}>{followed?'Following':'Follow'}</button></div>
    {menu&&<div className="white-card"><button className="setting-row" disabled={busy} onClick={()=>run(async()=>{await rest('reports',{method:'POST',body:JSON.stringify({target_id:other,target_kind:'profile',reason:'Please review this profile.'})});setMenu(false);setNotice('Report received.')})}>Report profile</button><button className="setting-row" onClick={()=>run(async()=>{await rest('blocks',{method:'POST',body:JSON.stringify({blocked_id:other})});write('people',{...read('people',{}),[other]:person.name});back()})}>Block listener</button></div>}</>}
    <div className="works">{[ ['Posts',own?'feed.mine':'feed.author',5],['Dreams',own?'dreams.mine':'dreams.author',6] ].map(([title,to,index])=><button className="work-link" key={to} onClick={()=>go(String(to),own?undefined:other)}><img src={art('profile',Number(index))} alt=""/><span>{own?'My ':''}{title}</span></button>)}</div>
    {own&&<><button className="wallet-strip" onClick={()=>go('wallet')}><img src={art('wallet',3)} alt=""/><span>My wallet<strong>{balance} coins</strong></span><b>Open wallet</b></button><h3>More settings</h3>{settings.map(([name,to,icon])=><button className={'setting-row menu-row '+(to==='delete'?'danger':'')} key={to} onClick={()=>go(to)}><span className="menu-icon" style={{backgroundImage:'url('+art('profile',icon)+')'}}/>{name}<span>›</span></button>)}<button className="outline logout" onClick={()=>go('logout')}>Sign out</button></>}</section>;
}
