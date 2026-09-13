-- Mobin VPN accounts. Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to run again (uses IF NOT EXISTS / OR REPLACE).

-- One row per user. Users cannot change their own `enabled`, usage totals or device directly:
-- the app goes through the security-definer functions below, the admin panel through admin policies.
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  full_name text not null default '',
  enabled boolean not null default true,
  device_id text,
  device_name text,
  usage_up bigint not null default 0,
  usage_down bigint not null default 0,
  created_at timestamptz not null default now(),
  last_seen timestamptz
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

alter table public.profiles enable row level security;
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

drop policy if exists "own profile readable" on public.profiles;
create policy "own profile readable" on public.profiles for select using (id = auth.uid() or public.is_admin());

drop policy if exists "admins update profiles" on public.profiles;
create policy "admins update profiles" on public.profiles for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins read admins" on public.admins;
create policy "admins read admins" on public.admins for select using (user_id = auth.uid() or public.is_admin());

-- Create the profile automatically on sign-up (name comes from the sign-up form metadata).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- App: bind the account to this device on first use. Returns the account status for the app:
-- 'ok', 'disabled' (turned off in the panel) or 'other_device' (already bound to another device).
create or replace function public.claim_device(p_device_id text, p_device_name text) returns text
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found then
    insert into public.profiles (id, email) select id, email from auth.users where id = auth.uid();
    select * into p from public.profiles where id = auth.uid();
  end if;
  if not p.enabled then return 'disabled'; end if;
  if p.device_id is not null and p.device_id <> p_device_id then return 'other_device'; end if;
  update public.profiles
     set device_id = p_device_id, device_name = p_device_name, last_seen = now()
   where id = auth.uid();
  return 'ok';
end;
$$;

-- App: add traffic (bytes) used since the last report. Only works from the bound device.
create or replace function public.report_usage(p_device_id text, p_up bigint, p_down bigint) returns text
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found or not p.enabled then return 'disabled'; end if;
  if p.device_id is distinct from p_device_id then return 'other_device'; end if;
  update public.profiles
     set usage_up = usage_up + greatest(p_up, 0),
         usage_down = usage_down + greatest(p_down, 0),
         last_seen = now()
   where id = auth.uid();
  return 'ok';
end;
$$;

revoke all on function public.claim_device(text, text) from public, anon;
revoke all on function public.report_usage(text, bigint, bigint) from public, anon;
grant execute on function public.claim_device(text, text) to authenticated;
grant execute on function public.report_usage(text, bigint, bigint) to authenticated;

-- ── After you have signed up once with your own email (in the app or the panel), make yourself admin:
-- insert into public.admins (user_id) select id from auth.users where email = 'YOUR-EMAIL@example.com';
