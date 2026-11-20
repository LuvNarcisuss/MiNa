import React, { useEffect, useRef, useState } from 'react';
import { rest, userId } from './cloud';
import { giftNames } from './Economy';
import { art, Empty, Header, read, ScreenProps, write } from './shared';
import { asset, cover, Icon, Rankings, Sheet, sounds, useSoundPlayer } from './Rooms';
import { jsonRequest, makeId, Member, useRoomSession } from './roomSession';

type Panel = 'host' | 'audience' | 'mic' | 'music' | 'gift' | 'share' | 'exit' | 'chat' | 'ranking';
const titles: Record<Panel, string> = {
  host: 'Room details', audience: 'Room audience', mic: 'Microphone seats', music: 'Music on demand',
  ranking: 'Rankings', gift: 'Send a gift', share: 'Share with friends', exit: 'Leave room?', chat: 'Room chat',
};
const failure = (error: unknown) => error instanceof Error ? error.message : 'The request failed. Try again.';
type Name = (id: string) => string;

function Gifts({ room, members, name, go, close }: { room: string; members: Member[]; name: Name; go: ScreenProps['go']; close: () => void }) {
  const key = 'room.gift.' + room;
  const previous = read(key, { index: 0, quantity: 1, recipient: '', operation: '', backpack: false });
  const [index, setIndex] = useState(previous.index);
  const [quantity, setQuantity] = useState(previous.quantity);
  const [recipient, setRecipient] = useState(previous.recipient);
  const [backpack, setBackpack] = useState(previous.backpack || false);
  const [inventory, setInventory] = useState<Record<number, number>>({});
  const [catalog, setCatalog] = useState<Record<number, number>>({});
  const [balance, setBalance] = useState<number | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const [op, setOp] = useState(previous.operation);
  const me = userId();
  const recipients = members.filter(m => m.user_id !== me);
  const unitPrice = catalog[index];
  const total = backpack ? 0 : (unitPrice ?? 0) * quantity;
  const limit = backpack ? Math.min(99, inventory[index] || 0) : unitPrice === 0 ? 1 : 99;
  const valid = recipients.some(m => m.user_id === recipient);
  useEffect(() => {
    let active = true;
    Promise.all([rest<{balance: number}[]>('wallets?owner_id=eq.' + me + '&select=balance'), rest<{gift_index: number; unit_price: number}[]>('gift_catalog?select=gift_index,unit_price'), rest<{gift_index: number; quantity: number}[]>('gift_inventory?owner_id=eq.' + me + '&select=gift_index,quantity')]).then(([wallet, prices, bag]) => {
      if (!active) return;
      setBalance(wallet[0]?.balance ?? null); setCatalog(Object.fromEntries(prices.map(g => [g.gift_index, g.unit_price]))); setInventory(Object.fromEntries(bag.map(g => [g.gift_index, g.quantity])));
    }).catch(() => { if (active) setError('The gift catalog could not load. Reopen gifts to try again.'); });
    return () => { active = false; };
  }, [me]);
  function retain(operation: string) { write(key, { index, quantity, recipient, operation, backpack }); }
  async function send() {
    if (!valid || busy) return;
    setBusy(true); setError('');
    try {
      const operation = op || makeId(); setOp(operation); retain(operation);
      const receipt = await rest<{id:string;balance:number}>('rpc/send_gift', jsonRequest('POST', { target_room: room, recipient, gift_index: index, quantity, operation, use_inventory: backpack }));
      if (receipt?.id !== operation) throw new Error('The gift receipt could not be confirmed. Retry with this selection.');
      setBalance(receipt.balance);
      setSent(true); setConfirm(false);
      write(key, { index, quantity, recipient, operation: '', backpack });
    } catch (e) { setError(failure(e)); } finally { setBusy(false); }
  }
  const change = (action: () => void) => { setOp(''); setError(''); action(); };
  if (sent) return <><Empty title="Gift sent" detail={quantity + ' × ' + giftNames[index] + ' sent to ' + name(recipient) + '.'} /><button className="rm-primary" onClick={close}>Done</button></>;
  return <>
    {!confirm && <><div className="rm-rank-tabs"><button aria-pressed={!backpack} onClick={() => change(() => { setBackpack(false); setQuantity(1); })}>Catalog</button><button aria-pressed={backpack} onClick={() => change(() => { setBackpack(true); setQuantity(1); const owned = Object.keys(inventory).find(i => inventory[Number(i)] > 0); if (owned) setIndex(Number(owned)); })}>Backpack</button></div>{backpack && !Object.values(inventory).some(n => n > 0) && <p>Your backpack is empty.</p>}<div className="rm-gifts">{giftNames.map((label, i) => (!backpack || inventory[i] > 0) && <button key={label} aria-pressed={index === i} onClick={() => change(() => { setIndex(i); setQuantity(1); })}><img src={art('store', i + 3)} alt="" /><span>{label}</span><strong>{backpack ? inventory[i] + ' owned' : catalog[i] === 0 ? 'Free' : catalog[i] !== undefined ? catalog[i] + ' coins' : 'Unavailable'}</strong></button>)}</div>
      <label className="rm-recipient">Recipient<select value={valid ? recipient : ''} onChange={e => change(() => setRecipient(e.target.value))}><option value="">{recipients.length ? 'Select a recipient' : 'No other participants'}</option>{recipients.map(m => <option key={m.user_id} value={m.user_id}>{name(m.user_id)}</option>)}</select></label>
      <div className="rm-quantity"><span>Quantity</span><button disabled={quantity <= 1} aria-label="Decrease quantity" onClick={() => change(() => setQuantity(q => q - 1))}>−</button><strong>{quantity}</strong><button disabled={quantity >= limit} aria-label="Increase quantity" onClick={() => change(() => setQuantity(q => q + 1))}>＋</button></div></>}
    <dl className="rm-summary">{confirm && <><div><dt>Gift</dt><dd>{quantity} × {giftNames[index]}</dd></div><div><dt>Recipient</dt><dd>{name(recipient)}</dd></div></>}<div><dt>Total</dt><dd>{unitPrice === undefined ? 'Unavailable' : total + ' coins'}</dd></div><div><dt>Balance</dt><dd>{balance === null ? 'Unavailable' : balance + ' coins'}</dd></div></dl>
    {error && <p role="alert">{error}</p>}
    {balance !== null && total > balance ? <button className="rm-primary" onClick={() => { retain(op); sessionStorage.setItem('mina.resumeGift.' + me + '.' + room, String(Date.now())); go('wallet'); }}>Open wallet</button> :
      <button className="rm-primary" disabled={!valid || busy || unitPrice === undefined || quantity > limit || (total > 0 && balance === null)} onClick={() => confirm ? void send() : setConfirm(true)}>{busy ? 'Sending…' : confirm ? 'Confirm and send' : 'Review gift'}</button>}
    {confirm && <button className="rm-secondary" disabled={busy} onClick={() => setConfirm(false)}>Change selection</button>}
  </>;
}
function Invitations({ room }: { room: string }) {
  const [friends, setFriends] = useState<{ id: string; name: string }[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<string[]>([]);
  const ops = useRef<Record<string, string>>({});
  useEffect(() => {
    let active = true;
    const me = userId();
    (async () => {
      const [out, incoming] = await Promise.all([rest<{followed_id: string}[]>('follows?follower_id=eq.' + me), rest<{follower_id: string}[]>('follows?followed_id=eq.' + me)]);
      const ids = out.map(f => f.followed_id).filter(id => incoming.some(f => f.follower_id === id));
      const people = ids.length ? await rest<{id: string; name: string}[]>('profiles?select=id,name&id=in.(' + ids.join(',') + ')') : [];
      if (active) { setFriends(people); setLoaded(true); }
    })().catch(() => { if (active) setNotice('Friends could not load. Reopen this panel to retry.'); });
    return () => { active = false; };
  }, []);
  async function invite(id: string) {
    setBusy(true); setNotice('');
    try {
      const operation = ops.current[id] || (ops.current[id] = makeId());
      const exists = await rest<{id: string}[]>('messages?select=id&id=eq.' + operation);
      if (!exists.length) await rest('messages', jsonRequest('POST', { id: operation, sender_id: userId(), recipient_id: id, body: 'mina:room:' + room }));
      setSent(v => [...v, id]);
    } catch (e) { setNotice(failure(e)); } finally { setBusy(false); }
  }
  return <>{!friends.length && <Empty title={loaded ? 'No friends to invite' : 'Finding friends…'} detail="Room invitations appear in your friend’s conversation. Room visibility still applies." />}
    {friends.map(f => <div className="rm-member" key={f.id}><strong>{f.name}</strong><button disabled={busy || sent.includes(f.id)} onClick={() => invite(f.id)}>{sent.includes(f.id) ? 'Sent' : 'Invite'}</button></div>)}{notice && <p role="status">{notice}</p>}</>;
}
type SeatRequest = { user_id: string; seat: number; created_at: string };
function Seats({ id, target, session }: { id: string; target: number; session: ReturnType<typeof useRoomSession> }) {
  const me = userId();
  const [requests, setRequests] = useState<SeatRequest[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [sync, setSync] = useState(0);
  const [ready, setReady] = useState(false);
  const host = session.room?.host_id === me;
  const mySeat = session.members.find(m => m.user_id === me)?.seat;
  const occupied = session.members.find(m => m.seat === target && m.user_id !== me);
  const mine = requests.find(r => r.user_id === me);
  const filter = 'room_id=eq.' + id;
  useEffect(() => {
    let canceled = false, timer = 0;
    const poll = async () => {
      try {
        const rows = await rest<SeatRequest[]>('room_seat_requests?' + filter + '&order=created_at.asc');
        if (!canceled) { setRequests(rows); setReady(true); }
      } catch { if (!canceled) { setReady(false); setNotice('The seat queue could not load.'); } }
      if (!canceled) timer = window.setTimeout(poll, 2500);
    };
    void poll();
    return () => { canceled = true; window.clearTimeout(timer); };
  }, [filter, sync]);
  async function act(action: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true); setNotice('');
    try { await action(); session.refresh(); setSync(n => n + 1); }
    catch (e) { setNotice(failure(e)); } finally { setBusy(false); }
  }
  const remove = (uid: string) => rest('room_seat_requests?' + filter + '&user_id=eq.' + uid, { method: 'DELETE' });
  const assigned = mySeat !== null && mySeat !== undefined;
  return <><p>Microphone audio stops when MiNa goes into the background. You choose when to turn it on again.</p>
    {assigned ? <>{session.mic === 'off' ? <button className="rm-primary" disabled={busy || session.status !== 'active'} onClick={() => act(() => session.speak(mySeat))}>Turn on microphone</button> : <button className="rm-primary" onClick={session.mute}>{session.mic === 'on' ? 'Mute microphone' : 'Unmute microphone'}</button>}
      <button className="rm-secondary" disabled={busy} onClick={() => act(session.releaseSeat)}>{host ? 'Turn microphone off' : 'Leave microphone seat'}</button></> :
      mine ? <><p>Seat {mine.seat} · Queue position {requests.findIndex(r => r.user_id === me) + 1}</p><button className="rm-secondary" disabled={busy} onClick={() => act(() => remove(me))}>Cancel request</button></> :
      <button className="rm-primary" disabled={!ready || busy || session.status !== 'active'} onClick={() => act(() => rest('room_seat_requests', jsonRequest('POST', { room_id: id, user_id: me, seat: target || 1 })))}>{occupied ? 'Queue for microphone seat ' + target : 'Request microphone seat ' + (target || 1)}</button>}
    {host && <><h3>Speaker requests</h3>{!requests.length && <p>No one is waiting for a seat.</p>}
      {requests.map(r => <div className="rm-member" key={r.user_id}><span>{session.names[r.user_id] || 'Listener'} · Mic {r.seat}</span><button disabled={busy || session.members.some(m => m.seat === r.seat && m.user_id !== r.user_id)} onClick={() => act(async () => {
        const rows = await rest<Member[]>('room_members?' + filter + '&user_id=eq.' + r.user_id, jsonRequest('PATCH', { seat: r.seat }));
        if (!rows.length) throw new Error('This listener has left.');
      })}>Admit</button><button disabled={busy} onClick={() => act(() => remove(r.user_id))}>Decline</button></div>)}</>}
    {notice && <p role="alert">{notice}</p>}</>;
}

export default function LiveRoom({ route, go, back }: ScreenProps) {
  const id = route.id!;
  const me = userId();
  const session = useRoomSession(id);
  const player = useSoundPlayer();
  const [musicEnabled, setMusicEnabled] = useState(false);
  const [panel, setPanel] = useState<Panel | null>(() => {
    const key = 'mina.resumeGift.' + me + '.' + id;
    const timestamp = Number(sessionStorage.getItem(key));
    sessionStorage.removeItem(key);
    return Date.now() - timestamp < 600000 ? 'gift' : null;
  });
  const [seat, setSeat] = useState(1);
  const [body, setBody] = useState('');
  const op = useRef({ text: '', id: '' });
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [hostFollowed, setHostFollowed] = useState(false);
  const room = session.room;
  const host = room?.host_id === me;
  const music = sounds.find(s => s.id === room?.music_track);
  useEffect(() => {
    if (musicEnabled && music && session.status === 'active') player.play(music, room?.music_started_at);
    else player.stop();
  }, [musicEnabled, music?.id, room?.music_started_at, session.status]);
  const name = (who: string) => session.names[who] || (who === me ? 'You' : 'Listener');
  useEffect(() => {
    let active = true;
    if (room && !host) rest<unknown[]>('follows?follower_id=eq.' + me + '&followed_id=eq.' + room.host_id).then(rows => { if (active) setHostFollowed(!!rows.length); }).catch(() => {});
    return () => { active = false; };
  }, [room?.host_id, host, me]);
  async function act(action: () => Promise<void>) {
    if (busy) return;
    setBusy(true); setNotice('');
    try { await action(); session.refresh(); } catch (e) { setNotice(failure(e)); } finally { setBusy(false); }
  }
  function send(e: React.FormEvent) {
    e.preventDefault();
    const text = body.trim();
    if (!text || !room?.allow_comments || session.status !== 'active') return;
    void act(async () => {
      if (op.current.text !== text) op.current = { text, id: makeId() };
      const existing = await rest<unknown[]>('room_messages?select=id&id=eq.' + op.current.id);
      if (!existing.length) await rest('room_messages', jsonRequest('POST', { id: op.current.id, room_id: id, owner_id: me, body: text }));
      op.current = { text: '', id: '' }; setBody('');
    });
  }
  async function chooseMusic(sound: typeof sounds[number]) {
    if (!room || session.status !== 'active') return;
    if (host) {
      const stopping = room.music_track === sound.id;
      const changed = await rest<{id:string}[]>('rooms?id=eq.' + id + '&host_id=eq.' + me + '&closed=eq.false', jsonRequest('PATCH', {
        music_track: stopping ? null : sound.id, music_started_at: stopping ? null : new Date().toISOString(),
      }));
      if (!changed.length) throw new Error('The room music could not be updated.');
      if (!stopping) setMusicEnabled(true);
    } else {
      if (!room.allow_comments) throw new Error('Music requests are off while room chat is closed.');
      const text = 'mina:music:' + sound.id;
      if (op.current.text !== text) op.current = { text, id: makeId() };
      const previous = await rest<unknown[]>('room_messages?select=id&id=eq.' + op.current.id);
      if (!previous.length) await rest('room_messages', jsonRequest('POST', {id: op.current.id, room_id: id, owner_id: me, body: text}));
      op.current = { text: '', id: '' }; setNotice('Requested ' + sound.title + ' in room chat.');
    }
  }
  function chatBody(text: string) {
    const request = sounds.find(s => 'mina:music:' + s.id === text);
    return request ? 'Requested “' + request.title + '”.' : text;
  }
  function open(next: Panel) { setNotice(''); setPanel(next); }
  if (!room) return <section className="rm-light"><Header title="Voice room" back={back} /><Empty title={session.status === 'ended' ? 'This room has ended or is private' : session.status === 'retry' ? 'Could not join this room' : 'Connecting to the room…'} detail={session.status === 'ended' ? 'Find another open room in Voice Rooms.' : ''}>
    {session.status === 'retry' && <button className="rm-primary" onClick={session.refresh}>Retry</button>}</Empty></section>;
  const active = session.status === 'active';
  const runtime = Math.max(0, Math.floor((Date.now() - Date.parse(room.created_at)) / 60000));
  const chat = <><div className="rm-chat-history">{session.messages.length ? session.messages.map(m => <p key={m.id}><b>{name(m.owner_id)}</b> {chatBody(m.body)}</p>) : <p>No room messages yet.</p>}</div>
    {room.allow_comments ? <form className="rm-chat-form" onSubmit={send}><input aria-label="Message the room" value={body} maxLength={1200} onChange={e => setBody(e.target.value)} placeholder="Say hello…" /><button disabled={!active || !body.trim() || busy}>Send</button></form> : <p>Comments are off in this room.</p>}</>;
  return <section className="rm-stage" style={{ '--room-sea': 'url(' + asset('moonlit-sea.webp') + ')' } as React.CSSProperties}>
    <div className="rm-stage-top"><button className="rm-stage-label" onClick={() => open('host')}><img src={cover(room.cover)} alt="" /><span><strong>{room.title}</strong><small>{name(room.host_id)}</small></span></button>
      <button aria-label={'View audience, ' + session.members.length + ' present'} onClick={() => open('audience')}><Icon group="room" index={3} />{session.members.length}</button><button aria-label="Share room" onClick={() => open('share')}><Icon group="room" index={2} /></button>
      <button aria-label="Leave room" onClick={() => open('exit')}><Icon group="room" index={1} /></button></div>
    <div className="rm-stage-tags"><span><Icon group="room" index={4} />{room.topic}</span><button onClick={() => open('ranking')}>Rankings ›</button><span><Icon group="room" index={13} />{runtime} min</span></div>
    <button className="rm-host-seat" onClick={() => open('host')}><span><img src={session.portraits[room.host_id] || cover(room.cover)} alt="" /></span><strong>{name(room.host_id)}</strong><small>{session.members.some(m => m.user_id === room.host_id) ? 'Host' : 'Host away'}</small></button>
    <div className="rm-seats">{Array.from({ length: 8 }, (_, i) => {
      const member = session.members.find(m => m.seat === i + 1);
      return <button key={i} onClick={() => { setSeat(i + 1); open('mic'); }} aria-label={'Microphone seat ' + (i + 1) + (member ? ', ' + name(member.user_id) : ', available')}><span>{member ? session.portraits[member.user_id] ? <img className="rm-avatar" src={session.portraits[member.user_id]} alt="" /> : name(member.user_id).slice(0, 2).toUpperCase() : <Icon group="room" index={7} />}</span>{member ? name(member.user_id) : 'Mic ' + (i + 1)}</button>;
    })}</div>
    <div className="rm-stage-bottom"><div className="rm-live-status" role="status">{active ? (session.connections ? 'Voice connected · ' + session.connections + (session.connections === 1 ? ' peer' : ' peers') : 'In room · No voice connection yet') : 'Reconnecting…'} · {session.mic === 'on' ? 'Mic on' : session.mic === 'muted' ? 'Muted' : 'Mic off'}</div>
      {session.audioBlocked && <button className="rm-primary" onClick={() => act(async () => { await session.hear(); })}>Enable room audio</button>}
      {session.notice && <p>{session.notice}</p>}
      {chat}<div className="rm-stage-tools"><button className="rm-chat-control" onClick={() => open('chat')}>Room chat</button><button aria-label="Microphone settings" onClick={() => open('mic')}><Icon group="room" index={15} /></button><button aria-label="Choose a gift" disabled={!room.allow_gifts} onClick={() => open('gift')}><Icon group="room" index={19} /></button><button aria-label="Music on demand" onClick={() => open('music')}><Icon group="room" index={16} /></button></div>
      {notice && !panel && <p role="alert">{notice}</p>}
    </div>
    {panel && <Sheet key={panel} title={panel === 'exit' && host ? 'End this room?' : titles[panel]} close={() => setPanel(null)} drawer={panel === 'music'}>
      {panel === 'audience' && <>{session.members.map(m => <div className="rm-member" key={m.user_id}><button onClick={() => go(m.user_id === me ? 'profile' : 'person', m.user_id)}>{name(m.user_id)}</button><span>{m.seat === null ? 'Listening' : m.seat === 0 ? 'Host' : 'Mic ' + m.seat}</span>{host && m.seat !== null && m.user_id !== me && <button disabled={busy} onClick={() => act(async () => { await rest('room_members?room_id=eq.' + id + '&user_id=eq.' + m.user_id, jsonRequest('PATCH', { seat: null })); })}>Remove from mic</button>}</div>)}</>}
      {panel === 'host' && <><div className="rm-detail-cover"><img src={cover(room.cover)} alt="" /><div><strong>{room.title}</strong><small>{room.topic}</small></div></div><dl className="rm-summary"><div><dt>Host</dt><dd>{name(room.host_id)}</dd></div><div><dt>Audience</dt><dd>{session.members.length}</dd></div><div><dt>Open for</dt><dd>{runtime} min</dd></div></dl><button className="rm-primary" onClick={() => go(host ? 'profile' : 'person', room.host_id)}>View host profile</button>
        {!host && room.allow_follow && <button className="rm-secondary" disabled={busy} onClick={() => act(async () => {
          if (hostFollowed) await rest('follows?follower_id=eq.' + me + '&followed_id=eq.' + room.host_id, { method: 'DELETE' });
          else await rest('follows', jsonRequest('POST', { follower_id: me, followed_id: room.host_id }));
          setHostFollowed(!hostFollowed);
        })}>{hostFollowed ? 'Unfollow host' : 'Follow host'}</button>}</>}
      {panel === 'mic' && <Seats id={id} target={seat} session={session} />}
      {panel === 'chat' && chat}
      {panel === 'ranking' && <Rankings embedded roomId={id} back={() => setPanel(null)} />}
      {panel === 'share' && <Invitations room={id} />}
      {panel === 'music' && <><p>{music ? 'Room selection: ' + music.title : 'No music is selected.'} {host ? 'Choose a soundscape to play in the room.' : 'Ask the host to play a soundscape.'}</p>
        {music && <button className="rm-primary" onClick={() => {
          if (player.playing) { setMusicEnabled(false); player.stop(); }
          else { setMusicEnabled(true); player.play(music, room.music_started_at); }
        }}>{player.playing ? 'Mute room music' : 'Listen to room music'}</button>}
        {sounds.map(sound => <button className="rm-track" disabled={busy || !active || (!host && !room.allow_comments)} key={sound.id} onClick={() => act(() => chooseMusic(sound))}><img src={cover(sound.id)} alt="" /><span><strong>{sound.title}</strong><small>{sound.description} · Free</small></span><b>{host ? music?.id === sound.id ? 'Stop' : 'Play' : 'Request'}</b></button>)}
        {player.audioError && <p role="alert">{player.audioError}</p>}</>}
      {panel === 'gift' && <Gifts room={id} members={active ? session.members : []} name={name} go={go} close={() => setPanel(null)} />}
      {panel === 'exit' && <><p>{host ? 'Ending the room disconnects every participant and closes its chat.' : 'Your microphone and room audio will disconnect.'}</p><button className="rm-primary" disabled={busy} onClick={() => act(async () => {
        if (host) {
          const rows = await rest<unknown[]>('rooms?id=eq.' + id + '&host_id=eq.' + me, jsonRequest('PATCH', { closed: true }));
          if (!rows.length) throw new Error('Could not end this room.');
        }
        go('rooms');
      })}>{host ? 'End room for everyone' : 'Leave room'}</button><button className="rm-secondary" disabled={busy} onClick={() => setPanel(null)}>Stay in room</button></>}
      {notice && <p role="alert">{notice}</p>}
    </Sheet>}
  </section>;
}
