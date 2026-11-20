create table public.conversation_state (
  owner_id uuid not null references public.profiles on delete cascade,
  peer_id uuid not null references public.profiles on delete cascade,
  read_at timestamptz not null default '-infinity', read_id uuid not null default '00000000-0000-0000-0000-000000000000',
  cleared_at timestamptz not null default '-infinity', cleared_id uuid not null default '00000000-0000-0000-0000-000000000000',
  primary key(owner_id,peer_id), check (owner_id<>peer_id)
);
create table public.account_notices (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles on delete cascade,
  kind text not null check(kind in ('platform','follow','ranking')), title text not null, body text not null,
  actor_id uuid references public.profiles on delete set null, created_at timestamptz not null default now(), read_at timestamptz
);
create index account_notices_owner on public.account_notices(owner_id,created_at desc);
create table public.voice_calls (
  id uuid primary key, caller_id uuid not null references public.profiles on delete cascade,
  callee_id uuid not null references public.profiles on delete cascade, check(caller_id<>callee_id),
  state text not null check(state in ('ringing','accepted','declined','busy','missed','ended','disconnected')),
  created_at timestamptz not null default now(), caller_seen timestamptz not null default now(), callee_seen timestamptz not null default now(),
  offer text check(octet_length(offer)<=65536), answer text check(octet_length(answer)<=65536)
);
create index calls_incoming on public.voice_calls(callee_id,state,created_at desc);
create index calls_outgoing on public.voice_calls(caller_id,state,created_at desc);
alter table public.conversation_state enable row level security;
alter table public.account_notices enable row level security;
alter table public.voice_calls enable row level security;
revoke all on public.conversation_state,public.account_notices,public.voice_calls from public,anon,authenticated;
grant select,insert,update on public.conversation_state to authenticated;
grant select on public.account_notices,public.voice_calls to authenticated;
grant update(read_at) on public.account_notices to authenticated;
create policy conversation_owner on public.conversation_state for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy notice_owner on public.account_notices for select to authenticated using(owner_id=(select auth.uid()) and (actor_id is null or mina_private.can_interact(actor_id)));
create policy notice_read on public.account_notices for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy call_member on public.voice_calls for select to authenticated using((select auth.uid()) in (caller_id,callee_id) and mina_private.can_interact(caller_id) and mina_private.can_interact(callee_id));

create function mina_private.message_clock() returns trigger language plpgsql set search_path='' as $$
begin new.created_at=clock_timestamp(); return new; end $$;
create trigger message_clock before insert on public.messages for each row execute function mina_private.message_clock();
create function mina_private.follow_notice() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.account_notices(owner_id,kind,actor_id,title,body)
values(new.followed_id,'follow',new.follower_id,'New follower','Started following you.'); return new; end $$;
create trigger notify_follow after insert on public.follows for each row execute function mina_private.follow_notice();

create function public.send_message(p_id uuid,p_peer uuid,p_body text) returns uuid language plpgsql security invoker set search_path='' as $$
declare saved public.messages;
begin
  insert into public.messages(id,sender_id,recipient_id,body) values(p_id,auth.uid(),p_peer,p_body) on conflict do nothing;
  select * into saved from public.messages where id=p_id;
  if saved.id is null or saved.sender_id<>auth.uid() or saved.recipient_id<>p_peer or saved.body<>p_body then
    raise exception 'This message could not be confirmed.'; end if;
  return saved.id;
end $$;
create function public.inbox_summary() returns table(peer_id uuid,latest_id uuid,body text,created_at timestamptz,unread bigint)
language sql stable security invoker set search_path='' as $$
 with m as (select m.*,case when sender_id=auth.uid() then recipient_id else sender_id end as peer
    from public.messages m where auth.uid() in (sender_id,recipient_id)),
 visible as (select m.*, count(*) filter(where m.sender_id=m.peer and
    (s.read_at is null or (m.created_at,m.id)>(s.read_at,s.read_id))) over(partition by m.peer) as n
    from m left join public.conversation_state s on s.owner_id=auth.uid() and s.peer_id=m.peer
    where s.cleared_at is null or (m.created_at,m.id)>(s.cleared_at,s.cleared_id)),
 newest as (select distinct on(peer) peer,id,body,created_at,n from visible order by peer,created_at desc,id desc)
 select peer,id,body,created_at,n from newest order by created_at desc,id desc
$$;
create function public.mark_conversation(p_peer uuid,p_latest uuid,p_clear boolean default false) returns void
language plpgsql security invoker set search_path='' as $$
declare m public.messages;
begin
 select * into m from public.messages where id=p_latest and ((sender_id=auth.uid() and recipient_id=p_peer) or (sender_id=p_peer and recipient_id=auth.uid()));
 if m.id is null then return; end if;
 insert into public.conversation_state(owner_id,peer_id) values(auth.uid(),p_peer) on conflict do nothing;
 update public.conversation_state set read_at=m.created_at,read_id=m.id
 where owner_id=auth.uid() and peer_id=p_peer and (read_at,read_id)<(m.created_at,m.id);
 if p_clear then update public.conversation_state set cleared_at=m.created_at,cleared_id=m.id
 where owner_id=auth.uid() and peer_id=p_peer and (cleared_at,cleared_id)<(m.created_at,m.id); end if;
