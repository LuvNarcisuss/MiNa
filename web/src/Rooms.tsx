import React, { useEffect, useRef, useState } from 'react';
import { ScreenProps, art, read, write, Header, Empty } from './shared';
import { rest, userId } from './cloud';
import { isUuid, jsonRequest, LiveRoomRecord, makeId } from './roomSession';
import LiveRoom from './LiveRoom';
import './rooms.css';

export const asset = (file: string) => './art/rooms-extra/' + file;
export const sounds = [
  { id: 'moon-seat', title: 'A Moon to Lean On', description: 'Slow, warm harmonies', topic: 'Light music' },
  { id: 'star-pillow', title: 'Starlight Lullaby', description: 'Soft bells under the stars', topic: 'Light music' },
  { id: 'moonlit-sea', title: 'The Midnight Tide', description: 'Gentle waves on a quiet shore', topic: 'Nature sounds' },
];
type Sound = typeof sounds[number];
type Draft = {
  id: string; title: string; cover: string; topic: string; visibility: string;
  follow: boolean; gifts: boolean; comments: boolean;
};
const draftKey = 'room.drafts';
const topics = ['Light music', 'Bedtime stories', 'Night chat'];
const visibilities = ['Public', 'Followers only', 'Only me'];
export const cover = (id: string) => asset((sounds.find(sound => sound.id === id) || sounds[0]).id + '.webp');
const getDrafts = () => read<Draft[]>(draftKey, []);
const emptyDraft = (): Draft => ({
  id: '', title: '', cover: sounds[0].id, topic: topics[0], visibility: 'Only me',
  follow: true, gifts: false, comments: true,
});
const errorText = 'Your changes could not be saved on this device. Please try again.';
type Go = ScreenProps['go'];

