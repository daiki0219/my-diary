begin;

do $preflight$
declare
  follows_oid oid := pg_catalog.to_regclass('public.follows');
  reactions_oid oid := pg_catalog.to_regclass('public.reactions');
  comments_oid oid := pg_catalog.to_regclass('public.comments');
  posts_oid oid := pg_catalog.to_regclass('public.posts');
  notifications_oid oid := pg_catalog.to_regclass('public.notifications');
begin
  if follows_oid is null
     or reactions_oid is null
     or comments_oid is null
     or posts_oid is null
     or notifications_oid is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_validate_comment_parent()'
     ) is null then
    raise exception
      'generate_notifications preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_generate_follow_notification()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_generate_reaction_notification()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_generate_comment_notification()'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_trigger
       where tgname in (
         'my_diary_follows_generate_notification',
         'my_diary_reactions_generate_notification',
         'my_diary_comments_generate_notification'
       )
         and not tgisinternal
     ) then
    raise exception
      'generate_notifications preflight failed: notification generators already exist';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = comments_oid
      and tgname = 'my_diary_comments_validate_parent'
      and tgenabled = 'O'
      and not tgisinternal
      and pg_catalog.pg_get_triggerdef(oid)
        like '%AFTER INSERT OR UPDATE%'
  ) then
    raise exception
      'generate_notifications preflight failed: reply validator differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = notifications_oid
  )
  or (
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
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) <> 2
  or not pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'SELECT'
     )
  or not pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'is_read', 'UPDATE'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'INSERT, DELETE'
     )
  or pg_catalog.has_table_privilege(
       'anon', notifications_oid, 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'generate_notifications preflight failed: notifications RLS or ACL differs';
  end if;
end;
$preflight$;

create function my_diary_private.my_diary_generate_follow_notification()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  authenticated_user_id uuid := auth.uid();
begin
  if authenticated_user_id is null
     or authenticated_user_id <> new.follower_id
     or not my_diary_private.my_diary_is_account_active(new.follower_id)
     or not my_diary_private.my_diary_is_account_active(new.following_id) then
    return new;
  end if;

  insert into public.notifications (
    recipient_user_id,
    actor_user_id,
    notification_type
  )
  select
    new.following_id,
    new.follower_id,
    'follow'
  where new.follower_id <> new.following_id;

  return new;
end;
$function$;

alter function my_diary_private.my_diary_generate_follow_notification()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_generate_follow_notification()
  from public, anon, authenticated, service_role, authenticator;

create function my_diary_private.my_diary_generate_reaction_notification()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  authenticated_user_id uuid := auth.uid();
begin
  if authenticated_user_id is null
     or authenticated_user_id <> new.user_id
     or not my_diary_private.my_diary_is_account_active(new.user_id) then
    return new;
  end if;

  insert into public.notifications (
    recipient_user_id,
    actor_user_id,
    notification_type,
    target_post_id
  )
  select
    target_post.user_id,
    new.user_id,
    'reaction',
    new.post_id
  from public.posts as target_post
  where target_post.id = new.post_id
    and target_post.deleted_at is null
    and target_post.user_id <> new.user_id
    and my_diary_private.my_diary_is_account_active(target_post.user_id);

  return new;
end;
$function$;

alter function my_diary_private.my_diary_generate_reaction_notification()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_generate_reaction_notification()
  from public, anon, authenticated, service_role, authenticator;

create function my_diary_private.my_diary_generate_comment_notification()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  authenticated_user_id uuid := auth.uid();
begin
  if authenticated_user_id is null
     or authenticated_user_id <> new.user_id
     or not my_diary_private.my_diary_is_account_active(new.user_id) then
    return new;
  end if;

  if new.parent_comment_id is null then
    insert into public.notifications (
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_post_id,
      target_comment_id
    )
    select
      target_post.user_id,
      new.user_id,
      'comment',
      new.post_id,
      new.id
    from public.posts as target_post
    where target_post.id = new.post_id
      and target_post.deleted_at is null
      and target_post.user_id <> new.user_id
      and my_diary_private.my_diary_is_account_active(target_post.user_id);
  else
    insert into public.notifications (
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_post_id,
      target_comment_id
    )
    select
      parent_comment.user_id,
      new.user_id,
      'reply',
      new.post_id,
      new.id
    from public.comments as parent_comment
    where parent_comment.id = new.parent_comment_id
      and parent_comment.post_id = new.post_id
      and parent_comment.parent_comment_id is null
      and parent_comment.deleted_at is null
      and parent_comment.user_id <> new.user_id
      and my_diary_private.my_diary_is_account_active(parent_comment.user_id)
      and exists (
        select 1
        from public.posts as target_post
        where target_post.id = new.post_id
          and target_post.deleted_at is null
          and my_diary_private.my_diary_is_account_active(target_post.user_id)
      );
  end if;

  return new;
end;
$function$;

alter function my_diary_private.my_diary_generate_comment_notification()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_generate_comment_notification()
  from public, anon, authenticated, service_role, authenticator;

create trigger my_diary_follows_generate_notification
after insert on public.follows
for each row
when (
  current_user = 'authenticated'::name
  and auth.uid() = new.follower_id
)
execute function
  my_diary_private.my_diary_generate_follow_notification();

create trigger my_diary_reactions_generate_notification
after insert on public.reactions
for each row
when (
  current_user = 'authenticated'::name
  and auth.uid() = new.user_id
)
execute function
  my_diary_private.my_diary_generate_reaction_notification();

create trigger my_diary_comments_generate_notification
after insert on public.comments
for each row
when (
  current_user = 'authenticated'::name
  and auth.uid() = new.user_id
)
execute function
  my_diary_private.my_diary_generate_comment_notification();

do $postcondition$
declare
  notifications_oid oid := 'public.notifications'::pg_catalog.regclass;
  comments_oid oid := 'public.comments'::pg_catalog.regclass;
  generator_function_names text[] := array[
    'my_diary_generate_follow_notification',
    'my_diary_generate_reaction_notification',
    'my_diary_generate_comment_notification'
  ];
begin
  if (
    select count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function_definition.prolang
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = any(generator_function_names)
      and function_definition.proargtypes = ''::oidvector
      and function_definition.prorettype = 'trigger'::pg_catalog.regtype
      and function_definition.prokind = 'f'
      and language.lanname = 'plpgsql'
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) <> 3 then
    raise exception
      'generate_notifications postcondition failed: function attributes differ';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as function_acl
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = any(generator_function_names)
      and function_definition.proargtypes = ''::oidvector
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  )
  or exists (
    select 1
    from pg_catalog.unnest(
      array[
        'anon', 'authenticated', 'service_role', 'authenticator'
      ]
    ) as denied(role_name)
    cross join pg_catalog.unnest(generator_function_names)
      as generator(function_name)
    where pg_catalog.has_function_privilege(
      denied.role_name,
      pg_catalog.to_regprocedure(
        'my_diary_private.' || generator.function_name || '()'
      ),
      'EXECUTE'
    )
  ) then
    raise exception
      'generate_notifications postcondition failed: function ACL differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_trigger as trigger_definition
    join pg_catalog.pg_proc as function_definition
      on function_definition.oid = trigger_definition.tgfoid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where trigger_definition.tgname in (
        'my_diary_follows_generate_notification',
        'my_diary_reactions_generate_notification',
        'my_diary_comments_generate_notification'
      )
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgisinternal
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        like '%AFTER INSERT ON%'
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        ilike '%current_user%authenticated%auth.uid()%'
      and namespace.nspname = 'my_diary_private'
      and function_definition.proname = any(generator_function_names)
  ) <> 3 then
    raise exception
      'generate_notifications postcondition failed: triggers differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = comments_oid
      and tgname = 'my_diary_comments_validate_parent'
      and tgenabled = 'O'
      and not tgisinternal
      and pg_catalog.pg_get_triggerdef(oid)
        like '%AFTER INSERT OR UPDATE%'
  ) then
    raise exception
      'generate_notifications postcondition failed: reply validator differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = notifications_oid
  )
  or (
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
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) <> 2
  or not pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'SELECT'
     )
  or not pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'is_read', 'UPDATE'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'INSERT, DELETE'
     )
  or pg_catalog.has_table_privilege(
       'anon', notifications_oid, 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'generate_notifications postcondition failed: notifications RLS or ACL differs';
  end if;
end;
$postcondition$;

commit;