end $$;
create function public.chat_history(p_peer uuid,p_take integer default 50,p_before timestamptz default null,p_id uuid default null)
returns setof public.messages language sql stable security invoker set search_path='' as $$
 select m.* from public.messages m left join public.conversation_state s on s.owner_id=auth.uid() and s.peer_id=p_peer
 where ((m.sender_id=auth.uid() and m.recipient_id=p_peer) or (m.sender_id=p_peer and m.recipient_id=auth.uid()))
 and (s.cleared_at is null or (m.created_at,m.id)>(s.cleared_at,s.cleared_id))
 and (p_before is null or (m.created_at,m.id)<(p_before,p_id))
 order by m.created_at desc,m.id desc limit greatest(1,least(p_take,100))
$$;
create function mina_private.start_voice_call(p_id uuid,p_peer uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid=auth.uid(); existing public.voice_calls; status text='ringing';
begin
 if me is null or me=p_peer or not mina_private.can_interact(p_peer) or not exists
   (select 1 from public.profiles where id=p_peer and allow_calls and not private_profile) then raise exception 'Calls are unavailable for this person.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(p_peer,me)::text,17));
 perform pg_advisory_xact_lock(hashtextextended(greatest(p_peer,me)::text,17));
 select * into existing from public.voice_calls where id=p_id;
 if existing.id is not null then
   if existing.caller_id<>me or existing.callee_id<>p_peer then raise exception 'Invalid call request.'; end if; return existing.id;
 end if;
 update public.voice_calls set state=case state when 'ringing' then 'missed' else 'disconnected' end,offer=null,answer=null
 where (caller_id in(me,p_peer) or callee_id in(me,p_peer)) and
 ((state='ringing' and created_at<now()-interval '45 seconds') or (state='accepted' and least(caller_seen,callee_seen)<now()-interval '40 seconds'));
 if exists(select 1 from public.voice_calls where me in(caller_id,callee_id) and state in('ringing','accepted')) then
   raise exception 'End your current call first.'; end if;
 if exists(select 1 from public.voice_calls where p_peer in(caller_id,callee_id) and state in('ringing','accepted')) then status='busy'; end if;
 insert into public.voice_calls(id,caller_id,callee_id,state) values(p_id,me,p_peer,status); return p_id;
end $$;
create function public.start_voice_call(p_id uuid,p_peer uuid) returns uuid language sql security invoker set search_path='' as $$
 select mina_private.start_voice_call(p_id,p_peer)
$$;
create function mina_private.voice_action(p_id uuid,p_action text,p_sdp text default null) returns text
language plpgsql security definer set search_path='' as $$
declare c public.voice_calls; me uuid=auth.uid(); next_state text;
begin
 select * into c from public.voice_calls where id=p_id and me in(caller_id,callee_id) for update;
 if c.id is null then raise exception 'Call unavailable.'; end if;
 if c.state not in('ringing','accepted') then return c.state; end if;
 next_state=c.state;
 if not mina_private.can_interact(c.caller_id) or not mina_private.can_interact(c.callee_id) then next_state='ended';
 elsif c.state='ringing' and c.created_at<now()-interval '45 seconds' then next_state='missed';
 elsif c.state='accepted' and least(c.caller_seen,c.callee_seen)<now()-interval '40 seconds' then next_state='disconnected';
 elsif p_action='accept' and me=c.callee_id and c.state='ringing' then
   if not exists(select 1 from public.profiles where id=me and allow_calls and not private_profile) then raise exception 'Enable voice calls in Privacy first.'; end if;
   next_state='accepted';
 elsif p_action='decline' and me=c.callee_id and c.state='ringing' then next_state='declined';
 elsif p_action='end' then next_state='ended';
 elsif p_action='disconnect' then next_state='disconnected';
 elsif p_action='offer' and c.state='accepted' and me=c.caller_id and p_sdp is not null then
   if c.offer is not null and c.offer<>p_sdp then raise exception 'Call offer changed.'; end if;
   update public.voice_calls set offer=p_sdp where id=p_id;
 elsif p_action='answer' and c.state='accepted' and me=c.callee_id and c.offer is not null and p_sdp is not null then
   if c.answer is not null and c.answer<>p_sdp then raise exception 'Call answer changed.'; end if;
   update public.voice_calls set answer=p_sdp where id=p_id;
 elsif p_action<>'heartbeat' then raise exception 'Call state changed.'; end if;
 update public.voice_calls set state=next_state,caller_seen=case when me=c.caller_id or c.state<>next_state then now() else caller_seen end,
   callee_seen=case when me=c.callee_id or c.state<>next_state then now() else callee_seen end,
   offer=case when next_state in('accepted','ringing') then offer else null end,
   answer=case when next_state in('accepted','ringing') then answer else null end where id=p_id;
 return next_state;
end $$;
create function public.voice_action(p_id uuid,p_action text,p_sdp text default null) returns text language sql security invoker set search_path='' as $$
 select mina_private.voice_action(p_id,p_action,p_sdp)
$$;
revoke all on function mina_private.message_clock(),mina_private.follow_notice(),mina_private.start_voice_call(uuid,uuid),mina_private.voice_action(uuid,text,text),
 public.start_voice_call(uuid,uuid),public.voice_action(uuid,text,text),public.send_message(uuid,uuid,text),public.inbox_summary(),public.mark_conversation(uuid,uuid,boolean),public.chat_history(uuid,integer,timestamptz,uuid) from public,anon,authenticated;
grant execute on function mina_private.start_voice_call(uuid,uuid),mina_private.voice_action(uuid,text,text),
 public.start_voice_call(uuid,uuid),public.voice_action(uuid,text,text),public.send_message(uuid,uuid,text),public.inbox_summary(),public.mark_conversation(uuid,uuid,boolean),public.chat_history(uuid,integer,timestamptz,uuid) to authenticated;