export function Icon({ group, index }: { group: string; index: number }) {
  return <img className="rm-icon" src={art(group, index)} alt="" />;
}
function SectionTitle({ title, more }: { title: string; more?: () => void }) {
  return <div className="rm-section-title"><h2>{title}</h2>{more && <button onClick={more} aria-label={'See all ' + title.toLowerCase()}>More <span aria-hidden="true">›</span></button>}</div>;
}
function SoundRow({ sound, go }: { sound: Sound; go: Go }) {
  return <button className="rm-row" onClick={() => go('rooms.stage', sound.id)}>
    <img className="rm-thumb" src={cover(sound.id)} alt="" /><span><strong>{sound.title}</strong><small>{sound.description}</small><em>Offline soundscape</em></span><b aria-hidden="true">›</b>
  </button>;
}
function DraftRow({ draft, go }: { draft: Draft; go: Go }) {
  return <button className="rm-row" onClick={() => go('rooms.stage', draft.id)}>
    <img className="rm-thumb" src={cover(draft.cover)} alt="" /><span><strong>{draft.title}</strong><small>{draft.topic}</small><em>Private draft</em></span><b aria-hidden="true">›</b>
  </button>;
}
function LiveDiscovery({ go, followed = false, term = '', list = false }: { go: Go; followed?: boolean; term?: string; list?: boolean }) {
  const [rooms, setRooms] = useState<LiveRoomRecord[]>([]);
  const [state, setState] = useState('loading');
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    let disposed = false;
    let timer = 0;
    const fetchRooms = async () => {
      try {
        const ids = followed ? await rest<{ followed_id: string }[]>('follows?select=followed_id&follower_id=eq.' + userId()) : [];
        const filter = followed ? '&host_id=in.(' + ids.map(x => x.followed_id).join(',') + ')' : '';
        const data = !followed || ids.length ? await rest<LiveRoomRecord[]>('rooms?closed=eq.false&order=created_at.desc&limit=100' + filter) : [];
        if (!disposed) { setRooms(data); setState('ready'); }
      } catch { if (!disposed) { setRooms([]); setState('error'); } }
      if (!disposed) timer = window.setTimeout(fetchRooms, 20000);
    };
    void fetchRooms();
    return () => { disposed = true; window.clearTimeout(timer); };
  }, [followed, retry]);
  const matches = rooms.filter(r => (r.title + ' ' + r.topic).toLowerCase().includes(term.trim().toLowerCase()));
  return <section className="rm-live-discovery"><SectionTitle title={followed ? 'Followed rooms' : 'Live rooms'} more={!list && matches.length > 3 ? () => go('rooms.liveList') : undefined} />
    {(list ? matches : matches.slice(0, 3)).map(r => <button className="rm-row" key={r.id} onClick={() => go('rooms.live', r.id)}><img className="rm-thumb" src={cover(r.cover)} alt="" /><span><strong>{r.title}</strong><small>{r.topic}</small><em>{r.visibility === 'followers' ? 'Followers only' : r.visibility === 'private' ? 'Only me' : 'Public room'}</em></span><b>›</b></button>)}
    {!matches.length && <p className="rm-note">{state === 'error' ? 'Live rooms could not load.' : state === 'loading' ? 'Finding rooms…' : term ? 'No matching live rooms.' : followed ? 'No followed hosts have an open room.' : 'No live rooms are open right now.'} {state === 'error' && <button onClick={() => setRetry(v => v + 1)}>Retry</button>}</p>}
  </section>;
}
function Discovery({ go }: { go: Go }) {
  const [followed, setFollowed] = useState(false);
  const drafts = getDrafts();
  const saved = read<string[]>('room.savedSounds', []);
  return <section className="rm-home" style={{ backgroundImage: 'url(' + art('home', 1) + ')' }}>
    <div className="rm-home-top"><div className="rm-home-tabs" role="group" aria-label="Discover rooms">
      <button className={!followed ? 'chosen' : ''} aria-pressed={!followed} onClick={() => setFollowed(false)}>Voice Rooms</button>
      <button className={followed ? 'chosen' : ''} aria-pressed={followed} onClick={() => setFollowed(true)}>Followed</button>
    </div><button className="rm-rank-button" aria-label="Open rankings" onClick={() => go('rooms.ranks')}><img src={asset('rank-button.webp')} alt="" /></button></div>
    <button className="rm-search-link" onClick={() => go('rooms.search')}><Icon group="home" index={6} />Search rooms and sounds</button>
    {followed ? <div className="rm-followed"><LiveDiscovery go={go} followed />
      <SectionTitle title="Saved sounds" />{sounds.filter(s => saved.includes(s.id)).map(s => <SoundRow key={s.id} sound={s} go={go} />)}
      {!saved.length && <p className="rm-note">Save a soundscape from its listening room.</p>}
    </div> : <>
      <button className="rm-banner" onClick={() => go('dreams')}><img src={asset('dream-banner.webp')} alt="" /><span><strong>Mysterious<br />Dream Space</strong><small>Listen to a dream</small><b>Explore dreams</b></span></button>
      <SectionTitle title="Tonight’s soundscapes" more={() => go('rooms.sounds')} />
      <div className="rm-features">{sounds.slice(0, 2).map(s => <button key={s.id} className="rm-feature" onClick={() => go('rooms.stage', s.id)}>
        <img src={cover(s.id)} alt="" /><span><small>Listen offline</small><strong>{s.title}</strong></span>
      </button>)}</div>
      <LiveDiscovery go={go} /><SectionTitle title="Recommended" more={() => go('rooms.sounds')} />
      {[sounds[2], sounds[1], sounds[0]].map(s => <SoundRow key={s.id} sound={s} go={go} />)}
      <SectionTitle title="Your room drafts" />{drafts.map(d => <DraftRow key={d.id} draft={d} go={go} />)}
      {!drafts.length && <button className="rm-start-draft" onClick={() => go('rooms.create')}>Create your first room draft <b aria-hidden="true">＋</b></button>}
      
    </>}
    <button className="rm-float" aria-label="Create a room" onClick={() => go('rooms.create')}><img src={asset('create-button.webp')} alt="" /></button>
  </section>;
}

function SearchRooms({ route, go, back }: ScreenProps) {
  const [text, setText] = useState('');
  const term = text.trim().toLocaleLowerCase();
  const searching = route.name === 'rooms.search';
  const matches = (value: string) => value.toLocaleLowerCase().includes(term);
  const results = sounds.filter(s => matches([s.title, s.description, s.topic].join(' ')));
  const drafts = searching ? getDrafts().filter(d => matches(d.title + ' ' + d.topic)) : [];
  return <section className="rm-light"><Header title={searching ? 'Search rooms' : 'Soundscapes'} back={back} />
    <div className="rm-inset">{searching && <label className="rm-search-field"><span>Room or soundscape</span><input type="search" value={text} placeholder="Search by name or topic" onChange={e => setText(e.target.value)} /></label>}
    {term && !results.length && !drafts.length ? <div className="rm-empty-search"><img src={art('search', 10)} alt="" /><h2>No local matches for “{text.trim()}”</h2><p>No matching room drafts or offline sounds.</p></div> : <>
      {results.length > 0 && <><SectionTitle title={term ? 'Matching soundscapes' : 'Listen offline'} />{results.map(s => <SoundRow key={s.id} sound={s} go={go} />)}</>}
      {drafts.length > 0 && <><SectionTitle title="Your room drafts" />{drafts.map(d => <DraftRow key={d.id} draft={d} go={go} />)}</>}
    </>}
    {searching && <LiveDiscovery go={go} term={term} list />}</div>
  </section>;
}

