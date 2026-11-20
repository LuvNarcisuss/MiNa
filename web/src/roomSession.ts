import { useEffect, useRef, useState } from 'react';
import { mediaUrl, rest, userId } from './cloud';

export type LiveRoomRecord = {
  id: string; host_id: string; title: string; topic: string; cover: string; visibility: string;
  music_track: string | null; music_started_at: string | null; allow_follow: boolean; allow_gifts: boolean; allow_comments: boolean; closed: boolean; created_at: string;
};
export type Member = { user_id: string; seat: number | null; joined_at: string; last_seen: string };
export type RoomMessage = { id: string; owner_id: string; body: string; created_at: string };
type SignalBody = { fromSession: string; toSession: string; exchange: string; description: RTCSessionDescriptionInit };
type Signal = { id: number; sender_id: string; body: SignalBody };
type Peer = { pc: RTCPeerConnection; element: HTMLAudioElement; session: string; exchange: string; started: number };
type PeerOptions = { room: string; me: string; session: string; update: (connected: number, blocked: boolean) => void };
export const jsonRequest = (method: string, value?: unknown, prefer = 'return=representation'): RequestInit => ({
  method, headers: { 'Content-Type': 'application/json', Prefer: prefer }, ...(value === undefined ? {} : { body: JSON.stringify(value) }),
});
export {newId as makeId} from './ids';
import {newId as makeId} from './ids';
export const isUuid = (id: string | undefined) => /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(id || '');
const time = (date: string) => encodeURIComponent(date);

async function localDescription(pc: RTCPeerConnection, description: RTCSessionDescriptionInit) {
  await pc.setLocalDescription(description);
  if (pc.iceGatheringState !== 'complete') await new Promise<void>(resolve => {
    function finish() { window.clearTimeout(timer); pc.removeEventListener('icegatheringstatechange', changed); resolve(); }
    function changed() { if (pc.iceGatheringState === 'complete') finish(); }
    const timer = window.setTimeout(finish, 3500);
    pc.addEventListener('icegatheringstatechange', changed);
  });
  const ready = pc.localDescription;
  if (!ready) throw new Error('Voice connection closed.');
  return { type: ready.type, sdp: ready.sdp };
}

