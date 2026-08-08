begin;

do $preflight$
declare
  can_view_post_oid oid;
  profile_search_oid oid;
begin
  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null then
    raise exception
      'fail_close_non_active_accounts preflight failed: required objects are missing';
  end if;

  if (
    select pg_catalog.pg_get_constraintdef(constraint_definition.oid)
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid =
        'public.accounts'::pg_catalog.regclass
      and constraint_definition.conname =
        'my_diary_accounts_status_check'
      and constraint_definition.contype = 'c'
  ) is distinct from $$CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'deactivated'::text])))$$ then
    raise exception
      'fail_close_non_active_accounts preflight failed: account statuses differ';
  end if;

  select function_definition.oid
  into can_view_post_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'my_diary_private'
    and function_definition.proname = 'my_diary_can_view_post'
    and function_definition.proargtypes = '2950 25 1184'::oidvector
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and function_definition.prokind = 'f'
    and language.lanname = 'sql'
    and function_definition.prosecdef
    and function_definition.provolatile = 's'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if can_view_post_oid is null or (
    select count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_can_view_post'
  ) <> 1 then
    raise exception
      'fail_close_non_active_accounts preflight failed: post visibility helper differs';
  end if;

  select function_definition.oid
  into profile_search_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'public'
    and function_definition.proname = 'my_diary_search_profiles'
    and function_definition.proargtypes = '25'::oidvector
    and function_definition.prorettype = 'record'::pg_catalog.regtype
    and function_definition.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function_definition.prosecdef
    and function_definition.provolatile = 's'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if profile_search_oid is null or (
    select count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname = 'my_diary_search_profiles'
  ) <> 1 then
    raise exception
      'fail_close_non_active_accounts preflight failed: profile search differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', can_view_post_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', profile_search_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', can_view_post_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', profile_search_oid, 'EXECUTE'
     ) then
    raise exception
      'fail_close_non_active_accounts preflight failed: function ACL differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'my_diary_profiles_select_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 1 then
    raise exception
      'fail_close_non_active_accounts preflight failed: core SELECT policies differ';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_guard_authenticated',
        'my_diary_post_images_storage_select_owned_orphan',
        'my_diary_post_images_storage_delete_owned_orphan',
        'my_diary_post_images_storage_guard_delete_authenticated'
      )
      and roles = array['authenticated']::name[]
      and (
        (
          policyname in (
            'my_diary_post_images_storage_guard_authenticated',
            'my_diary_post_images_storage_select_owned_orphan'
          )
          and cmd = 'SELECT'
        )
        or (
          policyname in (
            'my_diary_post_images_storage_delete_owned_orphan',
            'my_diary_post_images_storage_guard_delete_authenticated'
          )
          and cmd = 'DELETE'
        )
      )
  ) <> 4 then
    raise exception
      'fail_close_non_active_accounts preflight failed: Storage policies differ';
  end if;
end;
$preflight$;

