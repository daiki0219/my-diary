begin;

do $preflight$
declare
  profile_search_oid oid;
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null then
    raise exception
      'extend_user_and_tag_search preflight failed: required objects are missing';
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
      'extend_user_and_tag_search preflight failed: a required role is missing';
  end if;

  select function.oid
  into profile_search_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_search_profiles'
    and function.pronargs = 1
    and function.proargtypes = '25'::pg_catalog.oidvector
    and function.proallargtypes = array[
      'text'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'text'::pg_catalog.regtype,
      'text'::pg_catalog.regtype
    ]::oid[]
    and function.proargmodes = array['i', 't', 't', 't']::"char"[]
    and function.proargnames = array[
      'search_query', 'user_id', 'username', 'bio'
    ]::text[]
    and language.lanname = 'plpgsql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.prosecdef
    and function.provolatile = 's'
    and function.proconfig = array['search_path=""']::text[];

  if profile_search_oid is null or (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
  ) <> 1 then
    raise exception
      'extend_user_and_tag_search preflight failed: profile search contract differs';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where (
      namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_search_query'
    ) or (
      namespace.nspname = 'public'
      and function.proname = 'my_diary_search_tags'
    )
  ) then
    raise exception
      'extend_user_and_tag_search preflight failed: a new function name exists';
  end if;

  if not (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.tags'::pg_catalog.regclass
  ) or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'tags'
      and policyname = 'my_diary_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) then
    raise exception
      'extend_user_and_tag_search preflight failed: tags RLS differs';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated', profile_search_oid, 'EXECUTE'
  ) or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as denied(role_name)
    where pg_catalog.has_function_privilege(
      denied.role_name, profile_search_oid, 'EXECUTE'
    )
  ) then
    raise exception
      'extend_user_and_tag_search preflight failed: profile search ACL differs';
  end if;
end;
$preflight$;

