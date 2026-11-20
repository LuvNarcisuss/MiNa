alter table public.rooms add column music_track text check(music_track in ('moon-seat','star-pillow','moonlit-sea')),
  add column music_started_at timestamptz;
grant update(music_track,music_started_at) on public.rooms to authenticated;

create table public.room_seat_requests (
  room_id uuid not null, user_id uuid not null default auth.uid(), seat integer not null check(seat between 1 and 8),
  created_at timestamptz not null default now(), primary key(room_id,user_id),
  foreign key(room_id,user_id) references public.room_members(room_id,user_id) on delete cascade
);
create table public.room_checkins (
  room_id uuid references public.rooms on delete cascade, user_id uuid references public.profiles on delete cascade,
  day date not null, primary key(room_id,user_id,day)
);
create table public.gift_catalog (
  gift_index integer primary key check(gift_index between 0 and 19), unit_price integer not null check(unit_price>=0)
);
insert into public.gift_catalog(gift_index,unit_price) select ordinal-1,price from
unnest(array[0,0,29,39,49,59,69,79,49,59,69,79,49,59,69,79,49,59,69,69]) with ordinality as prices(price,ordinal);
create table public.wallets (
  owner_id uuid primary key references public.profiles on delete cascade, balance bigint not null default 0 check(balance>=0)
);
create table public.gift_inventory (
  owner_id uuid references public.profiles on delete cascade, gift_index integer references public.gift_catalog,
  quantity integer not null check(quantity>=0),primary key(owner_id,gift_index)
);
create table public.wallet_ledger (
  owner_id uuid references public.profiles on delete cascade, id uuid not null, kind text not null check(kind in('acquire','send')),
  gift_index integer not null references public.gift_catalog, quantity integer not null check(quantity between 1 and 99),
  amount bigint not null check(amount>=0), balance_after bigint not null check(balance_after>=0),
  created_at timestamptz not null default now(), request jsonb not null, result jsonb not null, primary key(owner_id,id)
);
create table public.gift_receipts (
  sender_id uuid not null references public.profiles on delete cascade, id uuid not null,
  recipient_id uuid not null references public.profiles on delete cascade,room_id uuid not null references public.rooms on delete cascade,
  gift_index integer not null references public.gift_catalog,quantity integer not null check(quantity between 1 and 99),
  amount bigint not null check(amount>=0),created_at timestamptz not null default now(),
  primary key(sender_id,id),check(sender_id<>recipient_id)
);
create table mina_private.free_gift_claims (
  owner_id uuid references public.profiles on delete cascade, gift_index integer references public.gift_catalog,
  day date not null, primary key(owner_id,gift_index,day)
);
alter table mina_private.free_gift_claims enable row level security;
revoke all on mina_private.free_gift_claims from public,anon,authenticated;

create index room_queue_order on public.room_seat_requests(room_id,created_at);
create index checkins_by_day on public.room_checkins(day,room_id);
create index checkins_owner on public.room_checkins(user_id,day);
create index gift_receipts_period on public.gift_receipts(created_at,room_id) where amount>0;
create index gift_receipts_recipient on public.gift_receipts(recipient_id,created_at);
create index gift_receipts_room on public.gift_receipts(room_id,created_at);
create index wallet_history on public.wallet_ledger(owner_id,created_at desc);
create index inventory_by_item on public.gift_inventory(gift_index);
create index ledger_by_item on public.wallet_ledger(gift_index);
create index receipts_by_item on public.gift_receipts(gift_index);
create index free_claims_by_item on mina_private.free_gift_claims(gift_index);
create index room_members_freshness on public.room_members(room_id,last_seen);

do $$
declare t text;
begin
 foreach t in array array['room_seat_requests','room_checkins','gift_catalog','wallets','gift_inventory','wallet_ledger','gift_receipts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
grant insert(room_id,user_id,seat), delete on public.room_seat_requests to authenticated;
create policy browse_items on public.gift_catalog for select to authenticated using(true);
create policy own_wallet on public.wallets for select to authenticated using(owner_id=(select auth.uid()));
create policy own_inventory on public.gift_inventory for select to authenticated using(owner_id=(select auth.uid()));
create policy own_ledger on public.wallet_ledger for select to authenticated using(owner_id=(select auth.uid()));
create policy view_gift on public.gift_receipts for select to authenticated using(
 (select auth.uid()) in(sender_id,recipient_id) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid()))
);
create policy view_checkin on public.room_checkins for select to authenticated using(
 user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid()))
);
create or replace function mina_private.member_active(r uuid,u uuid) returns boolean language sql stable security invoker set search_path=''
as $$select exists(select 1 from public.room_members m where m.room_id=r and m.user_id=u and m.last_seen>now()-interval '60 seconds')$$;
create policy queue_read on public.room_seat_requests for select to authenticated using(
 mina_private.room_open(room_id) and mina_private.member_active(room_id,(select auth.uid())) and mina_private.member_active(room_id,user_id)
);
create policy queue_join on public.room_seat_requests for insert to authenticated with check(
 user_id=(select auth.uid()) and mina_private.room_open(room_id) and exists(select 1 from public.room_members m
 where m.room_id=room_seat_requests.room_id and m.user_id=(select auth.uid()) and m.seat is null and m.last_seen>now()-interval '60 seconds')
);
create policy queue_remove on public.room_seat_requests for delete to authenticated using(
 user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid()))
);

