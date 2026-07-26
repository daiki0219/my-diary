begin;

create table public.reactions (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  user_id uuid not null,
  reaction_type text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_reactions_pkey primary key (id),
  constraint my_diary_reactions_post_user_key unique (post_id, user_id),
  constraint my_diary_reactions_post_id_fkey
    foreign key (post_id) references public.posts (id) on delete cascade,
  constraint my_diary_reactions_user_id_fkey
    foreign key (user_id) references public.accounts (user_id) on delete cascade,
  constraint my_diary_reactions_type_check
    check (reaction_type in ('empathy', 'support', 'relatable'))
);

create index my_diary_reactions_post_type_idx
  on public.reactions (post_id, reaction_type);

create trigger my_diary_reactions_set_updated_at
before update on public.reactions
for each row execute function public.my_diary_set_updated_at();

alter table public.reactions enable row level security;

revoke all on table public.reactions from public, anon, authenticated;

grant select on table public.reactions to authenticated;
grant insert (post_id, user_id, reaction_type)
  on table public.reactions to authenticated;
grant update (reaction_type) on table public.reactions to authenticated;
grant delete on table public.reactions to authenticated;

create policy my_diary_reactions_select_visible_post
on public.reactions
for select
to authenticated
using (
  exists (
    select 1
    from public.posts
    where posts.id = reactions.post_id
  )
);

create policy my_diary_reactions_insert_own_visible_post
on public.reactions
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = reactions.post_id
  )
);

create policy my_diary_reactions_update_own_visible_post
on public.reactions
for update
to authenticated
using (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = reactions.post_id
  )
)
with check (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = reactions.post_id
  )
);

create policy my_diary_reactions_delete_own_visible_post
on public.reactions
for delete
to authenticated
using (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.posts
    where posts.id = reactions.post_id
  )
);

commit;