create or replace function public.my_diary_search_profiles(search_query text)
returns table (
  user_id uuid,
  username text,
  bio text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  normalized_query text;
  escaped_query text;
begin
  if auth.uid() is null then
    raise insufficient_privilege;
  end if;

  normalized_query := pg_catalog.btrim(
    pg_catalog.normalize(search_query, 'NFKC')
  );

  if normalized_query is null
    or pg_catalog.char_length(normalized_query) not between 1 and 50
  then
    raise invalid_parameter_value;
  end if;

  escaped_query := pg_catalog.replace(normalized_query, E'\\', E'\\\\');
  escaped_query := pg_catalog.replace(escaped_query, '%', E'\\%');
  escaped_query := pg_catalog.replace(escaped_query, '_', E'\\_');

  return query
  select
    profiles.user_id,
    profiles.username,
    profiles.bio
  from public.profiles
  join public.accounts
    on accounts.user_id = profiles.user_id
  where (
      accounts.status = 'active'
      or profiles.user_id = auth.uid()
    )
    and pg_catalog.normalize(profiles.username, 'NFKC')
      ilike ('%' || escaped_query || '%') escape E'\\'
  order by
    pg_catalog.lower(profiles.username) asc,
    profiles.username asc,
    profiles.user_id asc
  limit 20;
end;
$function$;

alter function public.my_diary_search_profiles(text) owner to postgres;
revoke all on function public.my_diary_search_profiles(text)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function public.my_diary_search_profiles(text)
  to authenticated;

create function my_diary_private.my_diary_normalize_tag_search_query(
  raw_query text
)
returns text
language sql
immutable
strict
parallel safe
security invoker
set search_path = ''
as $function$
  select pg_catalog.translate(
    pg_catalog.regexp_replace(
      pg_catalog.btrim(
        pg_catalog.regexp_replace(
          pg_catalog.btrim(pg_catalog.normalize(raw_query, 'NFKC')),
          '^#+',
          ''
        )
      ),
      ' +',
      ' ',
      'g'
    ),
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'abcdefghijklmnopqrstuvwxyz'
  );
$function$;

alter function
  my_diary_private.my_diary_normalize_tag_search_query(text)
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_normalize_tag_search_query(text)
  from public, anon, authenticated, service_role, authenticator;

create function public.my_diary_search_tags(
  search_query text,
  after_normalized_name text
)
returns table (
  id uuid,
  name text,
  normalized_name text
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  canonical_query text;
  canonical_cursor text;
  escaped_query text;
begin
  if auth.uid() is null then
    raise insufficient_privilege;
  end if;

  if search_query is null then
    raise invalid_parameter_value;
  end if;

  -- Keep this expression aligned with the private helper. The RPC is
  -- SECURITY INVOKER, while the helper intentionally is not executable by
  -- application roles.
  canonical_query := pg_catalog.translate(
    pg_catalog.regexp_replace(
      pg_catalog.btrim(
        pg_catalog.regexp_replace(
          pg_catalog.btrim(pg_catalog.normalize(search_query, 'NFKC')),
          '^#+',
          ''
        )
      ),
      ' +',
      ' ',
      'g'
    ),
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'abcdefghijklmnopqrstuvwxyz'
  );

  if pg_catalog.char_length(canonical_query) not between 1 and 30
     or pg_catalog.strpos(canonical_query, ',') > 0
     or pg_catalog.strpos(canonical_query, '#') > 0
     or canonical_query ~ '[[:cntrl:]]' then
    raise invalid_parameter_value;
  end if;

  if after_normalized_name is not null then
    canonical_cursor := pg_catalog.translate(
      pg_catalog.regexp_replace(
        pg_catalog.btrim(
          pg_catalog.regexp_replace(
            pg_catalog.btrim(
              pg_catalog.normalize(after_normalized_name, 'NFKC')
            ),
            '^#+',
            ''
          )
        ),
        ' +',
        ' ',
        'g'
      ),
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'abcdefghijklmnopqrstuvwxyz'
    );

    if pg_catalog.char_length(after_normalized_name) not between 1 and 30
       or pg_catalog.strpos(after_normalized_name, ',') > 0
       or pg_catalog.strpos(after_normalized_name, '#') > 0
       or after_normalized_name ~ '[[:cntrl:]]'
       or after_normalized_name <> canonical_cursor then
      raise invalid_parameter_value;
    end if;
  end if;

  escaped_query := pg_catalog.replace(canonical_query, E'\\', E'\\\\');
  escaped_query := pg_catalog.replace(escaped_query, '%', E'\\%');
  escaped_query := pg_catalog.replace(escaped_query, '_', E'\\_');

  return query
  select
    tags.id,
    tags.name,
    tags.normalized_name
  from public.tags
  where tags.normalized_name
      ilike ('%' || escaped_query || '%') escape E'\\'
    and (
      after_normalized_name is null
      or tags.normalized_name > after_normalized_name
    )
  order by tags.normalized_name asc
  limit 21;
end;
$function$;

alter function public.my_diary_search_tags(text, text) owner to postgres;
revoke all on function public.my_diary_search_tags(text, text)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function public.my_diary_search_tags(text, text)
  to authenticated;

do $postcondition$
declare
  profile_search_oid oid;
  tag_normalizer_oid oid;
  tag_search_oid oid;
begin
  select function.oid
  into profile_search_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_search_profiles'
    and function.pronargs = 1
    and function.proargtypes = '25'::pg_catalog.oidvector
    and function.proallargtypes = array[
      'text'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'text'::pg_catalog.regtype,
      'text'::pg_catalog.regtype
    ]::oid[]
    and function.proargmodes = array['i', 't', 't', 't']::"char"[]
    and function.proargnames = array[
      'search_query', 'user_id', 'username', 'bio'
    ]::text[]
    and language.lanname = 'plpgsql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.prosecdef
    and function.provolatile = 's'
    and function.proconfig = array['search_path=""']::text[];

  select function.oid
  into tag_normalizer_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'my_diary_private'
    and function.proname = 'my_diary_normalize_tag_search_query'
    and function.pronargs = 1
    and function.proargtypes = '25'::pg_catalog.oidvector
    and function.prorettype = 'text'::pg_catalog.regtype
    and language.lanname = 'sql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and not function.prosecdef
    and function.provolatile = 'i'
    and function.proisstrict
    and function.proparallel = 's'
    and function.proconfig = array['search_path=""']::text[];

  select function.oid
  into tag_search_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_search_tags'
    and function.pronargs = 2
    and function.proargtypes = '25 25'::pg_catalog.oidvector
    and function.proallargtypes = array[
      'text'::pg_catalog.regtype,
      'text'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'text'::pg_catalog.regtype,
      'text'::pg_catalog.regtype
    ]::oid[]
    and function.proargmodes = array['i', 'i', 't', 't', 't']::"char"[]
    and function.proargnames = array[
      'search_query', 'after_normalized_name',
      'id', 'name', 'normalized_name'
    ]::text[]
    and language.lanname = 'plpgsql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and not function.prosecdef
    and function.provolatile = 's'
    and function.proconfig = array['search_path=""']::text[];

  if profile_search_oid is null or tag_normalizer_oid is null
     or tag_search_oid is null then
    raise exception
      'extend_user_and_tag_search postcondition failed: function contract differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_search_query'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_tags'
  ) <> 1 then
    raise exception
      'extend_user_and_tag_search postcondition failed: unexpected overload';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated', profile_search_oid, 'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated', tag_search_oid, 'EXECUTE'
  ) or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as denied(role_name)
    where pg_catalog.has_function_privilege(
      denied.role_name, profile_search_oid, 'EXECUTE'
    ) or pg_catalog.has_function_privilege(
      denied.role_name, tag_search_oid, 'EXECUTE'
    ) or pg_catalog.has_function_privilege(
      denied.role_name, tag_normalizer_oid, 'EXECUTE'
    )
  ) or pg_catalog.has_function_privilege(
    'authenticated', tag_normalizer_oid, 'EXECUTE'
  ) then
    raise exception
      'extend_user_and_tag_search postcondition failed: ACL differs';
  end if;

  if not (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.tags'::pg_catalog.regclass
  ) or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'tags'
      and policyname = 'my_diary_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) then
    raise exception
      'extend_user_and_tag_search postcondition failed: tags RLS differs';
  end if;
end;
$postcondition$;

commit;
