begin;

do $preflight$
declare
  accounts_oid oid := pg_catalog.to_regclass('public.accounts');
  posts_oid oid := pg_catalog.to_regclass('public.posts');
  comments_oid oid := pg_catalog.to_regclass('public.comments');
begin
  if accounts_oid is null
     or posts_oid is null
     or comments_oid is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_post(uuid,text,timestamp with time zone)'
     ) is null then
    raise exception
      'create_notifications preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regclass('public.notifications') is not null
     or pg_catalog.to_regclass(
       'public.my_diary_notifications_recipient_created_id_idx'
     ) is not null then
    raise exception
      'create_notifications preflight failed: notification objects already exist';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = posts_oid
  )
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
      and qual like '%my_diary_can_view_post%'
  ) <> 1 then
    raise exception
      'create_notifications preflight failed: posts visibility boundary differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', posts_oid, 'SELECT'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'my_diary_private.my_diary_is_account_active(uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'my_diary_private.my_diary_can_view_post(uuid,text,timestamp with time zone)',
       'EXECUTE'
     ) then
    raise exception
      'create_notifications preflight failed: visibility ACL differs';
  end if;
end;
$preflight$;

create table public.notifications (
  id uuid not null default gen_random_uuid(),
  recipient_user_id uuid not null,
  actor_user_id uuid not null,
  notification_type text not null,
  target_post_id uuid,
  target_comment_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint my_diary_notifications_pkey primary key (id),
  constraint my_diary_notifications_recipient_user_id_fkey
    foreign key (recipient_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_notifications_actor_user_id_fkey
    foreign key (actor_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_notifications_target_post_id_fkey
    foreign key (target_post_id)
    references public.posts (id)
    on delete cascade,
  constraint my_diary_notifications_target_comment_id_fkey
    foreign key (target_comment_id)
    references public.comments (id)
    on delete cascade,
  constraint my_diary_notifications_type_check
    check (notification_type in ('follow', 'reaction', 'comment', 'reply')),
  constraint my_diary_notifications_not_self_check
    check (actor_user_id <> recipient_user_id),
  constraint my_diary_notifications_target_shape_check
    check (
      (
        notification_type = 'follow'
        and target_post_id is null
        and target_comment_id is null
      )
      or (
        notification_type = 'reaction'
        and target_post_id is not null
        and target_comment_id is null
      )
      or (
        notification_type in ('comment', 'reply')
        and target_post_id is not null
        and target_comment_id is not null
      )
    )
);

create index my_diary_notifications_recipient_created_id_idx
  on public.notifications (recipient_user_id, created_at desc, id desc);

alter table public.notifications enable row level security;

revoke all on table public.notifications
  from public, anon, authenticated;

grant select on table public.notifications to authenticated;
grant update (is_read) on table public.notifications to authenticated;

create policy my_diary_notifications_select_recipient
on public.notifications
for select
to authenticated
using (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    target_post_id is null
    or exists (
      select 1
      from public.posts
      where posts.id = notifications.target_post_id
    )
  )
);

create policy my_diary_notifications_update_read_state
on public.notifications
for update
to authenticated
using (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    target_post_id is null
    or exists (
      select 1
      from public.posts
      where posts.id = notifications.target_post_id
    )
  )
)
with check (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    target_post_id is null
    or exists (
      select 1
      from public.posts
      where posts.id = notifications.target_post_id
    )
  )
);

do $postcondition$
declare
  notifications_oid oid := 'public.notifications'::pg_catalog.regclass;
begin
  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = notifications_oid
  ) then
    raise exception
      'create_notifications postcondition failed: owner or RLS differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_attribute
    where attrelid = notifications_oid
      and attnum > 0
      and not attisdropped
  ) <> 8
  or not exists (
    select 1
    from pg_catalog.pg_attribute
    join pg_catalog.pg_attrdef
      on adrelid = attrelid
      and adnum = attnum
    where attrelid = notifications_oid
      and attname = 'is_read'
      and atttypid = 'boolean'::pg_catalog.regtype
      and attnotnull
      and atthasdef
      and pg_catalog.pg_get_expr(
        adbin,
        adrelid
      ) = 'false'
  ) then
    raise exception
      'create_notifications postcondition failed: columns differ';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname in (
        'my_diary_notifications_pkey',
        'my_diary_notifications_recipient_user_id_fkey',
        'my_diary_notifications_actor_user_id_fkey',
        'my_diary_notifications_target_post_id_fkey',
        'my_diary_notifications_target_comment_id_fkey',
        'my_diary_notifications_type_check',
        'my_diary_notifications_not_self_check',
        'my_diary_notifications_target_shape_check'
      )
  ) <> 8
  or (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and contype = 'f'
      and confdeltype = 'c'
  ) <> 4 then
    raise exception
      'create_notifications postcondition failed: constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'notifications'
      and indexname = 'my_diary_notifications_recipient_created_id_idx'
      and indexdef like
        '%(recipient_user_id, created_at DESC, id DESC)%'
  ) then
    raise exception
      'create_notifications postcondition failed: index differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname in (
        'my_diary_notifications_select_recipient',
        'my_diary_notifications_update_read_state'
      )
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
      and qual like '%my_diary_is_account_active%'
      and qual like '%target_post_id%'
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) <> 2 then
    raise exception
      'create_notifications postcondition failed: policies differ';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'is_read', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'INSERT, DELETE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'actor_user_id', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'anon', notifications_oid, 'SELECT, INSERT, UPDATE, DELETE'
     )
     or exists (
       select 1
       from pg_catalog.aclexplode(
         coalesce(
           (
             select relacl
             from pg_catalog.pg_class
             where oid = notifications_oid
           ),
           pg_catalog.acldefault(
             'r',
             (
               select relowner
               from pg_catalog.pg_class
               where oid = notifications_oid
             )
           )
         )
       ) as table_acl
       where table_acl.grantee = 0
     ) then
    raise exception
      'create_notifications postcondition failed: table ACL differs';
  end if;
end;
$postcondition$;

commit;
