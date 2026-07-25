begin;

create extension if not exists pgcrypto with schema extensions;

create schema my_diary_private;
revoke all on schema my_diary_private from public, anon, authenticated;
grant usage on schema my_diary_private to authenticated;

create table public.accounts (
  user_id uuid not null,
  role text not null default 'user',
  status text not null default 'active',
  timezone text not null default 'Asia/Tokyo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_accounts_pkey primary key (user_id),
  constraint my_diary_accounts_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  constraint my_diary_accounts_role_check
    check (role in ('user', 'admin')),
  constraint my_diary_accounts_status_check
    check (status in ('active', 'suspended', 'deactivated')),
  constraint my_diary_accounts_timezone_check
    check (
      char_length(btrim(timezone)) between 1 and 64
      and timezone = btrim(timezone)
    )
);

create table public.profiles (
  user_id uuid not null,
  username text not null default '新しいユーザー',
  bio text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_profiles_pkey primary key (user_id),
  constraint my_diary_profiles_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  constraint my_diary_profiles_username_check
    check (
      char_length(btrim(username)) between 1 and 50
      and username = btrim(username)
    ),
  constraint my_diary_profiles_bio_check
    check (bio is null or char_length(bio) <= 500),
  constraint my_diary_profiles_avatar_path_check
    check (avatar_path is null or char_length(avatar_path) between 1 and 1024)
);

create table public.posts (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  title text,
  body text not null,
  mood text,
  location_name text,
  visibility text not null default 'private',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint my_diary_posts_pkey primary key (id),
  constraint my_diary_posts_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  constraint my_diary_posts_title_check
    check (
      title is null
      or (
        char_length(btrim(title)) between 1 and 120
        and title = btrim(title)
      )
    ),
  constraint my_diary_posts_body_check
    check (char_length(btrim(body)) between 1 and 10000),
  constraint my_diary_posts_mood_check
    check (
      mood is null
      or mood in ('happy', 'sad', 'tired', 'irritated', 'calm', 'neutral')
    ),
  constraint my_diary_posts_location_name_check
    check (
      location_name is null
      or (
        char_length(btrim(location_name)) between 1 and 100
        and location_name = btrim(location_name)
      )
    ),
  constraint my_diary_posts_visibility_check
    check (visibility in ('private', 'followers', 'public'))
);

create table public.follows (
  follower_id uuid not null,
  following_id uuid not null,
  created_at timestamptz not null default now(),
  constraint my_diary_follows_pkey primary key (follower_id, following_id),
  constraint my_diary_follows_follower_id_fkey
    foreign key (follower_id) references auth.users (id) on delete cascade,
  constraint my_diary_follows_following_id_fkey
    foreign key (following_id) references auth.users (id) on delete cascade,
  constraint my_diary_follows_not_self_check
    check (follower_id <> following_id)
);

create index my_diary_posts_user_created_at_idx
  on public.posts (user_id, created_at desc)
  where deleted_at is null;

create index my_diary_posts_public_created_at_idx
  on public.posts (created_at desc)
  where visibility = 'public' and deleted_at is null;

create index my_diary_follows_following_follower_idx
  on public.follows (following_id, follower_id);

create index my_diary_profiles_username_lower_idx
  on public.profiles (lower(username));

create function public.my_diary_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter function public.my_diary_set_updated_at() owner to postgres;
revoke all on function public.my_diary_set_updated_at()
  from public, anon, authenticated;

create trigger my_diary_accounts_set_updated_at
before update on public.accounts
for each row execute function public.my_diary_set_updated_at();

create trigger my_diary_profiles_set_updated_at
before update on public.profiles
for each row execute function public.my_diary_set_updated_at();

create trigger my_diary_posts_set_updated_at
before update on public.posts
for each row execute function public.my_diary_set_updated_at();

create function public.my_diary_handle_new_auth_user()
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

alter function public.my_diary_handle_new_auth_user() owner to postgres;
revoke all on function public.my_diary_handle_new_auth_user()
  from public, anon, authenticated;

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

create trigger my_diary_on_auth_user_created
after insert on auth.users
for each row execute function public.my_diary_handle_new_auth_user();

create function my_diary_private.my_diary_is_account_active(
  target_user_id uuid
)
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

alter function my_diary_private.my_diary_is_account_active(uuid)
  owner to postgres;
revoke all on function my_diary_private.my_diary_is_account_active(uuid)
  from public, anon, authenticated;
grant execute on function
  my_diary_private.my_diary_is_account_active(uuid)
  to authenticated;

create function public.my_diary_soft_delete_post(target_post_id uuid)
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

alter function public.my_diary_soft_delete_post(uuid) owner to postgres;
revoke all on function public.my_diary_soft_delete_post(uuid)
  from public, anon, authenticated;
grant execute on function public.my_diary_soft_delete_post(uuid)
  to authenticated;

alter table public.accounts enable row level security;
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.follows enable row level security;

revoke all on table public.accounts from public, anon, authenticated;
revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.posts from public, anon, authenticated;
revoke all on table public.follows from public, anon, authenticated;

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

create policy my_diary_accounts_select_own
on public.accounts
for select
to authenticated
using (
  user_id = (select auth.uid())
);

create policy my_diary_accounts_update_own_timezone
on public.accounts
for update
to authenticated
using (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_profiles_select_authenticated
on public.profiles
for select
to authenticated
using ((select auth.uid()) is not null);

create policy my_diary_profiles_update_own
on public.profiles
for update
to authenticated
using (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_posts_select_visible
on public.posts
for select
to authenticated
using (
  deleted_at is null
  and (
    user_id = (select auth.uid())
    or (
      my_diary_private.my_diary_is_account_active((select auth.uid()))
      and my_diary_private.my_diary_is_account_active(posts.user_id)
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

create policy my_diary_posts_insert_own
on public.posts
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and deleted_at is null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_posts_update_own
on public.posts
for update
to authenticated
using (
  user_id = (select auth.uid())
  and deleted_at is null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and deleted_at is null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_follows_select_authenticated
on public.follows
for select
to authenticated
using (
  my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_follows_insert_own
on public.follows
for insert
to authenticated
with check (
  follower_id = (select auth.uid())
  and following_id <> (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_follows_delete_own
on public.follows
for delete
to authenticated
using (
  follower_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

commit;
