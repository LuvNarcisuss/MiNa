alter table public.reports add column reviewed_at timestamptz;

comment on column public.reports.reviewed_at is
  'Time a moderator completed review. A null value means no completed review is recorded.';

create policy submit_reports_without_review on public.reports
  as restrictive for insert to authenticated
  with check (reviewed_at is null);

notify pgrst, 'reload schema';
