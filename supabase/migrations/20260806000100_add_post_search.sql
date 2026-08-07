begin;

do $preflight$
declare
  visibility_helper_oid oid;
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.posts') is null then
    raise exception
      'add_post_search preflight failed: required objects are missing';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role
      where role.rolname = required.role_name
    )
  ) then
    raise exception
      'add_post_search preflight failed: a required role is missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_posts'
  ) then
    raise exception
      'add_post_search preflight failed: post search function name exists';
  end if;

  select function.oid
  into visibility_helper_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'my_diary_private'
    and function.proname = 'my_diary_can_view_post'
    and function.pronargs = 3
    and function.proargtypes = '2950 25 1184'::pg_catalog.oidvector
    and function.prorettype = 'boolean'::pg_catalog.regtype
    and language.lanname = 'sql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.prosecdef
    and function.provolatile = 's'
    and function.proconfig = array['search_path=""']::text[];

  if visibility_helper_oid is null then
    raise exception
      'add_post_search preflight failed: visibility helper differs';
  end if;

  if not (
    select relation.relrowsecurity and not relation.relforcerowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.posts'::pg_catalog.regclass
  ) or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and cmd = 'SELECT'
  ) <> 1 or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) then
    raise exception
      'add_post_search preflight failed: posts RLS differs';
  end if;

  if not pg_catalog.has_table_privilege(
    'authenticated', 'public.posts', 'SELECT'
  ) or pg_catalog.has_table_privilege(
    'anon', 'public.posts', 'SELECT'
  ) or exists (
    select 1
    from pg_catalog.pg_class as relation
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation.relacl,
        pg_catalog.acldefault('r', relation.relowner)
      )
    ) as privilege
    where relation.oid = 'public.posts'::pg_catalog.regclass
      and privilege.grantee = 0
      and privilege.privilege_type = 'SELECT'
  ) then
    raise exception
      'add_post_search preflight failed: posts SELECT ACL differs';
  end if;
end;
$preflight$;

create function public.my_diary_search_posts(
  search_query text,
  before_created_at timestamptz,
  before_id uuid
)
returns table (
  id uuid,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  normalized_query text;
  escaped_query text;
begin
  if auth.uid() is null then
    raise insufficient_privilege;
  end if;

  if search_query is null then
    raise invalid_parameter_value;
  end if;

  normalized_query := normalize(search_query, NFKC);

  if normalized_query ~ '[[:cntrl:]]' then
    raise invalid_parameter_value;
  end if;

  normalized_query := pg_catalog.btrim(normalized_query);

  if pg_catalog.char_length(normalized_query) not between 1 and 50 then
    raise invalid_parameter_value;
  end if;

  if (before_created_at is null) <> (before_id is null) then
    raise invalid_parameter_value;
  end if;

  escaped_query := pg_catalog.lower(normalized_query);
  escaped_query := pg_catalog.replace(escaped_query, E'\\', E'\\\\');
  escaped_query := pg_catalog.replace(escaped_query, '%', E'\\%');
  escaped_query := pg_catalog.replace(escaped_query, '_', E'\\_');

  return query
  select
    posts.id,
    posts.created_at
  from public.posts as posts
  where (
      (
        posts.title is not null
        and pg_catalog.lower(normalize(posts.title, NFKC))
          like ('%' || escaped_query || '%') escape E'\\'
      )
      or pg_catalog.lower(normalize(posts.body, NFKC))
        like ('%' || escaped_query || '%') escape E'\\'
    )
    and (
      before_created_at is null
      or posts.created_at < before_created_at
      or (
        posts.created_at = before_created_at
        and posts.id < before_id
      )
    )
  order by posts.created_at desc, posts.id desc
  limit 21;
end;
$function$;

alter function public.my_diary_search_posts(text, timestamptz, uuid)
  owner to postgres;
revoke all on function public.my_diary_search_posts(text, timestamptz, uuid)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function public.my_diary_search_posts(text, timestamptz, uuid)
  to authenticated;

do $postcondition$
declare
  post_search_oid oid;
begin
  select function.oid
  into post_search_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_search_posts'
    and function.pronargs = 3
    and function.proargtypes = '25 1184 2950'::pg_catalog.oidvector
    and function.prorettype = 'record'::pg_catalog.regtype
    and function.proallargtypes = array[
      'text'::pg_catalog.regtype,
      'timestamptz'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'timestamptz'::pg_catalog.regtype
    ]::oid[]
    and function.proargmodes = array['i', 'i', 'i', 't', 't']::"char"[]
    and function.proargnames = array[
      'search_query', 'before_created_at', 'before_id', 'id', 'created_at'
    ]::text[]
    and language.lanname = 'plpgsql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and not function.prosecdef
    and function.provolatile = 's'
    and function.proconfig = array['search_path=""']::text[];

  if post_search_oid is null or (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_posts'
  ) <> 1 then
    raise exception
      'add_post_search postcondition failed: function contract differs';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated', post_search_oid, 'EXECUTE'
  ) or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as denied(role_name)
    where pg_catalog.has_function_privilege(
      denied.role_name, post_search_oid, 'EXECUTE'
    )
  ) or exists (
    select 1
    from pg_catalog.pg_proc as function
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where function.oid = post_search_oid
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'add_post_search postcondition failed: function ACL differs';
  end if;

  if not (
    select relation.relrowsecurity and not relation.relforcerowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.posts'::pg_catalog.regclass
  ) or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and cmd = 'SELECT'
  ) <> 1 or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.posts', 'SELECT'
  ) or pg_catalog.has_table_privilege(
    'anon', 'public.posts', 'SELECT'
  ) then
    raise exception
      'add_post_search postcondition failed: posts RLS or ACL differs';
  end if;
end;
$postcondition$;

commit;
