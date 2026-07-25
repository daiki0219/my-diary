begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table if not exists public.accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'user',
  status text not null default 'active',
  timezone text not null default 'Asia/Tokyo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_role_check
    check (role in ('user', 'admin')),
  constraint accounts_status_check
    check (status in ('active', 'suspended', 'deactivated')),
  constraint accounts_timezone_check
    check (
      char_length(btrim(timezone)) between 1 and 64
      and timezone = btrim(timezone)
    )
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null default '新しいユーザー',
  bio text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_check
    check (
      char_length(btrim(username)) between 1 and 50
      and username = btrim(username)
    ),
  constraint profiles_bio_check
    check (bio is null or char_length(bio) <= 500),
  constraint profiles_avatar_path_check
    check (avatar_path is null or char_length(avatar_path) between 1 and 1024)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text,
  body text not null,
  mood text,
  location_name text,
  visibility text not null default 'private',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint posts_title_check
    check (
      title is null
      or (
        char_length(btrim(title)) between 1 and 120
        and title = btrim(title)
      )
    ),
  constraint posts_body_check
    check (char_length(btrim(body)) between 1 and 10000),
  constraint posts_mood_check
    check (
      mood is null
      or mood in ('happy', 'sad', 'tired', 'irritated', 'calm', 'neutral')
    ),
  constraint posts_location_name_check
    check (
      location_name is null
      or (
        char_length(btrim(location_name)) between 1 and 100
        and location_name = btrim(location_name)
      )
    ),
  constraint posts_visibility_check
    check (visibility in ('private', 'followers', 'public'))
);

create table if not exists public.follows (
  follower_id uuid not null references auth.users (id) on delete cascade,
  following_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_not_self_check
    check (follower_id <> following_id)
);

create index if not exists posts_user_created_at_idx
  on public.posts (user_id, created_at desc)
  where deleted_at is null;

create index if not exists posts_public_created_at_idx
  on public.posts (created_at desc)
  where visibility = 'public' and deleted_at is null;

create index if not exists follows_following_follower_idx
  on public.follows (following_id, follower_id);

create index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;

drop trigger if exists accounts_set_updated_at on public.accounts;
create trigger accounts_set_updated_at
before update on public.accounts
for each row execute function public.set_updated_at();

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
before update on public.posts
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.accounts (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.profiles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

insert into public.accounts (user_id)
select id
from auth.users
where true
on conflict (user_id) do nothing;

insert into public.profiles (user_id)
select id
from auth.users
where true
on conflict (user_id) do nothing;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function private.is_account_active(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.accounts
    where user_id = target_user_id
      and status = 'active'
  );
$$;

revoke all on function private.is_account_active(uuid) from public;
grant execute on function private.is_account_active(uuid) to authenticated;

create or replace function public.soft_delete_post(target_post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_rows integer;
begin
  update public.posts
  set deleted_at = now()
  where id = target_post_id
    and user_id = auth.uid()
    and deleted_at is null
    and exists (
      select 1
      from public.accounts
      where user_id = auth.uid()
        and status = 'active'
    );

  get diagnostics affected_rows = row_count;
  return affected_rows = 1;
end;
$$;

revoke all on function public.soft_delete_post(uuid) from public;
grant execute on function public.soft_delete_post(uuid) to authenticated;

alter table public.accounts enable row level security;
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.follows enable row level security;

revoke all on table public.accounts from anon, authenticated;
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.posts from anon, authenticated;
revoke all on table public.follows from anon, authenticated;

grant select on table public.accounts to authenticated;
grant update (timezone) on table public.accounts to authenticated;

grant select on table public.profiles to authenticated;
grant update (username, bio, avatar_path) on table public.profiles to authenticated;

grant select on table public.posts to authenticated;
grant insert (user_id, title, body, mood, location_name, visibility)
  on table public.posts to authenticated;
grant update (title, body, mood, location_name, visibility)
  on table public.posts to authenticated;

grant select on table public.follows to authenticated;
grant insert (follower_id, following_id) on table public.follows to authenticated;
grant delete on table public.follows to authenticated;

drop policy if exists accounts_select_own on public.accounts;
create policy accounts_select_own
on public.accounts
for select
to authenticated
using (
  user_id = (select auth.uid())
);

drop policy if exists accounts_update_own_timezone on public.accounts;
create policy accounts_update_own_timezone
on public.accounts
for update
to authenticated
using (
  user_id = (select auth.uid())
  and private.is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and private.is_account_active((select auth.uid()))
);

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated
on public.profiles
for select
to authenticated
using ((select auth.uid()) is not null);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
on public.profiles
for update
to authenticated
using (
  user_id = (select auth.uid())
  and private.is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and private.is_account_active((select auth.uid()))
);

drop policy if exists posts_select_visible on public.posts;
create policy posts_select_visible
on public.posts
for select
to authenticated
using (
  deleted_at is null
  and (
    user_id = (select auth.uid())
    or (
      private.is_account_active((select auth.uid()))
      and private.is_account_active(posts.user_id)
      and (
        visibility = 'public'
        or (
          visibility = 'followers'
          and exists (
            select 1
            from public.follows
            where follower_id = (select auth.uid())
              and following_id = posts.user_id
          )
        )
      )
    )
  )
);

drop policy if exists posts_insert_own on public.posts;
create policy posts_insert_own
on public.posts
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and deleted_at is null
  and private.is_account_active((select auth.uid()))
);

drop policy if exists posts_update_own on public.posts;
create policy posts_update_own
on public.posts
for update
to authenticated
using (
  user_id = (select auth.uid())
  and deleted_at is null
  and private.is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and deleted_at is null
  and private.is_account_active((select auth.uid()))
);

drop policy if exists follows_select_authenticated on public.follows;
create policy follows_select_authenticated
on public.follows
for select
to authenticated
using (private.is_account_active((select auth.uid())));

drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own
on public.follows
for insert
to authenticated
with check (
  follower_id = (select auth.uid())
  and following_id <> (select auth.uid())
  and private.is_account_active((select auth.uid()))
);

drop policy if exists follows_delete_own on public.follows;
create policy follows_delete_own
on public.follows
for delete
to authenticated
using (
  follower_id = (select auth.uid())
  and private.is_account_active((select auth.uid()))
);

commit;