function RoomEditor({ go, back, route }: ScreenProps) {
  const existing = getDrafts().find(d => d.id === route.id);
  const [draft, setDraft] = useState<Draft>(() => existing || emptyDraft());
  const [error, setError] = useState('');
  const change = <K extends keyof Draft,>(key: K, value: Draft[K]) => setDraft(old => ({ ...old, [key]: value }));
  const [publishing, setPublishing] = useState(false);
  const [operation] = useState(makeId);
  async function openLive() {
    const title = draft.title.trim();
    if (!title) { setError('Give your room a title.'); return; }
    setPublishing(true); setError('');
    try {
      const existingRoom = await rest<LiveRoomRecord[]>('rooms?id=eq.' + operation);
      if (!existingRoom.length) await rest('rooms', jsonRequest('POST', {id: operation, host_id: userId(), title, topic: draft.topic, cover: draft.cover, visibility: ['public','followers','private'][visibilities.indexOf(draft.visibility)], allow_follow: draft.follow, allow_gifts: draft.gifts, allow_comments: draft.comments}));
      go('rooms.live', operation);
    } catch { setError('Your room could not open. Your settings are still here.'); } finally { setPublishing(false); }
  }
  function save(e: React.FormEvent) {
    e.preventDefault();
    const title = draft.title.trim();
    if (!title) { setError('Give your room a title.'); return; }
    const values = getDrafts();
    if (existing && !values.some(d => d.id === existing.id)) { setError('This draft is no longer available.'); return; }
    const updated = { ...draft, id: draft.id || 'draft-' + makeId(), title };
    try {
      write(draftKey, [updated, ...values.filter(d => d.id !== updated.id)]);
      go('rooms.stage', updated.id);
    } catch { setError(errorText); }
  }
  return <section className="rm-editor"><Header title={existing ? 'Edit room draft' : 'Create a room'} back={back} />
    <div className="rm-editor-hero"><img src={asset('cloud-bank.webp')} alt="" /><h2>Good night,<br /><strong>voice room</strong></h2><img className="rm-editor-sleeper" src={art('store', 17)} alt="" /></div>
    <form onSubmit={save} className="rm-editor-form">
      <fieldset className="rm-cover-picker"><legend>Room cover</legend><div>{sounds.map(s => <button type="button" aria-label={'Use cover for ' + s.title} aria-pressed={s.id === draft.cover} key={s.id} onClick={() => change('cover', s.id)}><img src={cover(s.id)} alt="" />{draft.cover === s.id && <b aria-hidden="true">✓</b>}</button>)}</div></fieldset>
      <label>Room title <small>{draft.title.length}/20</small><input maxLength={20} required value={draft.title} placeholder="A name for your room" onChange={e => change('title', e.target.value)} /></label>
      <label>Topic<select value={draft.topic} onChange={e => change('topic', e.target.value)}>{topics.map(t => <option key={t}>{t}</option>)}</select></label>
      <fieldset><legend>Visibility when live</legend><div className="rm-choices">{visibilities.map(item => <button key={item} type="button" aria-pressed={draft.visibility === item} onClick={() => change('visibility', item)}>{item}</button>)}</div></fieldset>
      <fieldset className="rm-settings"><legend>Room settings</legend>{([['follow', 'Allow follows'], ['gifts', 'Allow gifts'], ['comments', 'Allow comments']] as const).map(([key, label]) => <label key={key}>{label}<input type="checkbox" checked={draft[key]} onChange={e => change(key, e.target.checked)} /></label>)}</fieldset>
      <p>Opening a room uses the visibility and permissions above. Your microphone starts off.</p>
      {error && <p role="alert">{error}</p>}<button className="rm-primary" type="button" disabled={publishing} onClick={openLive}>{publishing ? 'Opening…' : 'Open room'}</button><button className="rm-secondary" type="submit" disabled={publishing}>Save private draft</button>
    </form>
  </section>;
}

