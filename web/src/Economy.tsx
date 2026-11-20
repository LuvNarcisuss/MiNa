import {newId} from './ids';
import React,{useEffect,useState} from 'react';
import {art,Empty,Header,ScreenProps,native,errorText} from './shared';
import {rest,userId} from './cloud';

export const giftNames=['Sleep Mask','Cloud Kitten','Triple Six','Stardust Jar','Wishing Star','Moon Headphones','Rain Cloud','Dream Pillow','Dreamcatcher','Bunny Slippers','Sleeping Moon','Soft Slumber','Night Orbit','Star Friend','Sleepy Bear','Moonlight Bed','Heartbeat','Heart Headphones','Star Wand','Moon Lantern'];
type Item={gift_index:number;unit_price:number};
export default function Economy({route,go,back}:ScreenProps){
  const [balance,setBalance]=useState(0),[items,setItems]=useState<Item[]>([]),[inventory,setInventory]=useState<Record<number,number>>({}),[level,setLevel]=useState({contribution:0,current_level:0,next_threshold:100 as number|null});
  const [selection,setSelection]=useState<Item|null>(null),[op,setOp]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[version,setVersion]=useState(0);
  const [offers,setOffers]=useState<{status:string;message?:string}>({status:'loading'});
  const mine=userId(),bag=route.name==='store.bag';
  useEffect(()=>{let live=true;
    Promise.all([rest<{balance:number}[]>('wallets?select=balance&owner_id=eq.'+mine),rest<Item[]>('gift_catalog?select=gift_index,unit_price&order=gift_index'),rest<{gift_index:number;quantity:number}[]>('gift_inventory?select=gift_index,quantity&owner_id=eq.'+mine),rest<typeof level[]>('rpc/my_level',{method:'POST',body:'{}'})]).then(([w,c,i,g])=>{if(live){setBalance(w[0]?.balance||0);setItems(c);setInventory(Object.fromEntries(i.map(it=>[it.gift_index,it.quantity])));if(g[0])setLevel(g[0])}}).catch(e=>{if(live)setError(errorText(e))});
    if(route.name==='wallet')native<{status:string;message?:string}>('getCatalog').then(data=>{if(live)setOffers(data)}).catch(e=>{if(live)setOffers({status:'unavailable',message:errorText(e)})});return()=>{live=false};
  },[route.name,version,mine]);
  const err=error&&<p className="error" role="status">{error} <button onClick={()=>{setError('');setVersion(n=>n+1)}}>Refresh</button></p>;
  if(route.name==='wallet')return <section className="light-page"><Header title="My wallet" back={back}/><div className="wallet-hero"><div>My balance<h2>{balance.toLocaleString()}</h2><small>Star coins</small></div><img src={art('wallet',3)} alt="Star coin"/></div>{err}<div className="white-card"><h3>Coin packages</h3><p>{offers.status==='loading'?'Checking the App Store…':offers.message||'Coin packages are currently unavailable.'}</p><button className="outline" onClick={()=>setVersion(v=>v+1)}>Check again</button></div><button className="setting-row" onClick={()=>go('store.bag')}>My backpack <span>›</span></button></section>;
  if(route.name==='level')return <section className="light-page"><Header title="My level" back={back}/><div className="level-hero"><span>Gift contribution</span><h2>{level.contribution.toLocaleString()} coins</h2><p>VIP {level.current_level} · {level.next_threshold?level.next_threshold.toLocaleString()+' coins for the next level':'Highest level reached'}</p></div>{err}<div className="badge-grid">{[12,11,10,9,8,7,6,5,4,13,3,2,1].map((asset,idx)=><img key={idx} src={art('medals',idx<=level.current_level?asset:asset+13)} alt={'VIP '+idx}/>)}</div></section>;
  async function acquire(){
    if(!selection||busy)return;setBusy(true);setError('');
    try{await rest('rpc/acquire_gift',{method:'POST',body:JSON.stringify({gift_index:selection.gift_index,quantity:1,operation:op})});setSelection(null);setVersion(v=>v+1);}
    catch(e){setError(errorText(e))}finally{setBusy(false)}
  }
  const visible=items.filter(it=>!bag||inventory[it.gift_index]>0);
  return <section className="light-page"><Header title="Store" back={back}/><div className="segments">{[['Store','store'],['Backpack','store.bag']].map(([label,to])=><button key={to} aria-pressed={route.name===to} onClick={()=>{setSelection(null);go(to)}}>{label}</button>)}</div>{err}
    <div className="gift-grid">{visible.map(it=><button key={it.gift_index} onClick={()=>{setSelection(it);setOp(newId());setError('')}}><img src={art('store',3+it.gift_index)} alt={giftNames[it.gift_index]}/><small>{bag?'× '+inventory[it.gift_index]:it.unit_price?'◈ '+it.unit_price:'Free'}</small></button>)}</div>
    {!visible.length&&!error&&<Empty title={bag?'Your backpack is empty':'Loading gifts…'} detail={bag?'Choose something in the store to add it to your backpack.':undefined}/>}
    {selection&&<div className="scrim"><div className="sheet" role="dialog" aria-modal="true"><img className="chosen-gift" src={art('store',3+selection.gift_index)} alt=""/><h2>{giftNames[selection.gift_index]}</h2><p>{bag?'Owned: '+inventory[selection.gift_index]:(selection.unit_price?'Add one for '+selection.unit_price+' star coins.':'Claim one free gift for today.')}</p>{error&&<p role="alert">{error}</p>}{!bag&&<button className="primary" disabled={busy} onClick={selection.unit_price>balance?()=>go('wallet'):acquire}>{selection.unit_price>balance?'Open wallet':busy?'Saving…':'Confirm'}</button>}<button className="text-button" disabled={busy} onClick={()=>setSelection(null)}>Close</button></div></div>}</section>;
}
