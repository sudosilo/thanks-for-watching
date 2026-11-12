-- Thanks For Watching tables. They live in the shared accounts hub project next to Kat Chat.
-- Every table starts with tfw_ so it never collides with another app.
-- Row level security is on with no policies, so only the server function (secret key) can touch them.

create table if not exists public.tfw_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text unique not null check (handle ~ '^[a-z0-9_]{3,24}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.tfw_videos (
  uid text primary key,
  owner uuid not null references auth.users(id) on delete cascade,
  state text not null default 'pending',
  host text,
  views int not null default 0,
  flags int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists tfw_videos_ready on public.tfw_videos (state, views);
create index if not exists tfw_videos_owner on public.tfw_videos (owner, created_at);

create table if not exists public.tfw_seen (
  viewer uuid not null references auth.users(id) on delete cascade,
  uid text not null references public.tfw_videos(uid) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key (viewer, uid)
);

create table if not exists public.tfw_flags (
  uid text not null references public.tfw_videos(uid) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (uid, user_id)
);

create table if not exists public.tfw_creators_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  owner uuid not null,
  primary key (user_id, owner)
);

create table if not exists public.tfw_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device text not null,
  primary key (user_id, device)
);

create table if not exists public.tfw_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  watched int not null default 0,
  seconds int not null default 0
);

alter table public.tfw_profiles enable row level security;
alter table public.tfw_videos enable row level security;
alter table public.tfw_seen enable row level security;
alter table public.tfw_flags enable row level security;
alter table public.tfw_creators_seen enable row level security;
alter table public.tfw_devices enable row level security;
alter table public.tfw_stats enable row level security;

create or replace function public.tfw_add_view(p_uid text) returns void
language sql security definer set search_path = public as $$
  update tfw_videos set views = views + 1 where uid = p_uid;
$$;

create or replace function public.tfw_add_watch(p_user uuid, p_watched int, p_seconds int) returns void
language sql security definer set search_path = public as $$
  insert into tfw_stats (user_id, watched, seconds) values (p_user, p_watched, p_seconds)
  on conflict (user_id) do update
    set watched = tfw_stats.watched + excluded.watched,
        seconds = tfw_stats.seconds + excluded.seconds;
$$;

create or replace function public.tfw_flag(p_uid text, p_user uuid, p_limit int) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into tfw_flags (uid, user_id) values (p_uid, p_user) on conflict do nothing;
  if found then
    update tfw_videos set flags = flags + 1 where uid = p_uid returning flags into n;
    if n >= p_limit then
      update tfw_videos set state = 'flagged' where uid = p_uid;
    end if;
  end if;
  return coalesce(n, 0);
end;
$$;

revoke execute on function public.tfw_add_view(text) from public, anon, authenticated;
revoke execute on function public.tfw_add_watch(uuid, int, int) from public, anon, authenticated;
revoke execute on function public.tfw_flag(text, uuid, int) from public, anon, authenticated;
grant execute on function public.tfw_add_view(text) to service_role;
grant execute on function public.tfw_add_watch(uuid, int, int) to service_role;
grant execute on function public.tfw_flag(text, uuid, int) to service_role;