export function useSoundPlayer() {
  const audio = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState('');
  const [audioError, setAudioError] = useState('');
  function stop() {
    const current = audio.current;
    audio.current = null;
    if (current) { current.pause(); current.removeAttribute('src'); current.load(); }
    setPlaying('');
  }
  useEffect(() => {
    const interrupt = () => { if (document.hidden) audio.current?.pause(); };
    document.addEventListener('visibilitychange', interrupt);
    return () => {
      document.removeEventListener('visibilitychange', interrupt);
      const current = audio.current;
      audio.current = null;
      if (current) { current.pause(); current.removeAttribute('src'); current.load(); }
    };
  }, []);
  function play(sound: Sound, startedAt?: string | null) {
    stop();
    const player = new Audio(asset(sound.id + '.wav'));
    audio.current = player;
    player.dataset.soundId = sound.id;
    if (startedAt) player.onloadedmetadata = () => {
      if (player.duration > 0 && Number.isFinite(player.duration)) player.currentTime = Math.max(0, (Date.now() - Date.parse(startedAt)) / 1000) % player.duration;
    };
    player.loop = true;
    player.volume = 0.72;
    setAudioError('');
    player.onplaying = () => { if (audio.current === player) setPlaying(sound.id); };
    player.onpause = () => { if (audio.current === player) setPlaying(''); };
    const failed = () => { if (audio.current === player) { stop(); setAudioError('Playback could not start. Try playing the sound again.'); } };
    player.onerror = failed;
    void player.play().catch(failed);
  }
  function toggle(sound: Sound) {
    if (audio.current?.dataset.soundId === sound.id && !audio.current.paused) stop();
    else play(sound);
  }
  return { playing, audioError, stop, toggle, play };
}
type Player = ReturnType<typeof useSoundPlayer>;
type Panel = 'host' | 'audience' | 'share' | 'mic' | 'music' | 'gift' | 'exit';

function GiftPicker({ enabled, wallet }: { enabled: boolean; wallet: () => void }) {
  const choices = [
    [21, 'Star wand'], [14, 'Dream cloud'], [12, 'Bunny slippers'], [9, 'Moon mobile'],
    [3, 'Sleep mask'], [10, 'Dream pillow'], [13, 'Resting moon'], [16, 'Sleepy star'],
  ] as const;
  const [selected, setSelected] = useState<number>(choices[0][0]);
  const [quantity, setQuantity] = useState(1);
  return <><div className="rm-gifts">{choices.map(([index, title]) => <button key={index} aria-pressed={selected === index} onClick={() => setSelected(index)}><img src={art('store', index)} alt="" /><span>{title}</span></button>)}</div>
    <div className="rm-quantity"><span>Quantity</span><button aria-label="Decrease quantity" disabled={quantity <= 1} onClick={() => setQuantity(n => n - 1)}>−</button><strong>{quantity}</strong><button aria-label="Increase quantity" disabled={quantity >= 99} onClick={() => setQuantity(n => n + 1)}>＋</button></div>
    <dl className="rm-summary"><div><dt>Recipient</dt><dd>No live participants</dd></div><div><dt>Total</dt><dd>Price unavailable</dd></div></dl>
    <p>{enabled ? 'Sending gifts requires a live recipient and a connected gift catalog.' : 'Gifts are turned off in this room.'}</p>
    <button className="rm-primary" disabled>Send gift</button><button className="rm-secondary" onClick={wallet}>Open wallet</button>
  </>;
}
export function TrackList({ player }: { player: Player }) {
  return <><p>Original soundscapes made for MiNa. Playback is free and stays on this device.</p>{sounds.map(s =>
    <button className="rm-track" key={s.id} aria-pressed={player.playing === s.id} onClick={() => player.toggle(s)}><img src={cover(s.id)} alt="" /><span><strong>{s.title}</strong><small>{s.description}</small></span><b>{player.playing === s.id ? 'Pause' : 'Play'}</b></button>)}</>;
}
export function Sheet({ title, close, children, drawer }: { title: string; close: () => void; children: React.ReactNode; drawer?: boolean }) {
  const box = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = box.current;
    const opener = document.activeElement as HTMLElement | null;
    dialog?.showModal();
    return () => { dialog?.close(); opener?.focus(); };
  }, []);
  return <dialog ref={box} className={'rm-sheet' + (drawer ? ' rm-drawer' : '')} aria-labelledby="rm-sheet-title" onCancel={e => { e.preventDefault(); close(); }} onClick={e => { if (e.target === box.current) {
    const bounds = box.current.getBoundingClientRect();
    if (e.clientX < bounds.left || e.clientX > bounds.right || e.clientY < bounds.top || e.clientY > bounds.bottom) close();
  } }}>
    <header><h2 id="rm-sheet-title">{title}</h2><button aria-label={'Close ' + title} onClick={close}>×</button></header>{children}
  </dialog>;
}

