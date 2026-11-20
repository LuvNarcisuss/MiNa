import React,{useEffect,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {art,clearLibrary,Header,Route,ScreenProps,useLibrary,errorText,native} from './shared';
import {storedSession,signIn,signOut,removeAccount} from './cloud';
import Rooms from './Rooms';
import Community from './Community';
import Companion from './Companion';
import Messages,{IncomingCallNotice} from './Messages';
import Profile from './Profile';
import Economy from './Economy';
import {Legal,Support} from './Policies';
import './style.css';

const tabs=[['rooms','Rooms',1],['feed','Feed',2],['ai','AI Companion',5],['messages','Messages',3],['profile','Profile',4]] as const;
function App(){
  const [stack,setStack]=useState<Route[]>([{name:'rooms'}]),[signed,setSigned]=useState(false),[starting,setStarting]=useState(true),[busy,setBusy]=useState(false),[consent,setConsent]=useState(false),[error,setError]=useState('');
  const route=stack[stack.length-1],page=useRef<HTMLElement>(null);
  const go=(name:string,id?:string)=>{setError('');setStack(s=>s.at(-1)?.name===name&&s.at(-1)?.id===id?s:[...s,{name,id}]);};
  const back=()=>{setError('');setStack(s=>s.length>1?s.slice(0,-1):s)};
  const props:ScreenProps={route,go,back};
  const darkTop=(!signed&&!route.name.startsWith('legal.')) || ['rooms','rooms.search','rooms.sounds','rooms.create','rooms.live','rooms.stage','feed','messages','ai','ai.chat','profile','person'].includes(route.name);
  useEffect(()=>{native('setStatusBarStyle',{light:darkTop}).catch(()=>{});},[darkTop]);
  useEffect(()=>{page.current?.scrollTo(0,0);},[route]);
  useEffect(()=>{let active=true;async function start(){
    if(localStorage.getItem('mina.locked'))return;
    const saved=await storedSession();
    if(saved){const id=await signIn(true);await useLibrary(id);if(active)setSigned(true);}
  }start().catch(e=>{if(active)setError(errorText(e))}).finally(()=>{if(active)setStarting(false)});return()=>{active=false}},[]);
  async function enter(){if(busy||!consent)return;setBusy(true);setError('');try{
    const saved=await storedSession();const id=await signIn(!!saved);await useLibrary(id);
    setStack([{name:'rooms'}]);setSigned(true);
  }catch(e){setError(errorText(e))}finally{setBusy(false)}}
  async function leave(remove:boolean){
    if(busy)return;setBusy(true);setError('');
    try{if(remove){await removeAccount();clearLibrary()}else await signOut();
      setStack([{name:'rooms'}]);setConsent(false);setSigned(false);
    }catch(e){setError(errorText(e))}finally{setBusy(false)}
  }
  if(starting)return <div className="launch-page" role="status" aria-label="Opening MiNa"/>;
  const legal=route.name.startsWith('legal.');
  if(!signed&&!legal)return <main className="welcome"><div className="welcome-copy"><h1>MiNa</h1><p>Sleep better.<br/>Talk deeper.</p></div><div className="welcome-controls"><button className="welcome-enter" onClick={enter} disabled={busy||!consent}>{busy?'Connecting…':'Continue'}</button>
    <div className="consent"><input id="accept" type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/><span><label htmlFor="accept">I agree to the </label><button onClick={()=>go('legal.terms')}>Terms</button> and <button onClick={()=>go('legal.privacy')}>Privacy Policy</button>.</span></div>{error&&<p className="welcome-error" role="alert">{error}</p>}</div></main>;
  const showTabs=signed&&tabs.some(([name])=>name===route.name);
  function content(){
    if(legal)return <Legal {...props}/>;
    if(route.name.startsWith('rooms'))return <Rooms {...props}/>;
    if(route.name.startsWith('feed')||route.name.startsWith('dreams'))return <Community {...props}/>;
    if(route.name.startsWith('ai'))return <Companion {...props}/>;
    if(route.name.startsWith('messages'))return <Messages {...props}/>;
    if(route.name.startsWith('profile')||route.name==='person')return <Profile {...props}/>;
    if(['level','wallet','store','store.bag'].includes(route.name))return <Economy {...props}/>;
    if(route.name==='support')return <Support {...props}/>;
    if(route.name==='logout'||route.name==='delete'){
      const deleting=route.name==='delete';
      return <section className="light-page"><Header title={deleting?'Delete account':'Sign out'} back={back}/><div className="white-card"><h2>{deleting?'Delete your MiNa account?':'Leave MiNa on this iPhone?'}</h2><p>{deleting?'Your cloud account, uploaded media, messages and associated records will be removed. This action cannot be undone.':'Your device keeps your account key in Keychain. Use Continue on this iPhone to reopen it.'}</p>{error&&<p role="alert">{error}</p>}<button className={'primary '+(deleting?'destructive':'')} disabled={busy} onClick={()=>leave(deleting)}>{busy?'Please wait…':deleting?'Permanently delete':'Sign out'}</button><button className="text-button" disabled={busy} onClick={back}>Cancel</button></div></section>;
    }
    return <section className="light-page"><Header title="Page unavailable" back={back}/></section>;
  }
  return <div className={'app-shell '+(showTabs?'has-tabs ':'')+(darkTop?'night-top ':'day-top ')+'surface-'+route.name.split('.')[0]}><main className="screen" ref={page}><React.Fragment key={route.name+'|'+(route.id||'')}>{content()}</React.Fragment></main>
    {showTabs&&<nav className="bottom-nav" aria-label="Main navigation">{tabs.map(([name,label,index])=><button key={name} aria-label={label} aria-current={route.name===name?'page':undefined} onClick={()=>setStack([{name}])}><img src={art('tabs',index===5?5:route.name===name?index:index+5)} className={index===5?'plus':''} alt=""/></button>)}</nav>}
    {signed&&<IncomingCallNotice route={route} go={go}/>}</div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