create or replace function my_diary_private.my_diary_can_view_post(
  post_user_id uuid,
  post_visibility text,
  post_deleted_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    post_deleted_at is null
    and my_diary_private.my_diary_is_account_active(auth.uid())
    and (
      post_user_id = auth.uid()
      or (
        my_diary_private.my_diary_is_account_active(post_user_id)
        and (
          post_visibility = 'public'
          or (
            post_visibility = 'followers'
            and exists (
              select 1
              from public.follows
              where follows.follower_id = auth.uid()
                and follows.following_id = post_user_id
            )
          )
        )
      )
    );
$function$;

alter function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  owner to postgres;
revoke all on function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  to authenticated;

drop policy my_diary_profiles_select_authenticated on public.profiles;

create policy my_diary_profiles_select_authenticated
on public.profiles
for select
to authenticated
using (
  my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(profiles.user_id)
);

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
  if auth.uid() is null
     or not my_diary_private.my_diary_is_account_active(auth.uid()) then
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
  where accounts.status = 'active'
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

drop policy my_diary_post_images_storage_guard_authenticated
on storage.objects;

create policy my_diary_post_images_storage_guard_authenticated
on storage.objects
as restrictive
for select
to authenticated
using (
  bucket_id <> 'post-images'
  or exists (
    select 1
    from public.post_images
    where post_images.storage_path = objects.name
  )
  or (
    auth.uid() is not null
    and my_diary_private.my_diary_is_account_active(auth.uid())
    and storage.allow_any_operation(array[
      'storage.object.upload',
      'storage.object.delete_many'
    ])
    and owner_id = auth.uid()::text
    and name ~ (
      '^' || auth.uid()::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
    and not my_diary_private.my_diary_post_image_path_is_referenced(name)
  )
);

drop policy my_diary_post_images_storage_select_owned_orphan
on storage.objects;

create policy my_diary_post_images_storage_select_owned_orphan
on storage.objects
for select
to authenticated
using (
  bucket_id = 'post-images'
  and auth.uid() is not null
  and my_diary_private.my_diary_is_account_active(auth.uid())
  and storage.allow_any_operation(array[
    'storage.object.upload',
    'storage.object.delete_many'
  ])
  and owner_id = auth.uid()::text
  and name ~ (
    '^' || auth.uid()::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
  and not my_diary_private.my_diary_post_image_path_is_referenced(name)
);

drop policy my_diary_post_images_storage_delete_owned_orphan
on storage.objects;

create policy my_diary_post_images_storage_delete_owned_orphan
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'post-images'
  and auth.uid() is not null
  and my_diary_private.my_diary_is_account_active(auth.uid())
  and storage.allow_only_operation('storage.object.delete_many')
  and owner_id = auth.uid()::text
  and name ~ (
    '^' || auth.uid()::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
  and not my_diary_private.my_diary_post_image_path_is_referenced(name)
);

drop policy my_diary_post_images_storage_guard_delete_authenticated
on storage.objects;

create policy my_diary_post_images_storage_guard_delete_authenticated
on storage.objects
as restrictive
for delete
to authenticated
using (
  bucket_id <> 'post-images'
  or (
    auth.uid() is not null
    and my_diary_private.my_diary_is_account_active(auth.uid())
    and storage.allow_only_operation('storage.object.delete_many')
    and owner_id = auth.uid()::text
    and name ~ (
      '^' || auth.uid()::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
    and not my_diary_private.my_diary_post_image_path_is_referenced(name)
  )
);

do $postcondition$
declare
  can_view_post_oid oid;
  profile_search_oid oid;
begin
  select function_definition.oid
  into can_view_post_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'my_diary_private'
    and function_definition.proname = 'my_diary_can_view_post'
    and function_definition.proargtypes = '2950 25 1184'::oidvector
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and language.lanname = 'sql'
    and function_definition.prosecdef
    and function_definition.provolatile = 's'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      like '%my_diary_is_account_active(auth.uid())%';

  select function_definition.oid
  into profile_search_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'public'
    and function_definition.proname = 'my_diary_search_profiles'
    and function_definition.proargtypes = '25'::oidvector
    and function_definition.prorettype = 'record'::pg_catalog.regtype
    and function_definition.proallargtypes = array[
      'text'::pg_catalog.regtype,
      'uuid'::pg_catalog.regtype,
      'text'::pg_catalog.regtype,
      'text'::pg_catalog.regtype
    ]::oid[]
    and function_definition.proargmodes = array['i', 't', 't', 't']::"char"[]
    and function_definition.proargnames = array[
      'search_query', 'user_id', 'username', 'bio'
    ]::text[]
    and language.lanname = 'plpgsql'
    and function_definition.prosecdef
    and function_definition.provolatile = 's'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      like '%my_diary_is_account_active(auth.uid())%'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      not like '%profiles.user_id = auth.uid()%';

  if can_view_post_oid is null or profile_search_oid is null then
    raise exception
      'fail_close_non_active_accounts postcondition failed: function attributes differ';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', can_view_post_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', profile_search_oid, 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       where pg_catalog.has_function_privilege(
         denied.role_name, can_view_post_oid, 'EXECUTE'
       )
         or pg_catalog.has_function_privilege(
           denied.role_name, profile_search_oid, 'EXECUTE'
         )
     ) then
    raise exception
      'fail_close_non_active_accounts postcondition failed: function ACL differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'my_diary_profiles_select_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_is_account_active%'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_can_view_post%'
  ) <> 1 then
    raise exception
      'fail_close_non_active_accounts postcondition failed: core SELECT policies differ';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_guard_authenticated',
        'my_diary_post_images_storage_select_owned_orphan',
        'my_diary_post_images_storage_delete_owned_orphan',
        'my_diary_post_images_storage_guard_delete_authenticated'
      )
      and roles = array['authenticated']::name[]
      and coalesce(qual, '') like '%my_diary_is_account_active%'
  ) <> 4 then
    raise exception
      'fail_close_non_active_accounts postcondition failed: Storage policies are not active-gated';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.accounts', 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'status', 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'timezone', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'status', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'public.accounts', 'SELECT'
     ) then
    raise exception
      'fail_close_non_active_accounts postcondition failed: accounts minimal path or ACL differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'my_diary_accounts_select_own'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'my_diary_accounts_update_own_timezone'
      and cmd = 'UPDATE'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_is_account_active%'
      and with_check like '%my_diary_is_account_active%'
  ) <> 1 then
    raise exception
      'fail_close_non_active_accounts postcondition failed: accounts RLS differs';
  end if;
end;
$postcondition$;

commit;