const panelTitles: Record<Panel, string> = {
  host: 'Room details', audience: 'Room audience', share: 'Share with friends', mic: 'Microphone seats', music: 'Music on demand', gift: 'Gifts', exit: 'Leave room?',
};
function ListeningRoom({ route, go, back }: ScreenProps) {
  const draft = getDrafts().find(d => d.id === route.id);
  const source = sounds.find(s => s.id === route.id);
  const [panel, setPanel] = useState<Panel | null>(null);
  const [seat, setSeat] = useState(0);
  const [saved, setSaved] = useState(() => read<string[]>('room.savedSounds', []));
  const [error, setError] = useState('');
  const player = useSoundPlayer();
  if (!draft && !source) return <section className="rm-light"><Header title="Room unavailable" back={back} /><Empty title="This room is unavailable" detail="Return to Voice Rooms to find another room." /></section>;
  const title = draft?.title || source!.title;
  const sound = source || sounds.find(s => s.id === draft?.cover) || sounds[0];
  const roomCover = cover(draft?.cover || sound.id);
  const profile = read('profile', { name: 'Night Listener', avatarId: '' });
  const toggleSaved = () => {
    const current = read<string[]>('room.savedSounds', []);
    const next = current.includes(sound.id) ? current.filter(id => id !== sound.id) : [...current, sound.id];
    try { write('room.savedSounds', next); setSaved(next); setError(''); } catch { setError(errorText); }
  };
  const playing = sounds.find(s => s.id === player.playing);
  return <section className="rm-stage" style={{ "--room-sea": "url(" + asset("moonlit-sea.webp") + ")" } as React.CSSProperties}>
    <div className="rm-stage-top"><button className="rm-stage-label" onClick={() => setPanel('host')}><img src={roomCover} alt="" /><span><strong>{title}</strong><small>{draft ? 'Your private draft' : 'Offline listening room'}</small></span></button>
      <button aria-label="View room audience" onClick={() => setPanel('audience')}><Icon group="home" index={10} /></button>
      <button aria-label="Share room" onClick={() => setPanel('share')}><span aria-hidden="true">↗</span></button>
      <button aria-label="Leave room" onClick={() => setPanel('exit')}><Icon group="room" index={1} /></button>
    </div>
    <div className="rm-stage-tags"><span><Icon group="room" index={4} />{draft?.topic || sound.topic}</span><button onClick={() => go('rooms.ranks')}>Rankings ›</button></div>
    <button className="rm-host-seat" onClick={() => setPanel('host')}><span><img src={roomCover} alt="" /></span><strong>{draft ? profile.name : 'Host seat'}</strong><small>{draft ? 'Draft owner' : 'Unoccupied'}</small></button>
    <div className="rm-seats">{Array.from({ length: 8 }, (_, i) => <button key={i} aria-label={'View microphone seat ' + (i + 1)} onClick={() => { setSeat(i + 1); setPanel('mic'); }}><span><Icon group="room" index={7} /></span>Mic {i + 1}</button>)}</div>
    <div className="rm-stage-bottom"><div className="rm-listening"><span className="rm-kicker">ON THIS DEVICE</span><h2>{playing?.title || sound.title}</h2><p>{playing?.description || sound.description}</p><div><button className="rm-primary" onClick={() => player.toggle(playing || sound)}>{playing ? 'Pause sound' : 'Play soundscape'}</button>
      {source ? <button className="rm-glass" aria-pressed={saved.includes(sound.id)} onClick={toggleSaved}>{saved.includes(sound.id) ? 'Saved ✓' : 'Save sound'}</button> : <button className="rm-glass" onClick={() => go('rooms.create', draft!.id)}>Edit draft</button>}</div></div>
      {(error || player.audioError) && <p role="alert">{error || player.audioError}</p>}
      <div className="rm-stage-tools"><button className="rm-chat-control" onClick={() => setPanel('audience')}>{draft?.comments === false ? 'Comments off' : 'Room audience'}</button>
        <button aria-label="Open microphone settings" onClick={() => { setSeat(0); setPanel('mic'); }}><Icon group="room" index={15} /></button>
        <button aria-label="Open gift picker" onClick={() => setPanel('gift')}><img src={art('store', 7)} alt="" /></button>
        <button aria-label="Open music list" onClick={() => setPanel('music')}><Icon group="room" index={16} /></button>
      </div>
    </div>
    {panel && <Sheet key={panel} title={panelTitles[panel]} close={() => setPanel(null)} drawer={panel === 'music'}>
      {panel === 'host' && <><div className="rm-detail-cover"><img src={roomCover} alt="" /><div><strong>{title}</strong><small>{draft?.topic || sound.topic}</small></div></div>
        <dl className="rm-summary"><div><dt>Room type</dt><dd>{draft ? 'Private draft' : 'Offline soundscape'}</dd></div><div><dt>Host</dt><dd>{draft ? profile.name : 'No live host'}</dd></div>{draft && <div><dt>Visibility when live</dt><dd>{draft.visibility}</dd></div>}</dl>
        <button className="rm-primary" onClick={() => draft ? go('profile') : setPanel('music')}>{draft ? 'View your profile' : 'Browse soundscapes'}</button></>}
      {panel === 'audience' && <Empty title="No live audience" detail="Live participants and room comments will appear when the room is connected." />}
      {panel === 'share' && <Empty title="This room is on your device" detail="Room invitations become available for live rooms with a shareable address." />}
      {panel === 'mic' && <><div className="rm-mic-state"><Icon group="room" index={15} /><strong>{seat ? 'Microphone seat ' + seat : 'Microphone off'}</strong></div><p>Speaking and the seat queue require a live connection. You can listen to a soundscape on this device.</p><button className="rm-primary" onClick={() => setPanel('music')}>Browse sounds</button></>}
      {panel === 'music' && <><TrackList player={player} />{player.audioError && <p role="alert">{player.audioError}</p>}</>}
      {panel === 'gift' && <GiftPicker enabled={draft?.gifts ?? true} wallet={() => go('wallet')} />}
      {panel === 'exit' && <><p>{draft ? 'Your room draft will stay saved on this device.' : 'Audio will stop when you leave this listening room.'}</p><button className="rm-primary" onClick={() => { player.stop(); go('rooms'); }}>Leave room</button><button className="rm-secondary" onClick={() => setPanel(null)}>Keep listening</button></>}
    </Sheet>}
  </section>;
}

