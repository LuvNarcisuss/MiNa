-- An attested production app may authorize a device-funded share of one specific gift.
-- App Store receipts and purchase credits stay on the iPhone.
create table public.device_gift_keys (
    owner_id uuid not null references public.profiles on delete cascade,
    key_id text not null, challenge uuid not null default gen_random_uuid(),
    expires_at timestamptz not null default now() + interval '5 minutes',
    public_key text, sign_count bigint not null default 0,
    primary key (owner_id, key_id)
);
create table public.device_gift_operations (
    owner_id uuid not null references public.profiles on delete cascade, id uuid not null,
    request jsonb, quoted_total bigint, device_coins bigint, device_items integer, canceled boolean not null,
    primary key (owner_id, id),
    check (canceled or (request is not null and quoted_total is not null and device_coins is not null
                        and device_items is not null and device_items between 0 and 99
                        and device_coins between 0 and quoted_total and (device_coins>0 or device_items>0)))
);
alter table public.device_gift_keys enable row level security;
alter table public.device_gift_operations enable row level security;
revoke all on public.device_gift_keys, public.device_gift_operations from public, anon, authenticated;
grant select, insert, update on public.device_gift_keys to service_role;

create function public.authorize_device_gift(p_owner uuid, p_key text, p_counter bigint, p_operation uuid,
    p_request jsonb, p_total bigint, p_coins bigint, p_items integer)
returns void language plpgsql security invoker set search_path='' as $$
begin
    perform 1 from public.wallets where owner_id=p_owner for update;
    if not found then raise exception 'Wallet unavailable.'; end if;
    update public.device_gift_keys set sign_count=p_counter where owner_id=p_owner and key_id=p_key
        and public_key is not null and sign_count<p_counter;
    if not found then raise exception 'Request a fresh gift authorization.'; end if;
    insert into public.device_gift_operations(owner_id,id,request,quoted_total,device_coins,device_items,canceled)
        values (p_owner,p_operation,p_request,p_total,p_coins,p_items,false) on conflict do nothing;
    if not exists (select 1 from public.device_gift_operations where owner_id=p_owner and id=p_operation
                   and not canceled and request=p_request and device_coins=p_coins and device_items=p_items and quoted_total=p_total)
        then raise exception 'This gift operation has closed.'; end if;
end $$;
grant select,insert on public.device_gift_operations to service_role;
revoke all on function public.authorize_device_gift(uuid,text,bigint,uuid,jsonb,bigint,bigint,integer) from public,anon,authenticated;
grant execute on function public.authorize_device_gift(uuid,text,bigint,uuid,jsonb,bigint,bigint,integer) to service_role;

-- Serialize cancellation with authorization and delivery. An absent receipt alone cannot release a reservation.
create function mina_private.resolve_device_gift(p_operation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt jsonb;
begin
    perform 1 from public.wallets where owner_id=actor for update;
    if not found or p_operation is null then raise exception 'Wallet unavailable.'; end if;
    select result into receipt from public.wallet_ledger where owner_id=actor and id=p_operation;
    if found then return receipt; end if;
    insert into public.device_gift_operations(owner_id,id,canceled) values(actor,p_operation,true)
        on conflict(owner_id,id) do update set canceled=true;
    return jsonb_build_object('id',p_operation,'canceled',true);
end $$;
create function public.resolve_device_gift(p_operation uuid) returns jsonb language sql security invoker
set search_path='' as $$select mina_private.resolve_device_gift(p_operation)$$;
revoke all on function mina_private.resolve_device_gift(uuid), public.resolve_device_gift(uuid) from public,anon,authenticated;
grant execute on function mina_private.resolve_device_gift(uuid), public.resolve_device_gift(uuid) to authenticated;

create or replace function mina_private.gift_operation(action text,target_room uuid,recipient uuid,item integer,units integer,operation uuid,from_inventory boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); utc_day date:=(now() at time zone 'UTC')::date; price integer; coins bigint; total bigint;
 charged bigint; source text; prior public.wallet_ledger%rowtype; payload jsonb; receipt jsonb; permit public.device_gift_operations%rowtype; device_charge bigint := 0; local_items integer := 0;
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
 select * into permit from public.device_gift_operations where owner_id=actor and id=operation;
 if found then
   if permit.canceled or permit.request is distinct from payload or permit.quoted_total<>total
      or permit.device_coins>total or permit.device_items>units
      or (from_inventory and permit.device_coins<>0) or (not from_inventory and permit.device_items<>0) then raise exception 'This gift authorization is unavailable.'; end if;
   device_charge=permit.device_coins; local_items=permit.device_items;
 end if;
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
   if units>local_items then
     update public.gift_inventory i set quantity=i.quantity-(units-local_items)
       where i.owner_id=actor and i.gift_index=item and i.quantity>=units-local_items;
     if not found then raise exception 'There are not enough of this item in your backpack.'; end if;
   end if;
   charged=0; source='backpack';
 elsif price=0 then
   if units<>1 then raise exception 'Choose one free gift per day.'; end if;
   insert into mina_private.free_gift_claims(owner_id,gift_index,day) values(actor,item,utc_day) on conflict do nothing;
   if not found then raise exception 'Today’s free gift has already been used.'; end if;
   source='free';
 else
   charged=total-device_charge;
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
 receipt=jsonb_build_object('id',operation,'amount',total,'charged',charged,'balance',coins,'quantity',units,'source',source,'device_coins',device_charge,'device_items',local_items);
 insert into public.wallet_ledger(owner_id,id,kind,gift_index,quantity,amount,balance_after,request,result)
 values(actor,operation,action,item,units,charged,coins,payload,receipt);
 return receipt;
end $$;