class RoomAudio {
  private peers = new Map<string, Peer>();
  private microphone: MediaStreamTrack | null = null;
  private stopped = false;
  constructor(private options: PeerOptions) {}
  private report() {
    if (this.stopped) return;
    const peers = Array.from(this.peers.values());
    this.options.update(peers.filter(p => p.pc.connectionState === 'connected').length,
      peers.some(p => p.element.srcObject && p.element.paused));
  }
  private remove(id: string) {
    const peer = this.peers.get(id);
    if (!peer) return;
    this.peers.delete(id);
    peer.pc.close(); peer.element.pause(); peer.element.srcObject = null; peer.element.remove();
    this.report();
  }
  private create(member: Member, exchange: string) {
    this.remove(member.user_id);
    const config = window as Window & { MiNaIceServers?: RTCIceServer[] };
    const pc = new RTCPeerConnection({ iceServers: config.MiNaIceServers || [] });
    const element = document.createElement('audio');
    element.autoplay = true; element.muted = member.seat === null;
    element.setAttribute('playsinline', ''); element.hidden = true;
    document.body.appendChild(element);
    const peer: Peer = { pc, element, session: member.joined_at, exchange, started: Date.now() };
    this.peers.set(member.user_id, peer);
    pc.onconnectionstatechange = () => this.report();
    pc.ontrack = e => {
      if (this.stopped || this.peers.get(member.user_id) !== peer) return;
      element.srcObject = new MediaStream([e.track]);
      void element.play().catch(() => this.report());
    };
    element.onplaying = element.onpause = () => this.report();
    return peer;
  }
  private async send(id: string, peer: Peer, description: RTCSessionDescriptionInit) {
    const ready = await localDescription(peer.pc, description);
    if (this.stopped || this.peers.get(id) !== peer) return;
    await rest('room_signals', jsonRequest('POST', {
      room_id: this.options.room, sender_id: this.options.me, recipient_id: id,
      body: { fromSession: this.options.session, toSession: peer.session, exchange: peer.exchange, description: ready },
    }, 'return=minimal'));
  }
  async refresh(members: Member[], incoming: Signal[]) {
    if (this.stopped || !window.RTCPeerConnection) return;
    const me = members.find(m => m.user_id === this.options.me);
    if (!me) return;
    const wanted = members.filter(m => m.user_id !== this.options.me && (m.seat !== null || me.seat !== null));
    for (const [id, peer] of this.peers) {
      const member = wanted.find(m => m.user_id === id);
      if (!member || peer.session !== member.joined_at) this.remove(id);
      else peer.element.muted = member.seat === null;
    }
    for (const signal of incoming) {
      if (this.stopped) return;
      const body = signal.body;
      const member = wanted.find(m => m.user_id === signal.sender_id && m.joined_at === body?.fromSession);
      if (!member || body.toSession !== this.options.session || !body.description) continue;
      const id = member.user_id;
      if (body.description.type === 'offer' && id < this.options.me) {
        const peer = this.create(member, body.exchange);
        await peer.pc.setRemoteDescription(body.description);
        const channel = peer.pc.getTransceivers()[0];
        if (!channel) { this.remove(id); continue; }
        channel.direction = 'sendrecv';
        await channel.sender.replaceTrack(this.microphone);
        await this.send(id, peer, await peer.pc.createAnswer());
      } else if (body.description.type === 'answer') {
        const peer = this.peers.get(id);
        if (peer?.exchange === body.exchange && peer.pc.signalingState === 'have-local-offer') await peer.pc.setRemoteDescription(body.description);
      }
    }
    await Promise.allSettled(wanted.filter(m => this.options.me < m.user_id).map(async member => {
      const current = this.peers.get(member.user_id);
      if (current?.session === member.joined_at && (current.pc.connectionState === 'connected' || Date.now() - current.started < 24000)) return;
      const peer = this.create(member, makeId());
      const channel = peer.pc.addTransceiver('audio', { direction: 'sendrecv' });
      await channel.sender.replaceTrack(this.microphone);
      await this.send(member.user_id, peer, await peer.pc.createOffer());
    }));
  }
  async setMic(track: MediaStreamTrack | null) {
    this.microphone = track;
    await Promise.all(Array.from(this.peers.values(), async peer => {
      const channel = peer.pc.getTransceivers()[0];
      if (channel) await channel.sender.replaceTrack(track);
    }));
  }
  async hear() {
    await Promise.all(Array.from(this.peers.values(), p => p.element.srcObject ? p.element.play() : Promise.resolve()));
    this.report();
  }
  close() {
    this.stopped = true;
    this.microphone?.stop(); this.microphone = null;
    for (const id of this.peers.keys()) this.remove(id);
  }
}

