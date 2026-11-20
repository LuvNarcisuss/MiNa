import React, {useCallback, useEffect, useRef, useState} from 'react';
import {ScreenProps, art, read, write, Header, Empty, native} from './shared';
import {rest, userId, uploadMedia, mediaUrl} from './cloud';
import './community.css';

type Take = {id: string; duration: number};
type Media = {id: string; url: string; cover?: string; duration?: number};
type Draft = {id: string; text: string; media?: Take};
type DreamDraft = Draft & {
  candidate?: Take;
  pending?: {token: string; baseline: string | null};
};
type Journal = {postDraft?: Draft; dreamDraft?: DreamDraft};
type Change = (mutate: (state: Journal) => Journal) => boolean;
type Section = ScreenProps & {state: Journal; change: Change; issue: (message: string) => void};
type Row = {id: string; owner_id: string; kind: 'post'|'dream'; caption: string; media_path: string; duration: number; created_at: string};
type Profile = {id:string; name:string; avatar_path?:string};
type Note = {id:string; owner_id:string; body:string; created_at:string};
type Item = Row & {like_count:number;comment_count:number;liked:boolean;saved:boolean};
const changed = 'mina:community-change';
const refreshed = 'mina:community-refresh';
const journalKey = (account: string) => 'community.drafts.' + account;
const authorName = 'MiNa Journal';
const stories = [
  {
    id: 'journal-moon-window', title: 'A window left open',
    text: 'For a moment, the whole street was quiet enough to hear the curtains move.',
    body: 'Across the courtyard, one window stayed lit. A spoon touched the side of a cup, then the light went out. The curtains lifted again. For once, there was nothing else I needed to do.',
    cover: './art/rooms-extra/moon-seat.webp',
  },
  {
    id: 'journal-falling-star', title: 'One last star',
    text: 'I watched a small light cross the sky and forgot to make a wish.',
    body: 'Maybe it was a plane. Maybe someone in a window seat was watching the lights below, trying to guess which one was home. I pulled the blanket to my chin and let the thought drift on.',
    cover: './art/rooms-extra/star-pillow.webp',
  },
];
type Story = (typeof stories)[number];
function uid() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
  return [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
}
function stamp(time: number) {
  return new Intl.DateTimeFormat('en', {month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'}).format(time);
}
function reason(error: unknown, fallback: string) {
  return error instanceof Error && error.message ? error.message : fallback;
}
function clock(seconds: number) {
  const rounded = Math.ceil(Math.max(0, seconds));
  return Math.floor(rounded / 60) + ':' + String(rounded % 60).padStart(2, '0');
}
function snapshot(account = userId()) {
  return read<Journal>(journalKey(account), {});
}
function removeUnusedFile(id?: string, account = userId()) {
  if (!id) return;
  const s = snapshot(account);
  if (s.postDraft?.media?.id === id || s.dreamDraft?.media?.id === id || s.dreamDraft?.candidate?.id === id || s.dreamDraft?.pending?.baseline === id) return;
  void native('deleteMedia', {id}).catch(() => {});
}
function useMedia(id?: string, remote = false) {
  const [resource, setResource] = useState<{id?: string; media?: Media; error?: string}>({});
  const [attempt, retry] = useState(0);
  useEffect(() => {
    let active = true;
    if (id) {
      const request = remote ? mediaUrl(id).then(url => ({id,url})) : native<Media>('resolveMedia', {id});
      request.then(media => {
        if (active) setResource({id, media});
      }).catch(() => {
        if (active) setResource({id, error: 'This file could not be opened.'});
      });
    }
    return () => { active = false; };
  }, [id, attempt, remote]);
  return {media: resource.id === id ? resource.media : undefined,
    error: resource.id === id ? resource.error : undefined,
    retry: () => {setResource({}); retry(n => n + 1);}};
}
function quietOthers(current: HTMLMediaElement) {
  document.querySelectorAll<HTMLMediaElement>('video, audio').forEach(el => {
    if (el !== current && !el.paused) el.pause();
  });
}
function Icon({group, index}: {group: string; index: number}) {
  return <img className="cm-icon" src={art(group, index)} alt="" />;
}
function Action({children, onClick, ...props}: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type="button" className="cm-primary" onClick={onClick} {...props}>{children}</button>;
}
function Video({id, remote = false}: {id: string; remote?: boolean}) {
  const {media, error, retry} = useMedia(id, remote);
  const [badUrl, setBadUrl] = useState('');
  if (error || (media && badUrl === media.url)) return <div className="cm-file-error">Video unavailable.
    <button onClick={() => {setBadUrl(''); retry();}}>Try again</button></div>;
  if (!media) return <div className="cm-video cm-loading" role="status">Opening video…</div>;
  return <video className="cm-video" controls playsInline preload="metadata" poster={media.cover}
    src={media.url} onPlay={e => quietOthers(e.currentTarget)} onError={() => setBadUrl(media.url)} />;
}
const waveHeights = [9,17,13,25,32,14,21,11,19,29,37,16,22,10,26,34,20,14,25,12,18,30,19,10,24,33,21,15,26,13,31,18,25,10,21,16,29,12];
function Voice({take, remote = false}: {take: Take; remote?: boolean}) {
  const {media, error, retry} = useMedia(take.id, remote);
  const audio = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);
  const [failed, setFailed] = useState(false);
  return <div className="cm-audio-area">
    <audio ref={audio} src={media?.url} preload="metadata"
      onPlay={e => {quietOthers(e.currentTarget); setPlaying(true); setFailed(false);}}
      onPause={() => setPlaying(false)} onTimeUpdate={e => setPosition(e.currentTarget.currentTime)}
      onEnded={() => {setPlaying(false); setPosition(0);}} onError={() => setFailed(true)} />
    <button className="cm-wave" aria-label={playing ? 'Pause recording' : 'Play recording'}
      disabled={!media || failed} onClick={() => {
        if (!audio.current) return;
        if (playing) audio.current.pause();
        else void audio.current.play().catch(() => setFailed(true));
      }}>
      <Icon group="dreams" index={playing ? 18 : 3} />
      <span className="cm-bars" aria-hidden="true">{waveHeights.map((h,i) =>
        <i key={i} style={{height: h + '%', opacity: i / waveHeights.length <= position / take.duration ? 1 : .65}} />)}</span>
      <span>{clock(playing || position > 0 ? position : take.duration)}</span>
    </button>
    {(failed || error) && <button className="cm-retry" onClick={() => {setFailed(false); retry();}}>Recording unavailable · Retry</button>}
  </div>;
}
function opts(method: string, data?: unknown, prefer?: string): RequestInit {
  return {method, headers:prefer ? {Prefer:prefer} : undefined, body:data ? JSON.stringify(data) : undefined};
}
function reload() {
  window.dispatchEvent(new Event(refreshed));
}
function useData<T>(key: string, load: () => Promise<T>) {
  const loader = useRef(load);
  loader.current = load;
  const [version, setVersion] = useState(0);
  const [result, setResult] = useState<{key:string; data?:T; error?:string}>({key:''});
  const refresh = useCallback(() => setVersion(n => n + 1), []);
  useEffect(() => {
    window.addEventListener(refreshed,refresh);
    window.addEventListener('online',refresh);
    const onVisible=()=>{if(!document.hidden)refresh();};
    document.addEventListener('visibilitychange',onVisible);
    const timer=window.setInterval(onVisible,45000);
    return () => {window.clearInterval(timer);document.removeEventListener('visibilitychange',onVisible);
      window.removeEventListener(refreshed,refresh);window.removeEventListener('online',refresh);};
  },[refresh]);
  useEffect(() => {
    let current = true;
    loader.current().then(data => {
      if (current) setResult({key,data});
    }).catch(e => {if (current) setResult(prev => ({key,data:prev.key === key ? prev.data : undefined,error:reason(e,'Could not connect to MiNa.')}));});
    return () => {current = false;};
  }, [key,version]);
  return {data:result.key === key ? result.data : undefined,error:result.key === key ? result.error : undefined,refresh};
}
function Loading({error, retry}: {error?:string; retry:()=>void}) {
  return <div className="cm-load" role="status">{error ? <><span>{error}</span><button onClick={retry}>Try again</button></> : 'Loading…'}</div>;
}
async function names(ids: string[]) {
  const unique = [...new Set(ids)];
  if (!unique.length) return {} as Record<string,Profile>;
  const rows = await rest<Profile[]>('profiles?select=id,name,avatar_path&id=in.(' + unique.join(',') + ')');
  return Object.fromEntries(rows.map(p => [p.id,p])) as Record<string,Profile>;
}
function Owner({id, profile, date, go}: {id:string; profile?:Profile; date:string} & Pick<Section,'go'>) {
  const {media} = useMedia(profile?.avatar_path, true);
  const name = profile?.name || 'Night listener';
  return <button className="cm-author" onClick={() => id === userId() ? go('profile') : go('person',id)}>
    <span className="cm-avatar">{media ? <img src={media.url} alt=""/> : name.slice(0,1).toUpperCase()}</span>
    <span><strong>{name}</strong><small>{stamp(Date.parse(date))}</small></span></button>;
}
function EntryCard({row, profile, followed, detail, mine, go, issue}: {row:Item;profile?:Profile;followed:boolean; detail?:boolean;mine?:boolean} & Pick<Section,'go'|'issue'>) {
  const me = userId();
  const dream = row.kind === 'dream';
  const own = row.owner_id === me;
  const [menu,setMenu] = useState(false);
  const [confirm,setConfirm] = useState(false);
  const [reporting,setReporting] = useState(false);
  const [reportReason,setReportReason] = useState('Harassment');
  const reportId = useRef('');
  const [busy,setBusy] = useState(false);
  const lock = useRef(false);
  const {liked,saved} = row;
  async function act(op: () => Promise<unknown>) {
    if (lock.current) return;
    lock.current = true; setBusy(true);
    try {await op(); reload(); setMenu(false); setConfirm(false);}
    catch (e) {issue(reason(e,'Your change could not be saved. Try again.'));}
    finally {lock.current = false; setBusy(false);}
  }
  function toggle(kind:'like'|'save', active:boolean) {
    return act(() => active ? rest('entry_reactions?entry_id=eq.'+row.id+'&owner_id=eq.'+me+'&kind=eq.'+kind,opts('DELETE')) :
      rest('entry_reactions',opts('POST',{entry_id:row.id,owner_id:me,kind},'resolution=ignore-duplicates')));
  }
  const open = () => go(dream ? 'dreams.detail' : 'feed.post',row.id);
  return <article className={'cm-story' + (detail ? ' cm-full-story' : '')}>
    <div className="cm-byline"><Owner id={row.owner_id} profile={profile} date={row.created_at} go={go}/>
      {!own && <button className="cm-pill" disabled={busy} aria-pressed={followed} onClick={() => act(() => followed ?
        rest('follows?follower_id=eq.'+me+'&followed_id=eq.'+row.owner_id,opts('DELETE')) :
        rest('follows',opts('POST',{follower_id:me,followed_id:row.owner_id},'resolution=ignore-duplicates')))}>{followed ? 'Following' : 'Follow'}</button>}
      {own && mine && <button className="cm-pill" onClick={() => setConfirm(true)}>Delete</button>}</div>
    <button className="cm-caption" disabled={detail} onClick={open}>{row.caption || (dream ? 'A voice from the night' : 'A moment from my night')}</button>
    {dream ? <Voice remote take={{id:row.media_path,duration:row.duration}}/> : <Video remote id={row.media_path}/>}
    <div className="cm-engagement">
      <button aria-label={liked ? 'Remove like' : 'Like'} aria-pressed={liked} disabled={busy} onClick={() => toggle('like',liked)}><Icon group="feed" index={liked ? 9 : 6}/>{row.like_count}</button>
      {dream ? <button aria-pressed={saved} disabled={busy} onClick={() => toggle('save',saved)}><Icon group="dreams" index={saved ? 9 : 8}/>{saved ? 'Saved' : 'Save'}</button> :
        <button aria-label="Open discussion" onClick={() => detail ? document.getElementById('cm-comment')?.focus() : open()}><Icon group="feed" index={7}/>{row.comment_count}</button>}
      <button className="cm-more" aria-expanded={menu} aria-label="More options" onClick={() => setMenu(!menu)}><Icon group="feed" index={8}/></button></div>
    {menu && <div className="cm-options">{own ? <button onClick={() => {setConfirm(true);setMenu(false);}}>Delete {row.kind}</button> :
      <><button onClick={() => {setReporting(true);setMenu(false);}}>Report {row.kind}</button>
        <button onClick={() => go('person',row.owner_id)}>View author profile</button></>}</div>}
    {reporting && <div className="cm-confirm"><strong>Report this {row.kind}</strong>
      <p>Choose a reason for the moderation team.</p>
      <select aria-label="Report reason" value={reportReason} disabled={busy} onChange={e => setReportReason(e.target.value)}>
        {['Harassment','Sexual content','Harmful content','Privacy concern','Spam','Other'].map(r => <option key={r}>{r}</option>)}</select>
      <div><button disabled={busy} onClick={() => setReporting(false)}>Cancel</button><button disabled={busy} onClick={() => act(async () => {
        reportId.current ||= uid();
        const rows = await rest<{id:string}[]>('reports?select=id',opts('POST',{id:reportId.current,reporter_id:me,target_id:row.id,
          target_kind:row.kind,reason:reportReason},'return=representation,resolution=ignore-duplicates'));
        const receipt = rows[0] ?? (await rest<{id:string}[]>('reports?select=id&reporter_id=eq.'+me+'&id=eq.'+reportId.current))[0];
        if (!receipt) throw new Error('Your report could not be confirmed. Please retry.');
        setReporting(false);issue('Report received · '+receipt.id.slice(0,8));reportId.current='';
      })}>Submit report</button></div></div>}
    {confirm && <div className="cm-confirm"><strong>Delete this {row.kind}?</strong><p>It will be removed from MiNa.</p>
      <div><button disabled={busy} onClick={() => setConfirm(false)}>Keep</button><button disabled={busy} onClick={() => act(async () => {
        const deleted = await rest<{id:string}[]>('entries?id=eq.'+row.id+'&owner_id=eq.'+me+'&select=id',opts('DELETE',undefined,'return=representation'));
        if (!deleted.length) throw new Error('This entry has already been removed. Refresh to see the latest posts.');
      })}>Delete</button></div></div>}
  </article>;
}
function Discussion({id, go, issue}: {id:string} & Pick<Section,'go'|'issue'>) {
  const [text,setText] = useState('');
  const [emoji,setEmoji] = useState(false);
  const [busy,setBusy] = useState(false);
  const requestId = useRef('');
  const {data,error,refresh} = useData('comments-'+id,async () => {
    const notes = await rest<Note[]>('entry_comments?select=id,owner_id,body,created_at&entry_id=eq.'+id+'&order=created_at.desc');
    return {notes,profiles:await names(notes.map(n => n.owner_id))};
  });
  return <section className="cm-discussion"><h2>Discussion</h2>
    {(!data || error) && <Loading error={error} retry={refresh}/>}
    {data?.notes.map(n => <div key={n.id} className="cm-note"><Owner id={n.owner_id} profile={data.profiles[n.owner_id]} date={n.created_at} go={go}/><p>{n.body}</p></div>)}
    {data && !data.notes.length && <p>No comments yet.</p>}
    <form onSubmit={async e => {e.preventDefault(); if (busy || !text.trim()) return;setBusy(true);
      requestId.current ||= uid();
      try {await rest('entry_comments',opts('POST',{id:requestId.current,entry_id:id,owner_id:userId(),body:text.trim()},'resolution=ignore-duplicates'));
        requestId.current='';setText('');setEmoji(false);reload();}
      catch (err) {issue(reason(err,'Your comment could not be sent. Try again.'));} finally {setBusy(false);}
    }}>
      <button type="button" aria-label="Choose an emoji" onClick={() => setEmoji(!emoji)}><Icon group="post" index={10}/></button>
      <input id="cm-comment" aria-label="Comment" placeholder="Write a comment…" value={text} maxLength={1000} disabled={busy} onChange={e => {setText(e.target.value);requestId.current='';}}/>
      <button aria-label="Send comment" disabled={busy || !text.trim()}><Icon group="post" index={11}/></button></form>
    {emoji && <div className="cm-emoji">{['🌙','✨','💚','😴','🌟','🫶'].map(item => <button key={item} disabled={busy} onClick={() => {setText((text+item).slice(0,1000));requestId.current='';}}>{item}</button>)}</div>}
  </section>;
}
function Activity({go, back, route}: Section) {
  const [likes,setLikes] = useState(route.name === 'feed.likes');
  const {data,error,refresh} = useData('activity-'+likes,async () => {
    type ActivityRow = {entry_id:string;owner_id:string;created_at:string;body?:string;entries:{caption:string;kind:string}};
    const table = likes ? 'entry_reactions' : 'entry_comments';
    const fields = 'entry_id,owner_id,created_at,' + (likes ? '' : 'body,') + 'entries!inner(owner_id,caption,kind)';
    const list = await rest<ActivityRow[]>(table+'?select='+fields+'&entries.owner_id=eq.'+userId()+'&owner_id=neq.'+userId()+
      (likes ? '&kind=eq.like' : '')+'&order=created_at.desc');
    return {list,profiles:await names(list.map(r => r.owner_id))};
  });
  return <><Header title="Activity" back={back}/><div className="cm-segments">
    <button aria-pressed={!likes} onClick={() => setLikes(false)}>Comments</button><button aria-pressed={likes} onClick={() => setLikes(true)}>Likes</button></div>
    {(!data || error) && <Loading error={error} retry={refresh}/>}
    {data?.list.map((item,i) => <button className="cm-activity-row" key={item.entry_id+'-'+i} onClick={() => go(item.entries.kind === 'dream' ? 'dreams.detail' : 'feed.post',item.entry_id)}>
      <strong>{data.profiles[item.owner_id]?.name || 'Night listener'}</strong><small>{stamp(Date.parse(item.created_at))}</small>
      <p>{likes ? 'Liked your ' + item.entries.kind : item.body}</p><span>{item.entries.caption || 'View original'} ›</span></button>)}
    {data && !data.list.length && <div className="cm-quiet"><Empty title={likes ? 'No likes yet' : 'No comments yet'} detail="New activity on your entries will appear here."/></div>}</>;
}
function Reading({story,detail,go}: {story:Story;detail?:boolean} & Pick<Section,'go'>) {
  return <article className="cm-story"><div className="cm-author"><span className="cm-avatar"><img src={art('icon',1)} alt=""/></span>
    <span><strong>{authorName}</strong><small>Bedtime reading</small></span></div><p>{story.text}</p>
    <button className="cm-story-cover" disabled={detail} onClick={() => go('feed.read',story.id)}><img src={story.cover} alt=""/><span>{story.title}</span></button>
    {detail && <p className="cm-story-body">{story.body}</p>}</article>;
}
function Listing(ctx:Section) {
  const {route,go,back} = ctx;
  const dream = route.name.startsWith('dreams');
  const mine = route.name.endsWith('.mine');
  const detail = route.name === 'feed.post' || route.name === 'dreams.detail';
  const byAuthor = route.name.endsWith('.author');
  const [following,setFollowing] = useState(false);
  const [query,setQuery] = useState('');
  const [limit,setLimit] = useState(30);
  const [search,setSearch] = useState('');
  useEffect(() => {
    const timer=window.setTimeout(() => {setSearch(query.trim());setLimit(30);},250);
    return () => clearTimeout(timer);
  },[query]);
  const listKey = [route.name,route.id,following,limit,search].join(':');
  const {data,error,refresh} = useData(listKey,async () => {
    const me = userId();
    const follows = await rest<{followed_id:string}[]>('follows?select=followed_id&follower_id=eq.'+me);
    const followedIds = follows.map(f => f.followed_id);
    const byId = 'entry_feed?select=*&kind=eq.'+(dream ? 'dream' : 'post');
    const filter = mine ? '&owner_id=eq.'+me : byAuthor ? '&owner_id=eq.'+encodeURIComponent(route.id || '') : detail ? '&id=eq.'+encodeURIComponent(route.id || '') :
      following && followedIds.length ? '&owner_id=in.('+followedIds.join(',')+')' : '';
    const filterText = search ? '&caption=ilike.'+encodeURIComponent('%'+search.replace(/[\\%_]/g, value => '\\'+value)+'%') : '';
    const rows = following && !followedIds.length ? [] : await rest<Item[]>(byId+filter+filterText+'&order=created_at.desc,id.desc&limit='+(limit+1));
    return {rows:rows.slice(0,limit),more:rows.length > limit,profiles:await names(rows.map(r => r.owner_id)),followedIds};
  });
  const term = search.toLowerCase();
  const rows = data?.rows || [];
  const readings = dream || mine || byAuthor || detail || following ? [] : stories.filter(s => [s.title,s.text,authorName].some(v => v.toLowerCase().includes(term)));
  const render = (row:Item) => <EntryCard key={row.id} {...ctx} row={row} detail={detail} mine={mine} profile={data?.profiles[row.owner_id]} followed={data?.followedIds.includes(row.owner_id) || false}/>;
  if (detail) return <><Header title={dream ? 'Dream' : 'Post'} back={back}/>
    {(!data || error) && <Loading error={error} retry={refresh}/>}
    {rows.map(render)}{rows.length > 0 && !dream && <Discussion id={rows[0].id} {...ctx}/>}
    {data && !rows.length && <Empty title="Content unavailable" detail="This entry was removed or is no longer available to you."/>}</>;
  const create = () => go(dream ? 'dreams.compose' : 'feed.compose');
  return <>{mine || byAuthor ? <Header title={dream ? mine ? 'My Dreams' : 'Dreams' : mine ? 'My Posts' : 'Posts'} back={back}
    action={mine ? <button className="cm-pill" onClick={create}>{dream ? 'Record' : 'Post'}</button> : undefined}/> :
    dream ? <><Header title="Dream Space" back={back} action={<button className="cm-pill" onClick={create}>Post</button>}/>
      <button className="cm-dream-banner" onClick={create} aria-label="Record a dream"><img src={art('dreams',15)} alt=""/></button>
      <div className="cm-section-line"><h1>Dream Square</h1><button className="cm-filter" aria-pressed={following} onClick={() => setFollowing(!following)}>{following ? 'Following ✓' : 'Following'}</button></div></> :
    <div className="cm-feed-head"><div className="cm-feed-tabs"><button aria-pressed={!following} onClick={() => setFollowing(false)}>Recommended</button>
      <button aria-pressed={following} onClick={() => setFollowing(true)}>Following</button><button aria-label="Post activity" onClick={() => go('feed.activity')}><Icon group="feed" index={3}/></button></div>
      <label className="cm-search"><Icon group="feed" index={2}/><input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search post captions" aria-label="Search post captions"/></label>
      <div className="cm-feed-section"><h1>{following ? 'Following' : 'Night feed'}</h1><button className="cm-pill" onClick={create}>＋ Post</button></div></div>}
    {(!data || error) && <Loading error={error} retry={refresh}/>}
    {rows.map(render)}{readings.map(s => <Reading story={s} key={s.id} go={go}/>)}
    {data?.more && <button className="cm-load" onClick={() => setLimit(n => n+30)}>Load more</button>}
    {data && !rows.length && !readings.length && <div className="cm-quiet"><Empty title={term ? 'No matches' : dream ? 'No dreams yet' : 'No posts yet'} detail={following ? 'Entries from people you follow will appear here.' : mine || dream ? 'Keep a little piece of tonight.' : undefined}>
        {(mine || dream) && <button className="cm-pill" onClick={create}>{dream ? 'Record a dream' : 'Create a post'}</button>}</Empty></div>}
    {!dream && !mine && !byAuthor && <button className="cm-companion" aria-label="Open AI Companion" onClick={() => go('ai')}><span aria-hidden="true">☾</span></button>}
  </>;
}
async function fileBlob(id:string, progress:(fraction:number)=>void) {
  type Chunk = {base64:string; mimeType:string; total:number; nextOffset:number};
  const chunks:ArrayBuffer[] = [];
  let offset = 0;
  let chunk:Chunk;
  do {
    chunk = await native<Chunk>('mediaBytes',{id,offset,length:512*1024});
    if (chunk.total > 50*1024*1024) throw new Error('Choose a video of 50 MB or less.');
    if (chunk.nextOffset <= offset || chunk.nextOffset > chunk.total) throw new Error('This file could not be read. Choose it again.');
    const binary = atob(chunk.base64);
    const bytes = new Uint8Array(binary.length);
    for (let i=0;i<binary.length;i++) bytes[i] = binary.charCodeAt(i);
    if (bytes.length !== chunk.nextOffset-offset) throw new Error('This file was incomplete. Please retry.');
    chunks.push(bytes.buffer); offset = chunk.nextOffset;
    progress(offset/chunk.total);
  } while (offset < chunk.total);
  return new Blob(chunks,{type:chunk.mimeType});
}
function Composer(ctx:Section) {
  const {state,change,issue,go,back,route} = ctx;
  const dream = route.name === 'dreams.compose';
  const key = dream ? 'dreamDraft' : 'postDraft';
  const [freshId] = useState(uid);
  const draft:DreamDraft = state[key] ?? {id:freshId,text:''};
  const [busy,setBusy] = useState(false);
  const [status,setStatus] = useState('');
  const gate = useRef(false);
  const mounted = useRef(true);
  useEffect(() => {mounted.current=true;return () => {mounted.current=false;};},[]);
  function update(patch: Partial<DreamDraft>) {
    return change(s => ({...s,[key]:{...(s[key] || draft),...patch}}));
  }
  async function pick() {
    if (gate.current) return;
    gate.current=true;setBusy(true);setStatus('Importing video…');
    try {
      const file = await native<Media|{cancelled:true}>('pickMedia',{kind:'video'});
      if ('cancelled' in file) return;
      if (!file.id || !file.duration || file.duration<=0) throw new Error('Choose a playable video.');
      if (update({id:uid(),media:{id:file.id,duration:file.duration}})) removeUnusedFile(draft.media?.id);
      else removeUnusedFile(file.id);
    } catch(e) {issue(reason(e,'The video could not be imported. Try again.'));}
    finally {gate.current=false;setBusy(false);setStatus('');}
  }
  async function publish() {
    if (gate.current || !draft.media) return;
    const take = draft.media;
    const account = userId();
    const kind = dream ? 'dream' : 'post';
    gate.current=true;setBusy(true);setStatus('Checking draft…');
    try {
      if (!account) throw new Error('Sign in to publish your draft.');
      const existing = await rest<{id:string}[]>('entries?select=id&id=eq.'+draft.id+'&owner_id=eq.'+account);
      if (!existing.length) {
        const blob = await fileBlob(take.id,p => setStatus('Preparing media · '+Math.round(p*100)+'%'));
        if (userId() !== account) throw new Error('Sign in to the same account to continue.');
        setStatus('Uploading '+(dream ? 'recording' : 'video')+'…');
        const ext = dream ? 'm4a' : blob.type.includes('quicktime') ? 'mov' : blob.type.includes('webm') ? 'webm' : 'mp4';
        const path = await uploadMedia(blob,ext,draft.id);
        if (userId() !== account) throw new Error('Your session changed. Reopen your draft.');
        setStatus('Publishing…');
        await rest('entries',opts('POST',{id:draft.id,owner_id:account,kind,caption:draft.text.trim(),
          media_path:path,duration:take.duration},'resolution=ignore-duplicates'));
      }
      if (change(s => s[key]?.id === draft.id ? {...s,[key]:undefined} : s)) {
        removeUnusedFile(take.id,account);removeUnusedFile(draft.candidate?.id,account);
        reload(); if (mounted.current) go(dream ? 'dreams.mine' : 'feed.mine');
      }
    } catch(e) {issue(reason(e,'Publishing failed. Your draft is ready to retry.'));}
    finally {gate.current=false;setBusy(false);setStatus('');}
  }
  return <><Header title={dream ? 'Post a dream' : 'New post'} back={back}/><div className="cm-compose">
    {dream && <label className="cm-field"><textarea aria-label="Dream description" value={draft.text} maxLength={2000} disabled={busy}
      placeholder="What do you remember from your dream?" onChange={e => update({text:e.target.value})}/></label>}
    {dream ? <div className="cm-record-card"><img src={art('dreamCompose',3)} alt=""/>{draft.media && <Voice key={draft.media.id} take={draft.media}/>}
      <button className="cm-outline" disabled={busy} onClick={() => {
        if (!state.dreamDraft && !update({})) return;
        go('dreams.record');
      }}>{draft.candidate || draft.pending ? 'Review your take' : draft.media ? 'Record again' : 'Record a dream'}</button></div> :
      <><div className="cm-upload">{draft.media ? <><Video id={draft.media.id}/>
        <button className="cm-remove" disabled={busy} aria-label="Remove video" onClick={() => {if (update({media:undefined,id:uid()})) removeUnusedFile(draft.media?.id);}}><Icon group="compose" index={4}/></button></> :
        <button className="cm-upload-target" disabled={busy} onClick={pick}><img src={art('compose',3)} alt=""/><span>{busy ? 'Importing…' : 'Choose a video'}</span></button>}</div>
        <label className="cm-field"><span>Tonight’s mood</span><textarea aria-label="Post caption" placeholder="What would you like to remember?" maxLength={2000}
        disabled={busy} value={draft.text} onChange={e => update({text:e.target.value})}/></label></>}
    <div className="cm-publish">{busy && <progress aria-label={status || 'Working'}/>}<p role="status">{status || 'Your published '+(dream ? 'dream' : 'post')+' will be visible on MiNa.'}</p>
      <Action disabled={busy || !draft.media} onClick={publish}>{busy ? 'Working…' : dream ? 'Publish dream' : 'Publish post'}</Action></div>
  </div></>;
}
type Recovery = {id:string|null;duration:number;recording:boolean};
function Recorder({state,change,issue,back}:Section) {
  const [readyId] = useState(uid);
  const [phase,setPhase] = useState<'idle'|'starting'|'recording'|'stopping'>('idle');
  const [seconds,setSeconds] = useState(0);
  const [recoveryError,setRecoveryError] = useState(false);
  const [attempt,setAttempt] = useState(0);
  const live = useRef(false);
  const lock = useRef(false);
  const started = useRef(0);
  const {candidate,pending} = state.dreamDraft || {};
  const account = useRef(userId()).current;
  const fallback = {id:readyId,text:''};
  function adopt(sample:Take, token:string) {
    if (!sample.id || !Number.isFinite(sample.duration) || sample.duration<=0 || sample.duration>60.5) throw new Error('No usable sound was captured. Try again.');
    const prior = snapshot(account).dreamDraft;
    if (prior?.pending?.token !== token || prior.pending.baseline === sample.id) return false;
    const accepted = change(s => s.dreamDraft?.pending?.token === token ?
      {...s,dreamDraft:{...s.dreamDraft,candidate:{id:sample.id,duration:Math.min(60,sample.duration)},pending:undefined}} : s);
    if (accepted) removeUnusedFile(prior.candidate?.id,account);
    return accepted;
  }
  async function finish(token:string) {
    if (lock.current) return;
    lock.current=true;setPhase('stopping');
    try {
      const take = await native<Take>('stopRecording');
      if (!adopt(take,token)) throw new Error('Could not save the take. Try recovery.');
      setRecoveryError(false);setPhase('idle');
    } catch(e) {setPhase('idle');setRecoveryError(true);issue(reason(e,'Recording was interrupted. Try recovering the take.'));}
    finally {lock.current=false;}
  }
  const finishRef = useRef(finish);
  finishRef.current=finish;
  useEffect(() => {
    live.current=true;
    return () => {
      live.current=false;
      const token = snapshot(account).dreamDraft?.pending?.token;
      if (token && started.current && !lock.current) void finishRef.current(token);
    };
  },[account]);
  useEffect(() => {
    if (!pending || lock.current || recoveryError) return;
    let active=true;
    let polling=false;
    const token=pending.token;
    async function poll() {
      if (polling || lock.current || !active) return;
      polling=true;
      try {
        const sample=await native<Recovery>('recoverRecording');
        if (!active || lock.current || snapshot(account).dreamDraft?.pending?.token!==token) return;
        if (sample.id && sample.id !== pending?.baseline && !sample.recording) {
          if (!adopt({id:sample.id,duration:sample.duration},token)) throw new Error('The take could not be saved.');
          setPhase('idle');setRecoveryError(false);return;
        }
        if (sample.recording) {
          setPhase('recording');
          if (!started.current) started.current=Date.now();
          const elapsed=Math.floor((Date.now()-started.current)/1000);setSeconds(Math.min(60,elapsed));
          if (elapsed>=60) await finishRef.current(token);
        } else {
          setPhase('idle');setRecoveryError(true);
        }
      } catch {if (active) {setPhase('idle');setRecoveryError(true);}}
      finally {polling=false;}
    }
    void poll();
    const timer=window.setInterval(poll,600);
    document.addEventListener('visibilitychange',poll);
    return () => {active=false;clearInterval(timer);document.removeEventListener('visibilitychange',poll);};
  },[pending?.token,phase === 'starting',attempt,recoveryError]);
  async function start() {
    if (lock.current || phase!=='idle' || pending) return;
    lock.current=true;setPhase('starting');setRecoveryError(false);
    let token='';
    try {
      document.querySelectorAll<HTMLMediaElement>('audio,video').forEach(el => el.pause());
      const prior=await native<Recovery>('recoverRecording');
      if (prior.recording) throw new Error('A recording is already in progress.');
      if (!live.current) return;
      token=uid();
      if (!change(s => ({...s,dreamDraft:{...(s.dreamDraft || fallback),pending:{token,baseline:prior.id}}}))) return;
      try {
        await native('startRecording');
      } catch(e) {
        change(s => s.dreamDraft?.pending?.token===token ? {...s,dreamDraft:{...s.dreamDraft,pending:undefined}} : s); throw e;
      }
      started.current=Date.now();setSeconds(0);setPhase('recording');
      if (!live.current) {
        lock.current=false;await finishRef.current(token);
      }
    } catch(e) {issue(reason(e,'Could not start recording. Check microphone access in Settings.'));}
    finally {lock.current=false;setPhase(p => p === 'starting' ? 'idle' : p);}
  }
  const recording = phase==='recording';
  async function leave() {
    if (lock.current) return;
    if (recording && pending) await finish(pending.token);
    back();
  }
  return <><Header title="Recording" back={leave}/><div className="cm-recorder">
    <img className="cm-mic-disc" src={art(recording ? 'recording' : 'recorder',2)} alt=""/>
    <strong className="cm-clock" aria-label="Recording duration">{clock(recording ? seconds : candidate?.duration || 0)}</strong>
    <p>Record up to 60 seconds.</p>
    {candidate && phase==='idle' && !pending && <Voice key={candidate.id} take={candidate}/>}
    <div className="cm-record-tools">
      {pending && recoveryError ? <div className="cm-recovery"><p>The recording was interrupted.</p>
        <button onClick={() => {setRecoveryError(false);setAttempt(n=>n+1);}}>Recover take</button>
        <button onClick={async () => {
          try {
            const recovery=await native<Recovery>('recoverRecording');
            if (recovery.recording) {await finish(pending.token);return;}
            if (recovery.id && recovery.id!==pending.baseline) {adopt({id:recovery.id,duration:recovery.duration},pending.token);setRecoveryError(false);return;}
            change(s => s.dreamDraft?.pending?.token===pending.token ? {...s,dreamDraft:{...s.dreamDraft,pending:undefined}} : s);
            setRecoveryError(false);
          } catch(e) {issue(reason(e,'Could not check the recorder. Try again.'));}
        }}>Finish recovery</button></div> :
        <button className="cm-record-trigger" aria-label={recording ? 'Stop recording' : candidate ? 'Record again' : 'Start recording'}
          disabled={phase==='starting' || phase==='stopping' || (!!pending && !recording)}
          onClick={() => recording && pending ? finish(pending.token) : start()}>
          <img src={art(recording ? 'recording' : 'recorder',3)} alt=""/><span>{recording ? 'Stop recording' : phase==='starting' ? 'Opening microphone…' : phase==='stopping' ? 'Saving take…' : candidate ? 'Record again' : 'Tap to record'}</span></button>}
      {candidate && <Action disabled={!!pending || phase!=='idle'} onClick={() => {
        const old=state.dreamDraft?.media?.id;
        if (change(s => s.dreamDraft ? {...s,dreamDraft:{...s.dreamDraft,id:uid(),media:candidate,candidate:undefined}} : s)) {
          removeUnusedFile(old);back();
        }
      }}>Save take</Action>}
    </div>
  </div></>;
}
export default function Community(props:ScreenProps) {
  const account=userId();
  const [state,setState]=useState(() => snapshot(account));
  const [message,issue]=useState('');
  useEffect(() => {
    const sync=() => setState(snapshot(account));
    sync();window.addEventListener(changed,sync);
    return () => window.removeEventListener(changed,sync);
  },[account]);
  const change:Change=useCallback(mutate => {
    if (!account || userId()!==account) return false;
    try {write(journalKey(account),mutate(snapshot(account)));window.dispatchEvent(new Event(changed));return true;}
    catch {issue('The draft could not be saved on this iPhone. Check your storage and try again.');return false;}
  },[account]);
  const name=props.route.name;
  const ctx={...props,state,change,issue};
  let screen:React.ReactNode;
  const key=name+':'+(props.route.id || '');
  if (name==='dreams.record') screen=<Recorder {...ctx}/>;
  else if (name.endsWith('.compose')) screen=<Composer key={key} {...ctx}/>;
  else if (name==='feed.activity' || name==='feed.likes') screen=<Activity key={key} {...ctx}/>;
  else if (name==='feed.read') {
    const story=stories.find(s=>s.id===props.route.id);
    screen=<><Header title="Bedtime reading" back={props.back}/>{story ? <Reading story={story} detail go={props.go}/> : <Empty title="Reading unavailable"/>}</>;
  } else screen=<Listing key={key} {...ctx}/>;
  return <section className={'cm-page '+(name==='feed' ? 'cm-feed-page' : '')} style={{backgroundImage:'url("'+art(name==='feed' ? 'home' : 'dreams',1)+'")'}}>
    {screen}{message && <div className="cm-message" role="alert"><span>{message}</span><button aria-label="Dismiss message" onClick={()=>issue('')}>×</button></div>}</section>;
}
