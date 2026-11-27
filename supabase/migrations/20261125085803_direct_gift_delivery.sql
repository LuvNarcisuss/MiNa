-- Keep device balances on the phone. The room service records delivery for authenticated participants.
create table mina_private.canceled_gifts (
    owner_id uuid not null references public.profiles on delete cascade,
    id uuid not null,
    primary key (owner_id,id)
);
alter table mina_private.canceled_gifts enable row level security;
revoke all on mina_private.canceled_gifts from public,anon,authenticated;

create or replace function mina_private.resolve_device_gift(p_operation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt jsonb;
begin
    perform 1 from public.wallets where owner_id=actor for update;
    if not found or p_operation is null then raise exception 'Wallet unavailable.'; end if;
    select result into receipt from public.wallet_ledger where owner_id=actor and id=p_operation;
    if found then return receipt; end if;
    insert into mina_private.canceled_gifts(owner_id,id) values(actor,p_operation) on conflict do nothing;
    return jsonb_build_object('id',p_operation,'canceled',true);
end $$;
create or replace function public.resolve_device_gift(p_operation uuid) returns jsonb language sql security invoker
set search_path='' as $$select mina_private.resolve_device_gift(p_operation)$$;
revoke all on function mina_private.resolve_device_gift(uuid), public.resolve_device_gift(uuid) from public,anon,authenticated;
grant execute on function mina_private.resolve_device_gift(uuid), public.resolve_device_gift(uuid) to authenticated;

create function mina_private.deliver_wallet_gift(action text,target_room uuid,recipient uuid,item integer,units integer,
 operation uuid,from_inventory boolean,quoted_price integer,device_charge bigint,local_items integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); utc_day date:=(now() at time zone 'UTC')::date; price integer; coins bigint; total bigint;
 charged bigint; source text; prior public.wallet_ledger%rowtype; payload jsonb; receipt jsonb;
begin
 if actor is null or operation is null or action is null or action not in('send','acquire')
    or device_charge is null or device_charge<0 or local_items is null or local_items not between 0 and units
    or (from_inventory and device_charge<>0) or (not from_inventory and local_items<>0)
    or item is null or units is null or units not between 1 and 99 or from_inventory is null then raise exception 'Invalid gift request.'; end if;
 payload=jsonb_build_array(action,target_room,recipient,item,units,from_inventory);
 select w.balance into coins from public.wallets w where w.owner_id=actor for update;
 if not found then raise exception 'Open your profile before using the store.'; end if;
 select * into prior from public.wallet_ledger l where l.owner_id=actor and l.id=operation;
 if found then
   if prior.request<>payload or coalesce((prior.result->>'device_coins')::bigint,0)<>device_charge
      or coalesce((prior.result->>'device_items')::integer,0)<>local_items then raise exception 'This operation belongs to a different gift.'; end if;
   return prior.result;
 end if;
 select c.unit_price into strict price from public.gift_catalog c where c.gift_index=item;
 total=price::bigint*units; charged=total;
 if exists(select 1 from mina_private.canceled_gifts c where c.owner_id=actor and c.id=operation) then
   raise exception 'This gift was canceled.';
 end if;
 if (quoted_price is not null and quoted_price<>price) or device_charge>total then
   raise exception 'Review the current gift price.';
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
 if action='send' then
   -- Public rankings count only the portion backed by server funds or inventory.
   insert into public.gift_receipts(sender_id,id,recipient_id,room_id,gift_index,quantity,amount)
     values(actor,operation,recipient,target_room,item,units,
       case when from_inventory then (units-local_items)::bigint*price else charged end);
 elsif device_charge=0 then
   insert into public.gift_inventory(owner_id,gift_index,quantity) values(actor,item,units)
     on conflict(owner_id,gift_index) do update set quantity=public.gift_inventory.quantity+excluded.quantity;
 end if;
 receipt=jsonb_build_object('id',operation,'amount',total,'charged',charged,'balance',coins,'quantity',units,'source',source,'device_coins',device_charge,'device_items',local_items);
 insert into public.wallet_ledger(owner_id,id,kind,gift_index,quantity,amount,balance_after,request,result)
 values(actor,operation,action,item,units,charged,coins,payload,receipt);
 return receipt;
end $$;

-- Earlier clients use the same operation lock and retain their original gift RPCs.
create or replace function mina_private.gift_operation(action text,target_room uuid,recipient uuid,item integer,
 units integer,operation uuid,from_inventory boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select mina_private.deliver_wallet_gift(action,target_room,recipient,item,units,operation,from_inventory,null,0,0)
$$;

create function public.deliver_wallet_gift(target_room uuid,recipient uuid,gift_index integer,quantity integer,
 operation uuid,use_inventory boolean,unit_price integer,device_coins bigint,device_items integer)
returns jsonb language sql security invoker set search_path='' as $$
 select mina_private.deliver_wallet_gift(case when target_room is null then 'acquire' else 'send' end,
   target_room,recipient,gift_index,quantity,operation,use_inventory,unit_price,device_coins,device_items)
$$;

revoke all on function mina_private.deliver_wallet_gift(text,uuid,uuid,integer,integer,uuid,boolean,integer,bigint,integer),
 public.deliver_wallet_gift(uuid,uuid,integer,integer,uuid,boolean,integer,bigint,integer) from public,anon,authenticated;
grant execute on function mina_private.deliver_wallet_gift(text,uuid,uuid,integer,integer,uuid,boolean,integer,bigint,integer),
 public.deliver_wallet_gift(uuid,uuid,integer,integer,uuid,boolean,integer,bigint,integer) to authenticated;
notify pgrst,'reload schema';