create or replace function mina_private.guard_seat() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid := auth.uid(); host uuid;
begin
 select r.host_id into host from public.rooms r where r.id=new.room_id and not r.closed;
 if actor is null or host is null then raise exception 'This room is unavailable.'; end if;
 if tg_op='INSERT' then
   if new.user_id<>actor or (new.seat is not null and (actor<>host or new.seat<>0)) then raise exception 'Join as a listener first.'; end if;
   new.last_seen=now(); new.joined_at=now();
 else
   if old.last_seen<=now()-interval '60 seconds' then
     delete from public.room_seat_requests q where q.room_id=new.room_id and q.user_id=new.user_id;
   end if;
   if old.last_seen<=now()-interval '60 seconds' and new.user_id<>host and new.seat is not null then
     if new.seat is distinct from old.seat then raise exception 'This listener must rejoin the room.'; end if;
     new.seat=null;
   end if;
   if old.seat is distinct from new.seat and new.seat is not null then
     if actor<>host or not mina_private.can_interact(new.user_id) or not mina_private.member_active(new.room_id,actor)
     then raise exception 'The active host admits speakers.'; end if;
     if new.user_id<>host then
       delete from public.room_seat_requests q where q.room_id=new.room_id and q.user_id=new.user_id and q.seat=new.seat;
       if not found then raise exception 'Ask the listener to request this seat.'; end if;
     end if;
   end if;
   if actor=new.user_id then new.last_seen=now(); else new.last_seen=old.last_seen; end if;
 end if;
 if new.seat is not null then
   delete from public.room_members m where m.room_id=new.room_id and m.user_id<>new.user_id and m.seat=new.seat
     and m.last_seen<=now()-interval '60 seconds';
 end if;
 return new;
end $$;
create trigger guard_room_join before insert on public.room_members for each row execute function mina_private.guard_seat();

create function mina_private.initialize_wallet() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.wallets(owner_id) values(new.id) on conflict do nothing; return new; end $$;
create trigger initialize_wallet after insert on public.profiles for each row execute function mina_private.initialize_wallet();
insert into public.wallets(owner_id) select id from public.profiles on conflict do nothing;

create function mina_private.visible_room(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rooms r where r.id=target and auth.uid() is not null
 and (r.host_id=auth.uid() or (mina_private.can_interact(r.host_id) and (r.visibility='public' or (r.visibility='followers'
 and exists(select 1 from public.follows f where f.followed_id=r.host_id and f.follower_id=auth.uid()))))))
$$;
create function mina_private.check_in(target_room uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); utc_day date:=(now() at time zone 'UTC')::date; first_check boolean;
begin
 if actor is null or not mina_private.visible_room(target_room) then raise exception 'Join this room before checking in.'; end if;
 perform 1 from public.rooms where id=target_room and not closed for share;
 if not found then raise exception 'This room has ended.'; end if;
 perform 1 from public.room_members where room_id=target_room and user_id=actor and last_seen>now()-interval '60 seconds' for share;
 if not found then raise exception 'Join this room before checking in.'; end if;
 insert into public.room_checkins(room_id,user_id,day) values(target_room,actor,utc_day) on conflict do nothing;
 first_check=found;
 return jsonb_build_object('day',utc_day,'first',first_check);
end $$;
create function public.check_in(target_room uuid) returns jsonb language sql security invoker set search_path=''
as $$select mina_private.check_in(target_room)$$;

create function mina_private.gift_operation(action text,target_room uuid,recipient uuid,item integer,units integer,operation uuid,from_inventory boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); utc_day date:=(now() at time zone 'UTC')::date; price integer; coins bigint; total bigint;
 charged bigint; source text; prior public.wallet_ledger%rowtype; payload jsonb; receipt jsonb;
