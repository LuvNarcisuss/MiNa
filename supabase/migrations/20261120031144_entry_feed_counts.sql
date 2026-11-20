create view public.entry_feed with (security_invoker=true) as
select e.id,e.owner_id,e.kind,e.caption,e.media_path,e.duration,e.created_at,
 (select count(*) from public.entry_comments c where c.entry_id=e.id) as comment_count,
 (select count(*) from public.entry_reactions r where r.entry_id=e.id and r.kind='like') as like_count,
 exists(select 1 from public.entry_reactions r where r.entry_id=e.id and r.owner_id=(select auth.uid()) and r.kind='like') as liked,
 exists(select 1 from public.entry_reactions r where r.entry_id=e.id and r.owner_id=(select auth.uid()) and r.kind='save') as saved
from public.entries e;
revoke all on public.entry_feed from public,anon,authenticated;
grant select on public.entry_feed to authenticated;