function weekDates(lastWeek: boolean) {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() - (start.getUTCDay() + 6) % 7 - (lastWeek ? 7 : 0));
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(start); d.setUTCDate(d.getUTCDate() + i); return d;
  });
}
type Rank = { room_id: string; score: number; title: string };
export function Rankings({ back, roomId, embedded = false, go }: { back: ScreenProps['back']; roomId?: string; embedded?: boolean; go?: Go }) {
  const [gift, setGift] = useState(false);
  const [lastWeek, setLastWeek] = useState(false);
  const [list, setList] = useState<Rank[]>([]);
  const [days, setDays] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);
  const [sync, setSync] = useState(0);
  const [error, setError] = useState('');
  const dates = weekDates(lastWeek);
  const start = dates[0].toISOString().slice(0,10);
  const today = new Date().toISOString().slice(0,10);
  useEffect(() => {
    let current = true;
    setReady(false); setError(''); setList([]); setDays([]);
    (async () => {
      const ranks = await rest<{ room_id: string; score: number }[]>('rpc/room_rankings', jsonRequest('POST', { start_day: start, gift_ranking: gift }));
      const checks = roomId ? await rest<{day: string}[]>('room_checkins?select=day&room_id=eq.' + roomId + '&user_id=eq.' + userId() + '&day=gte.' + start) : [];
      const rooms = ranks.length ? await rest<{id: string; title: string}[]>('rooms?select=id,title&id=in.(' + ranks.map(r => r.room_id).join(',') + ')') : [];
      if (current) { setList(ranks.map(r => ({ ...r, title: rooms.find(x => x.id === r.room_id)?.title || 'Room' }))); setDays(checks.map(d => d.day)); setReady(true); }
    })().catch(() => { if (current) setError('Rankings could not load.'); });
    return () => { current = false; };
  }, [gift, start, sync, roomId]);
  async function checkIn() {
    if (!roomId || busy) return;
    setBusy(true); setError('');
    try { await rest('rpc/check_in', jsonRequest('POST', { target_room: roomId })); setSync(n => n + 1); }
    catch { setError('Check-in could not be confirmed. Please try again.'); } finally { setBusy(false); }
  }
  const dateFormat: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric', timeZone: 'UTC' };
  const rank = list.findIndex(r => r.room_id === roomId);
  return <section className="rm-light rm-ranks">{!embedded && <Header title="Rankings" back={back} />}
    <div className="rm-rank-body"><div className="rm-rank-tabs" role="group" aria-label="Ranking category">{['Room ranking', 'Gift ranking'].map((item, i) => <button aria-pressed={gift === Boolean(i)} key={item} onClick={() => setGift(Boolean(i))}>{item}</button>)}</div>
      <div className="rm-week"><span>{dates[0].toLocaleDateString('en-US', dateFormat)} – {dates[6].toLocaleDateString('en-US', dateFormat)} UTC</span><div>{['This week', 'Last week'].map((name, i) => <button key={name} aria-pressed={lastWeek === Boolean(i)} onClick={() => setLastWeek(Boolean(i))}>{name}</button>)}</div></div>
      <div className="rm-podium">{[2, 1, 3].map((pos, i) => {
        const item = list[pos - 1];
        return <div key={pos} className={'rm-position p' + pos}><span><Icon group="rank" index={[9, 11, 10][i]} /></span><strong>{pos}</strong><small>{item ? item.title : '—'}</small>{item && <small>{item.score} {gift ? 'coins' : 'check-ins'}</small>}</div>;
      })}</div>
      {list.slice(3).map((item, i) => <div key={item.room_id} className="rm-member"><strong>{i + 4} · {item.title}</strong><span>{item.score} {gift ? 'coins' : 'check-ins'}</span></div>)}
      {!list.length && !error && <p className="rm-note">{ready ? 'No ranked rooms for this period.' : 'Loading rankings…'}</p>}
      {error && <p role="alert">{error} <button onClick={() => setSync(n => n + 1)}>Retry</button></p>}
      {roomId && <section className="rm-checkin"><h2>This room</h2><p>{rank < 0 ? 'Unranked' : 'Rank ' + (rank + 1)} · {gift ? 'Gift value' : 'Check-ins'}</p>
        {!gift && <><div className="rm-days">{dates.map(date => { const day = date.toISOString().slice(0,10); return <div key={day}><span>{date.toLocaleDateString('en-US', {weekday: 'narrow',timeZone:'UTC'})}</span><b aria-label={day + (days.includes(day) ? ', checked in' : ', no check-in')}>{days.includes(day) ? '✓' : date.getUTCDate()}</b></div>; })}</div>
          {!lastWeek && <button className="rm-primary" disabled={!ready || busy || days.includes(today)} onClick={checkIn}>{days.includes(today) ? 'Checked in today' : 'Check in today'}</button>}</>}
      </section>}
      {!roomId && go && <button className="rm-primary" onClick={() => go('rooms.liveList')}>Find a room to check in</button>}
    </div></section>;
}
export default function Rooms(props: ScreenProps) {
  switch (props.route.name) {
    case 'rooms.live': return isUuid(props.route.id) ? <LiveRoom key={props.route.id} {...props} /> : <Empty title="Room unavailable" />;
    case 'rooms.liveList': return <section className="rm-light"><Header title="Live rooms" back={props.back}/><div className="rm-inset"><LiveDiscovery go={props.go} list /></div></section>;
    case 'rooms.search': case 'rooms.sounds': return <SearchRooms key={props.route.name} {...props} />;
    case 'rooms.create': return <RoomEditor key={props.route.id || 'new'} {...props} />;
    case 'rooms.stage': return <ListeningRoom key={props.route.id} {...props} />;
    case 'rooms.ranks': return <Rankings back={props.back} go={props.go} />;
    default: return <Discovery go={props.go} />;
  }
}
