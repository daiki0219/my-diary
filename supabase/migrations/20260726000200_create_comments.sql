begin;

create table public.comments (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  user_id uuid not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint my_diary_comments_pkey primary key (id),
  constraint my_diary_comments_post_id_fkey
    foreign key (post_id) references public.posts (id) on delete cascade,
  constraint my_diary_comments_user_id_fkey
    foreign key (user_id) references public.accounts (user_id) on delete cascade,
  constraint my_diary_comments_body_check
    check (
      char_length(body) between 1 and 1000
      and body = btrim(body, E' \t\n\r\f\v')
      and body ~ '[^[:space:]]'
    ),
  constraint my_diary_comments_deleted_at_check
    check (deleted_at is null or deleted_at >= created_at)
);

create index my_diary_comments_post_created_id_idx
  on public.comments (post_id, created_at, id)
  where deleted_at is null;

create trigger my_diary_comments_set_updated_at
before update on public.comments
for each row execute function public.my_diary_set_updated_at();

alter table public.comments enable row level security;

revoke all on table public.comments from public, anon, authenticated;

grant select on table public.comments to authenticated;
grant insert (post_id, user_id, body)
  on table public.comments to authenticated;
grant update (deleted_at) on table public.comments to authenticated;

create policy my_diary_comments_select_visible
on public.comments
for select
to authenticated
using (
  deleted_at is null
  and (
    user_id = (select auth.uid())
    or my_diary_private.my_diary_is_account_active(comments.user_id)
  )
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
  )
);

create policy my_diary_comments_insert_own_visible_post
on public.comments
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and deleted_at is null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
  )
);

create policy my_diary_comments_soft_delete_own
on public.comments
for update
to authenticated
using (
  user_id = (select auth.uid())
  and deleted_at is null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
  )
)
with check (
  user_id = (select auth.uid())
  and deleted_at is not null
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
  )
);

commit;