export function useRoomSession(id: string) {
  const [room, setRoom] = useState<LiveRoomRecord | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [messages, setMessages] = useState<RoomMessage[]>([]);
  const [names, setNames] = useState<Record<string, string>>({});
  const [portraits, setPortraits] = useState<Record<string, string>>({});
  const [status, setStatus] = useState<'joining' | 'active' | 'retry' | 'ended'>('joining');
  const [connections, setConnections] = useState(0);
  const [audioBlocked, setAudioBlocked] = useState(false);
  const [mic, setMic] = useState<'off' | 'on' | 'muted'>('off');
  const [notice, setNotice] = useState('');
  const comm = useRef<RoomAudio | null>(null);
  const track = useRef<MediaStreamTrack | null>(null);
  const joinTime = useRef('');
  const acquire = useRef(0);
  const owner = useRef(false);
  const retryNow = useRef<() => void>(() => {});
  const seatPath = () => 'room_members?room_id=eq.' + id + '&user_id=eq.' + userId() + '&joined_at=eq.' + time(joinTime.current);
  function stopMicrophone() {
    acquire.current++;
    if (track.current) { track.current.onended = null; track.current.stop(); track.current = null; }
    void comm.current?.setMic(null).catch(() => {});
    setMic('off');
  }
  async function releaseSeat() {
    stopMicrophone();
    if (joinTime.current && !owner.current) await rest(seatPath(), jsonRequest('PATCH', { seat: null }, 'return=minimal'));
  }
  useEffect(() => {
    let canceled = false, ended = false, busy = false, timer = 0, cursor = 0, lastBeat = 0, lastConfirmed = 0;
    let joined = '', nextProfileRefresh = 0, loadingProfiles = false;
    let rosterNames: Record<string, string> = {}, rosterPortraits: Record<string, string> = {};
    const me = userId();
    const filter = 'room_id=eq.' + id;
    const membership = () => 'room_members?' + filter + '&user_id=eq.' + me + '&joined_at=eq.' + time(joined);
    const leave = () => {
      if (joined) void rest(membership(), { method: 'DELETE' }).catch(() => {});
    };
    const disconnect = () => {
      stopMicrophone(); comm.current?.close(); comm.current = null;
      setConnections(0); setAudioBlocked(false);
    };
    const poll = async () => {
      if (busy || canceled || ended || document.hidden) return;
      busy = true;
      try {
        const data = await rest<LiveRoomRecord[]>('rooms?id=eq.' + id + '&limit=1');
        if (canceled) return;
        const activeRoom = data[0];
        if (!activeRoom || activeRoom.closed) {
          ended = true; disconnect(); leave(); joined = ''; joinTime.current = ''; setStatus('ended'); setRoom(null); setMembers([]); return;
        }
        owner.current = me === activeRoom.host_id;
        setRoom(activeRoom);
        if (!joined) {
          const previous = await rest<Member[]>('room_members?' + filter + '&user_id=eq.' + me);
          if (canceled || document.hidden) return;
          if (previous[0]) await rest('room_members?' + filter + '&user_id=eq.' + me + '&joined_at=eq.' + time(previous[0].joined_at), { method: 'DELETE' });
          if (canceled || document.hidden) return;
          const rows = await rest<Member[]>('room_members', jsonRequest('POST', {
            room_id: id, user_id: me, seat: owner.current ? 0 : null,
          }));
          if (!rows[0]) throw new Error('Could not join.');
          joined = rows[0].joined_at;
          if (canceled || document.hidden) { leave(); joined = ''; return; }
          joinTime.current = joined; lastBeat = Date.now(); cursor = 0;
        }
        if (Date.now() - lastBeat >= 9000) {
          const rows = await rest<Member[]>(membership(), jsonRequest('PATCH', { last_seen: new Date().toISOString() }));
          if (!rows.length) { joined = ''; joinTime.current = ''; throw new Error('Membership expired.'); }
          lastBeat = Date.now();
        }
        const fresh = time(new Date(Date.now() - 60000).toISOString());
        const [present, chat, signals] = await Promise.all([
          rest<Member[]>('room_members?' + filter + '&last_seen=gte.' + fresh + '&order=joined_at.asc'),
          rest<RoomMessage[]>('room_messages?' + filter + '&order=created_at.desc&limit=45'),
          rest<Signal[]>('room_signals?' + filter + '&recipient_id=eq.' + me + '&id=gt.' + cursor + '&created_at=gte.' + time(joined) + '&order=id.asc&limit=100'),
        ]);
        if (canceled || document.hidden) return;
        const own = present.find(m => m.user_id === me && m.joined_at === joined);
        if (!own) { joined = ''; joinTime.current = ''; throw new Error('Membership expired.'); }
        if (track.current && own.seat === null) stopMicrophone();
        if (!comm.current) comm.current = new RoomAudio({ room: id, me, session: joined, update: (count, blocked) => {
          if (!canceled) { setConnections(count); setAudioBlocked(blocked); }
        } });
        lastConfirmed = Date.now(); setMembers(present); setMessages(chat.reverse()); setStatus('active');
        const ids = Array.from(new Set([activeRoom.host_id, ...present.map(m => m.user_id), ...chat.map(m => m.owner_id)]));
        const refreshAll = Date.now() >= nextProfileRefresh;
        const missing = refreshAll ? ids : ids.filter(value => !(value in rosterNames));
        if (missing.length && !loadingProfiles) {
          loadingProfiles = true;
          if (refreshAll) nextProfileRefresh = Date.now() + 8 * 60 * 1000;
          void (async () => {
            const people = await rest<{id: string; name: string; avatar_path: string}[]>('profiles?select=id,name,avatar_path&id=in.(' + missing.join(',') + ')');
            if (canceled) return;
            rosterNames = { ...rosterNames, ...Object.fromEntries(missing.map(id => [id, 'Listener'])), ...Object.fromEntries(people.map(p => [p.id, p.name])) };
            setNames(rosterNames);
            const pictures = await Promise.all(people.map(async p => [p.id, p.avatar_path ? await mediaUrl(p.avatar_path).catch(() => '') : '']));
            if (!canceled) { rosterPortraits = { ...rosterPortraits, ...Object.fromEntries(pictures) }; setPortraits(rosterPortraits); }
          })().catch(() => {}).finally(() => { loadingProfiles = false; });
        }
        await comm.current.refresh(present, signals).catch(() => {
          if (!canceled) setNotice('A voice connection was interrupted. Audio will retry.');
        });
        if (signals.length) cursor = signals[signals.length - 1].id;
      } catch {
        if (!canceled && !ended) { disconnect(); setMembers([]); setStatus('retry'); }
      } finally {
        busy = false;
        if (!canceled && !ended) { window.clearTimeout(timer); timer = window.setTimeout(poll, 2200); }
      }
    };
    const wake = () => {
      if (document.hidden) { disconnect(); leave(); joined = ''; joinTime.current = ''; setStatus('joining'); }
      else void poll();
    };
    retryNow.current = () => { window.clearTimeout(timer); void poll(); };
    const watchdog = window.setInterval(() => {
      if (!document.hidden && !ended && lastConfirmed && Date.now() - lastConfirmed > 30000) {
        lastConfirmed = 0; disconnect(); setMembers([]); setStatus('retry');
      }
    }, 3000);
    document.addEventListener('visibilitychange', wake);
    void poll();
    return () => {
      canceled = true; retryNow.current = () => {}; window.clearTimeout(timer); window.clearInterval(watchdog);
      document.removeEventListener('visibilitychange', wake);
      disconnect(); leave(); joinTime.current = '';
    };
  }, [id]);
  async function speak(seat: number) {
    if (status !== 'active' || !joinTime.current) throw new Error('Reconnect before taking a seat.');
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia || !window.RTCPeerConnection)
      throw new Error('This device cannot open the microphone here. Check microphone access and try again.');
    const token = ++acquire.current;
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true }, video: false });
    const fresh = stream.getAudioTracks()[0];
    if (!fresh) throw new Error('No microphone track is available.');
    fresh.enabled = false;
    try {
      if (token !== acquire.current || !joinTime.current || document.hidden) throw new Error('Microphone access was interrupted.');
      const rows = await rest<Member[]>(seatPath(), jsonRequest('PATCH', { seat }));
      if (!rows.length || rows[0].seat !== seat) throw new Error('This seat is no longer available.');
      if (token !== acquire.current || document.hidden) throw new Error('Microphone access was interrupted.');
      track.current = fresh; fresh.enabled = true;
      fresh.onended = () => { void releaseSeat().catch(() => {}); setNotice('Microphone interrupted. Tap a seat to speak again.'); };
      if (!comm.current) throw new Error('Voice is still connecting. Please try again.');
      await comm.current.setMic(fresh);
      setMic('on'); setMembers(old => old.map(m => m.user_id === userId() ? rows[0] : m)); setNotice('');
    } catch (error) {
      fresh.stop();
      if (track.current === fresh) await releaseSeat().catch(() => {});
      throw error;
    }
  }
  function mute() {
    const local = track.current;
    if (local?.readyState === 'live') { local.enabled = !local.enabled; setMic(local.enabled ? 'on' : 'muted'); }
  }
  return { room, members, messages, names, portraits, status, connections, audioBlocked, mic, notice,
    speak, mute, releaseSeat, hear: () => comm.current?.hear(), refresh: () => retryNow.current() };
}
