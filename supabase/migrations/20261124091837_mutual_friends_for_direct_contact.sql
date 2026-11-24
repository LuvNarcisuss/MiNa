create function public.is_chat_friend(p_peer uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
    select p_peer <> auth.uid() and mina_private.can_interact(p_peer) and exists (
        select 1 from public.follows outgoing
        join public.follows incoming on incoming.follower_id = outgoing.followed_id
                                    and incoming.followed_id = outgoing.follower_id
        where outgoing.follower_id = auth.uid() and outgoing.followed_id = p_peer
    )
$$;
revoke all on function public.is_chat_friend(uuid) from public, anon;
grant execute on function public.is_chat_friend(uuid) to authenticated;

create policy dm_friends_only on public.messages as restrictive for insert to authenticated
with check (public.is_chat_friend(recipient_id));

create or replace function mina_private.start_voice_call(p_id uuid,p_peer uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid=auth.uid(); existing public.voice_calls; status text='ringing';
begin
 if me is null or me=p_peer or not public.is_chat_friend(p_peer) or not exists
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

create or replace function mina_private.voice_action(p_id uuid,p_action text,p_sdp text default null) returns text
language plpgsql security definer set search_path='' as $$
declare c public.voice_calls; me uuid=auth.uid(); next_state text;
begin
 select * into c from public.voice_calls where id=p_id and me in(caller_id,callee_id) for update;
 if c.id is null then raise exception 'Call unavailable.'; end if;
 if c.state not in('ringing','accepted') then return c.state; end if;
 next_state=c.state;
 if not public.is_chat_friend(case when me=c.caller_id then c.callee_id else c.caller_id end) then next_state='ended';
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
