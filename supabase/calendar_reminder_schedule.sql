-- Keep gateway JWT verification ENABLED. Replace __PUBLIC_ANON_JWT__ with
-- this project's existing public legacy anon JWT (never its service_role key).
-- The handler additionally validates the private scoped scheduler credential.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create or replace function public.invoke_calendar_reminders() returns void
language plpgsql security definer set search_path='' as $$
begin
  -- Avoid idle function calls: wake only when a registered recipient has a due reminder.
  if exists (
    select 1 from public.community_calendar_reminders r
    join public.community_calendar_events e on e.id=r.event_id
    join public.app_push_devices d on d.owner_id=r.user_id and d.platform='android'
    where e.starts_at-make_interval(mins=>r.minutes_before)<=now()
      and e.starts_at+interval '15 minutes'>now() and d.updated_at>now()-interval '90 days'
      and not exists(select 1 from public.community_calendar_deliveries x where x.event_id=e.id
        and x.user_id=r.user_id and x.device_id=d.id and x.starts_at=e.starts_at and x.minutes_before=r.minutes_before)
  ) then
    perform net.http_post(
      url:='https://rbcsrqisbuutnnxpmcvp.supabase.co/functions/v1/calendar-reminders',
      headers:=jsonb_build_object('Content-Type','application/json',
        'Authorization','Bearer __PUBLIC_ANON_JWT__','apikey','__PUBLIC_ANON_JWT__','x-calendar-worker-key',
        (select token from public.community_calendar_worker_config where singleton)),
      body:='{}'::jsonb,timeout_milliseconds:=60000);
  end if;
end;
$$;
revoke all on function public.invoke_calendar_reminders() from public,anon,authenticated;
select cron.schedule('community-calendar-reminders','* * * * *','select public.invoke_calendar_reminders()');
