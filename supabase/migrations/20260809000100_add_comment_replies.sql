begin;

do $preflight$
declare
  comments_oid oid;
begin
  comments_oid := pg_catalog.to_regclass('public.comments');

  if comments_oid is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_post(uuid,text,timestamp with time zone)'
     ) is null then
    raise exception
      'add_comment_replies preflight failed: required objects are missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = comments_oid
      and attname = 'parent_comment_id'
      and not attisdropped
  )
  or pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_validate_comment_parent()'
  ) is not null
  or exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = comments_oid
      and tgname = 'my_diary_comments_validate_parent'
      and not tgisinternal
  )
  or pg_catalog.to_regclass(
    'public.my_diary_comments_post_parent_created_id_idx'
  ) is not null then
    raise exception
      'add_comment_replies preflight failed: reply objects already exist';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = comments_oid
  ) then
    raise exception
      'add_comment_replies preflight failed: comments RLS or owner differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
      and policyname in (
        'my_diary_comments_select_visible',
        'my_diary_comments_insert_own_visible_post'
      )
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
  ) <> 2 then
    raise exception
      'add_comment_replies preflight failed: comments policies differ';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', comments_oid, 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', comments_oid, 'post_id', 'INSERT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', comments_oid, 'user_id', 'INSERT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', comments_oid, 'body', 'INSERT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', comments_oid, 'UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon', comments_oid, 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'add_comment_replies preflight failed: comments ACL differs';
  end if;
end;
$preflight$;

alter table public.comments
  add column parent_comment_id uuid;

create index my_diary_comments_post_parent_created_id_idx
  on public.comments (post_id, parent_comment_id, created_at, id)
  where deleted_at is null;

create function my_diary_private.my_diary_validate_comment_parent()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  parent_comment public.comments%rowtype;
  parent_is_valid boolean := false;
begin
  if tg_op = 'UPDATE'
     and new.parent_comment_id is not distinct from old.parent_comment_id
     and new.post_id = old.post_id then
    return new;
  end if;

  if new.parent_comment_id is null then
    return new;
  end if;

  select comments.*
  into parent_comment
  from public.comments as comments
  where comments.id = new.parent_comment_id
  for update;

  if found then
    if parent_comment.post_id = new.post_id
       and parent_comment.parent_comment_id is null
       and parent_comment.deleted_at is null then
      parent_is_valid := my_diary_private.my_diary_is_account_active(
        parent_comment.user_id
      );
    end if;
  end if;

  if not parent_is_valid then
    raise check_violation
      using message = 'invalid parent comment';
  end if;

  return new;
end;
$function$;

alter function my_diary_private.my_diary_validate_comment_parent()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_validate_comment_parent()
  from public, anon, authenticated, service_role, authenticator;

create trigger my_diary_comments_validate_parent
after insert or update on public.comments
for each row execute function
  my_diary_private.my_diary_validate_comment_parent();

grant insert (parent_comment_id)
  on table public.comments to authenticated;

do $postcondition$
declare
  comments_oid oid := 'public.comments'::pg_catalog.regclass;
  validator_oid oid;
begin
  if not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = comments_oid
      and attname = 'parent_comment_id'
      and atttypid = 'uuid'::pg_catalog.regtype
      and not attnotnull
      and not atthasdef
      and not attisdropped
  ) then
    raise exception
      'add_comment_replies postcondition failed: parent column differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'comments'
      and indexname = 'my_diary_comments_post_parent_created_id_idx'
      and indexdef like '%(post_id, parent_comment_id, created_at, id)%'
      and indexdef like '%WHERE (deleted_at IS NULL)%'
  ) then
    raise exception
      'add_comment_replies postcondition failed: reply index differs';
  end if;

  select function_definition.oid
  into validator_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'my_diary_private'
    and function_definition.proname = 'my_diary_validate_comment_parent'
    and function_definition.proargtypes = ''::oidvector
    and function_definition.prorettype = 'trigger'::pg_catalog.regtype
    and function_definition.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      like '%for update%';

  if validator_oid is null
     or exists (
       select 1
       from pg_catalog.aclexplode(
         coalesce(
           (
             select proacl
             from pg_catalog.pg_proc
             where oid = validator_oid
           ),
           pg_catalog.acldefault(
             'f',
             (
               select proowner
               from pg_catalog.pg_proc
               where oid = validator_oid
             )
           )
         )
       ) as function_acl
       where function_acl.grantee = 0
         and function_acl.privilege_type = 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array[
           'anon', 'authenticated', 'service_role', 'authenticator'
         ]
       ) as denied(role_name)
       where pg_catalog.has_function_privilege(
         denied.role_name, validator_oid, 'EXECUTE'
       )
     ) then
    raise exception
      'add_comment_replies postcondition failed: validator attributes or ACL differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = comments_oid
      and tgname = 'my_diary_comments_validate_parent'
      and tgfoid = validator_oid
      and tgenabled = 'O'
      and not tgisinternal
      and pg_catalog.pg_get_triggerdef(oid)
        like '%AFTER INSERT OR UPDATE%'
  ) then
    raise exception
      'add_comment_replies postcondition failed: validator trigger differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = comments_oid
  )
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
      and policyname in (
        'my_diary_comments_select_visible',
        'my_diary_comments_insert_own_visible_post'
      )
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
  ) <> 2 then
    raise exception
      'add_comment_replies postcondition failed: comments RLS differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', comments_oid, 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', comments_oid, 'parent_comment_id', 'INSERT'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', comments_oid, 'parent_comment_id', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', comments_oid, 'UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon', comments_oid, 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'add_comment_replies postcondition failed: comments ACL differs';
  end if;
end;
$postcondition$;

commit;
