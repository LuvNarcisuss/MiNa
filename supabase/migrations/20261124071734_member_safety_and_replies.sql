alter table public.entry_comments add column parent_id uuid;
alter table public.entry_comments add constraint comment_thread_key unique(entry_id,id);
alter table public.entry_comments add constraint comment_parent_in_entry foreign key(entry_id,parent_id)
  references public.entry_comments(entry_id,id) on delete set null (parent_id);
alter table public.entry_comments add constraint comment_not_own_parent check(parent_id <> id);
create index comment_parent on public.entry_comments(entry_id,parent_id) where parent_id is not null;
create function mina_private.check_reply() returns trigger language plpgsql set search_path='' as $$
begin
  if new.parent_id is not null and not exists(select from public.entry_comments
    where id=new.parent_id and entry_id=new.entry_id) then
    raise exception 'This comment is unavailable.';
  end if;
  return new;
end $$;
create trigger check_reply before insert on public.entry_comments for each row execute function mina_private.check_reply();

alter table public.reports add column withdrawn_at timestamptz, add column target_label text not null default '';
alter table public.blocks add column blocked_name text not null default 'Listener';
create table mina_private.safety_events (
  id bigint generated always as identity primary key, actor_id uuid not null, target_id uuid not null,
  target_kind text not null, action text not null, receipt_id uuid, label text not null,
  occurred_at timestamptz not null default now()
);
revoke all on mina_private.safety_events from public, anon, authenticated;

update public.blocks b set blocked_name=p.name from public.profiles p where b.blocked_id=p.id;
update public.reports r set target_label=coalesce(case
  when target_kind in ('post','dream') then (select left(caption,160) from public.entries where id=r.target_id)
  when target_kind='comment' then (select left(body,160) from public.entry_comments where id=r.target_id)
  when target_kind='profile' then (select name from public.profiles where id=r.target_id)
  when target_kind='room' then (select title from public.rooms where id=r.target_id) end,initcap(target_kind));
insert into mina_private.safety_events(actor_id,target_id,target_kind,action,receipt_id,label,occurred_at)
select reporter_id,target_id,target_kind,'report',id,target_label,created_at from public.reports;
insert into mina_private.safety_events(actor_id,target_id,target_kind,action,label)
select owner_id,blocked_id,'profile','existing_block',blocked_name from public.blocks;

create function mina_private.prepare_report() returns trigger language plpgsql set search_path='' as $$
declare subject uuid; label text;
begin
  if exists(select from public.reports where id=new.id and reporter_id=auth.uid() and target_id=new.target_id and target_kind=new.target_kind) then
    return new;
  end if;
  case new.target_kind
    when 'post','dream' then select owner_id,caption into subject,label from public.entries where id=new.target_id and kind=new.target_kind;
    when 'comment' then select owner_id,body into subject,label from public.entry_comments where id=new.target_id;
    when 'profile' then select id,name into subject,label from public.profiles where id=new.target_id;
    when 'room' then select host_id,title into subject,label from public.rooms where id=new.target_id;
    else raise exception 'Unknown report target.';
  end case;
  if subject is null or subject=auth.uid() then raise exception 'This item cannot be reported.'; end if;
  new.target_label=coalesce(nullif(left(label,160),''),initcap(new.target_kind));
  new.created_at=now();
  new.withdrawn_at=null;
  return new;
end $$;
create trigger prepare_report before insert on public.reports for each row execute function mina_private.prepare_report();

create function mina_private.prepare_block() returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.blocked_name=coalesce((select name from public.profiles where id=new.blocked_id and not private_profile),'Listener');
  return new;
end $$;
create trigger prepare_block before insert on public.blocks for each row execute function mina_private.prepare_block();
revoke update on public.blocks from authenticated;

create function mina_private.record_safety_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='blocks' then
    if tg_op='INSERT' then
      insert into mina_private.safety_events(actor_id,target_id,target_kind,action,label)
      values(new.owner_id,new.blocked_id,'profile','block',new.blocked_name);
    else
      insert into mina_private.safety_events(actor_id,target_id,target_kind,action,label)
      values(old.owner_id,old.blocked_id,'profile','unblock',old.blocked_name);
    end if;
  else
    insert into mina_private.safety_events(actor_id,target_id,target_kind,action,label,receipt_id)
    values(new.reporter_id,new.target_id,new.target_kind,case when tg_op='INSERT' then 'report' else 'withdraw' end,new.target_label,new.id);
  end if;
  return null;
end $$;
create trigger record_report after insert or update of withdrawn_at on public.reports for each row execute function mina_private.record_safety_event();
create trigger record_block after insert or delete on public.blocks for each row execute function mina_private.record_safety_event();

create index active_report_target on public.reports(reporter_id,target_kind,target_id) where withdrawn_at is null;
create function mina_private.report_visible(kind text,target uuid) returns boolean language sql stable security invoker set search_path='' as $$
  select not exists(select from public.reports where reporter_id=(select auth.uid())
    and target_kind=kind and target_id=target and withdrawn_at is null)
$$;
create function public.withdraw_report(receipt uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select from public.reports where id=receipt and reporter_id=auth.uid()) then
    raise exception 'Report unavailable.';
  end if;
  update public.reports set withdrawn_at=now() where id=receipt and reporter_id=auth.uid() and withdrawn_at is null;
end $$;
revoke all on function mina_private.check_reply(),mina_private.prepare_report(),mina_private.prepare_block(),mina_private.record_safety_event(),mina_private.report_visible(text,uuid),public.withdraw_report(uuid) from public,anon,authenticated;
grant execute on function mina_private.report_visible(text,uuid),public.withdraw_report(uuid) to authenticated;
create policy filter_reported_entries on public.entries as restrictive for select to authenticated using(mina_private.report_visible(kind,id));
create policy filter_reported_comments on public.entry_comments as restrictive for select to authenticated using(mina_private.report_visible('comment',id));
create policy filter_reported_rooms on public.rooms as restrictive for select to authenticated using(mina_private.report_visible('room',id));
create policy filter_reported_profiles on public.profiles as restrictive for select to authenticated using(mina_private.report_visible('profile',id));
notify pgrst,'reload schema';