begin
 if actor is null or operation is null or action is null or action not in('send','acquire')
    or item is null or units is null or units not between 1 and 99 or from_inventory is null then raise exception 'Invalid gift request.'; end if;
 payload=jsonb_build_array(action,target_room,recipient,item,units,from_inventory);
 select w.balance into coins from public.wallets w where w.owner_id=actor for update;
 if not found then raise exception 'Open your profile before using the store.'; end if;
 select * into prior from public.wallet_ledger l where l.owner_id=actor and l.id=operation;
 if found then
   if prior.request<>payload then raise exception 'This operation belongs to a different gift.'; end if;
   return prior.result;
 end if;
 select c.unit_price into strict price from public.gift_catalog c where c.gift_index=item;
 total=price::bigint*units; charged=total;
 if action='send' then
   if recipient is null or recipient=actor or not mina_private.visible_room(target_room) or not mina_private.can_interact(recipient)
   then raise exception 'Choose an eligible listener.'; end if;
   perform 1 from public.rooms r where r.id=target_room and r.allow_gifts and not r.closed for share;
   if not found then raise exception 'Gifts are unavailable in this room.'; end if;
   perform 1 from public.room_members m where m.room_id=target_room and m.user_id=actor and m.last_seen>now()-interval '60 seconds' for share;
   if not found then raise exception 'Join the room before sending gifts.'; end if;
   perform 1 from public.room_members m where m.room_id=target_room and m.user_id=recipient and m.last_seen>now()-interval '60 seconds' for share;
   if not found then raise exception 'This listener has left the room.'; end if;
 elsif target_room is not null or recipient is not null or from_inventory then raise exception 'Invalid store request.';
 end if;
 if from_inventory then
   update public.gift_inventory i set quantity=i.quantity-units where i.owner_id=actor and i.gift_index=item and i.quantity>=units;
   if not found then raise exception 'There are not enough of this item in your backpack.'; end if;
   charged=0; source='backpack';
 elsif price=0 then
   if units<>1 then raise exception 'Choose one free gift per day.'; end if;
   insert into mina_private.free_gift_claims(owner_id,gift_index,day) values(actor,item,utc_day) on conflict do nothing;
   if not found then raise exception 'Today’s free gift has already been used.'; end if;
   source='free';
 else
   if coins<charged then raise exception 'Insufficient star coins.'; end if;
   update public.wallets set balance=balance-charged where owner_id=actor returning balance into coins;
   source='wallet';
 end if;
 if action='acquire' then
   insert into public.gift_inventory(owner_id,gift_index,quantity) values(actor,item,units)
    on conflict(owner_id,gift_index) do update set quantity=public.gift_inventory.quantity+excluded.quantity;
 else
   insert into public.gift_receipts(sender_id,id,recipient_id,room_id,gift_index,quantity,amount)
     values(actor,operation,recipient,target_room,item,units,total);
 end if;
 receipt=jsonb_build_object('id',operation,'amount',total,'charged',charged,'balance',coins,'quantity',units,'source',source);
 insert into public.wallet_ledger(owner_id,id,kind,gift_index,quantity,amount,balance_after,request,result)
 values(actor,operation,action,item,units,charged,coins,payload,receipt);
 return receipt;
end $$;
create function public.acquire_gift(gift_index integer,quantity integer,operation uuid) returns jsonb language sql security invoker set search_path=''
as $$select mina_private.gift_operation('acquire',null,null,gift_index,quantity,operation,false)$$;
create function public.send_gift(target_room uuid,recipient uuid,gift_index integer,quantity integer,operation uuid,use_inventory boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
 select mina_private.gift_operation('send',target_room,recipient,gift_index,quantity,operation,use_inventory)
$$;
create function mina_private.room_rankings(start_day date,gift_ranking boolean) returns table(room_id uuid,score bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or start_day is null or gift_ranking is null then raise exception 'Sign in to view rankings.'; end if;
 if gift_ranking then
   return query select g.room_id,sum(g.amount)::bigint from public.gift_receipts g
    where g.created_at >= (start_day::timestamp at time zone 'UTC') and g.created_at < ((start_day+7)::timestamp at time zone 'UTC')
      and g.amount>0 and mina_private.visible_room(g.room_id) and mina_private.can_interact(g.recipient_id) and mina_private.can_interact(g.sender_id)
    group by g.room_id order by 2 desc,1 limit 100;
 else
   return query select c.room_id,count(*) from public.room_checkins c
    where c.day>=start_day and c.day<start_day+7 and mina_private.visible_room(c.room_id) and mina_private.can_interact(c.user_id)
    group by c.room_id order by 2 desc,1 limit 100;
 end if;
end $$;
create function public.room_rankings(start_day date,gift_ranking boolean) returns table(room_id uuid,score bigint)
language sql stable security invoker set search_path='' as $$select * from mina_private.room_rankings(start_day,gift_ranking)$$;

revoke all on function mina_private.guard_seat(),mina_private.initialize_wallet(),mina_private.visible_room(uuid) from public,anon,authenticated;
revoke all on function mina_private.check_in(uuid),mina_private.gift_operation(text,uuid,uuid,integer,integer,uuid,boolean),mina_private.room_rankings(date,boolean),
 public.check_in(uuid),public.acquire_gift(integer,integer,uuid),public.send_gift(uuid,uuid,integer,integer,uuid,boolean),public.room_rankings(date,boolean)
 from public,anon,authenticated;
grant execute on function mina_private.check_in(uuid),mina_private.gift_operation(text,uuid,uuid,integer,integer,uuid,boolean),mina_private.room_rankings(date,boolean),
 public.check_in(uuid),public.acquire_gift(integer,integer,uuid),public.send_gift(uuid,uuid,integer,integer,uuid,boolean),public.room_rankings(date,boolean)
 to authenticated;
