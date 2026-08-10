begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('public.post_images') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null then
    raise exception
      'add_location_name_atomic_mutation preflight failed: required tables are missing';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'
     ) is null then
    raise exception
      'add_location_name_atomic_mutation preflight failed: predecessor RPC is missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_images_and_location',
        'my_diary_update_post_with_images_and_location'
      )
  ) then
    raise exception
      'add_location_name_atomic_mutation preflight failed: successor RPC already exists';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.posts'::pg_catalog.regclass
      and attribute.attname = 'location_name'
      and attribute.atttypid = 'text'::pg_catalog.regtype
      and attribute.attnum > 0
      and not attribute.attisdropped
      and not attribute.attnotnull
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.posts'::pg_catalog.regclass
      and conname = 'my_diary_posts_location_name_check'
      and contype = 'c'
      and convalidated
  ) then
    raise exception
      'add_location_name_atomic_mutation preflight failed: location_name schema differs';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.posts', 'INSERT, UPDATE'
     ) then
    raise exception
      'add_location_name_atomic_mutation preflight failed: direct posts mutation is open';
  end if;
end;
$preflight$;

create function public.my_diary_create_post_with_images_and_location(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_visibility text,
  p_tags text[],
  p_image_paths text[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_location_name text;
  v_post_id uuid;
  v_updated_count integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null or not exists (
    select 1
    from public.accounts
    where user_id = v_user_id
      and status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  v_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );

  if v_location_name is not null
     and pg_catalog.char_length(v_location_name) > 100 then
    raise exception using
      errcode = '22023',
      message = 'Invalid location name.';
  end if;

  v_post_id := public.my_diary_create_post_with_images(
    p_post_id,
    p_title,
    p_body,
    p_mood,
    p_visibility,
    p_tags,
    p_image_paths
  );

  update public.posts
  set location_name = v_location_name
  where id = v_post_id
    and user_id = v_user_id
    and deleted_at is null;

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> 1 then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  return v_post_id;
end;
$function$;

create function public.my_diary_update_post_with_images_and_location(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_visibility text,
  p_tags text[],
  p_image_manifest jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_location_name text;
  v_result jsonb;
  v_updated_count integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null or not exists (
    select 1
    from public.accounts
    where user_id = v_user_id
      and status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  v_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );

  if v_location_name is not null
     and pg_catalog.char_length(v_location_name) > 100 then
    raise exception using
      errcode = '22023',
      message = 'Invalid location name.';
  end if;

  v_result := public.my_diary_update_post_with_images(
    p_post_id,
    p_title,
    p_body,
    p_mood,
    p_visibility,
    p_tags,
    p_image_manifest
  );

  update public.posts
  set location_name = v_location_name
  where id = p_post_id
    and user_id = v_user_id
    and deleted_at is null;

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> 1 then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  return v_result;
end;
$function$;

alter function public.my_diary_create_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text[]
) owner to postgres;

alter function public.my_diary_update_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) owner to postgres;

comment on function public.my_diary_create_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text[]
) is 'Atomically creates an owned post, location name, canonical tags, and ordered image metadata.';

comment on function public.my_diary_update_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) is 'Atomically updates an owned post, location name, canonical tags, and its final ordered image manifest.';

revoke all on function public.my_diary_create_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text[]
) from public, anon, authenticated, service_role, authenticator;

revoke all on function public.my_diary_update_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text[]
) to authenticated;

grant execute on function public.my_diary_update_post_with_images_and_location(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) to authenticated;

do $postcondition$
declare
  create_oid oid;
  update_oid oid;
begin
  select function.oid
  into create_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname =
      'my_diary_create_post_with_images_and_location'
    and function.proargtypes =
      '2950 25 25 25 25 25 1009 1009'::oidvector
    and function.proargnames = array[
      'p_post_id',
      'p_title',
      'p_body',
      'p_mood',
      'p_location_name',
      'p_visibility',
      'p_tags',
      'p_image_paths'
    ]::text[]
    and function.prorettype = 'uuid'::pg_catalog.regtype
    and function.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function.provolatile = 'v'
    and function.prosecdef
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.proconfig = array['search_path=""']::text[];

  select function.oid
  into update_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname =
      'my_diary_update_post_with_images_and_location'
    and function.proargtypes =
      '2950 25 25 25 25 25 1009 3802'::oidvector
    and function.proargnames = array[
      'p_post_id',
      'p_title',
      'p_body',
      'p_mood',
      'p_location_name',
      'p_visibility',
      'p_tags',
      'p_image_manifest'
    ]::text[]
    and function.prorettype = 'jsonb'::pg_catalog.regtype
    and function.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function.provolatile = 'v'
    and function.prosecdef
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.proconfig = array['search_path=""']::text[];

  if create_oid is null
     or update_oid is null
     or pg_catalog.obj_description(create_oid, 'pg_proc') is null
     or pg_catalog.obj_description(update_oid, 'pg_proc') is null then
    raise exception
      'add_location_name_atomic_mutation postcondition failed: successor RPC differs';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_images_and_location',
        'my_diary_update_post_with_images_and_location'
      )
      and function.oid not in (create_oid, update_oid)
  ) then
    raise exception
      'add_location_name_atomic_mutation postcondition failed: unexpected overload exists';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where function.oid in (create_oid, update_oid)
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  )
     or pg_catalog.has_function_privilege('anon', create_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', update_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       'authenticated', create_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', update_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', create_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', update_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', create_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', update_oid, 'EXECUTE'
     ) then
    raise exception
      'add_location_name_atomic_mutation postcondition failed: successor RPC ACL differs';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'
     ) is null
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.posts', 'INSERT, UPDATE'
     )
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'posts'
     ) <> 3
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_trigger
       where tgrelid = 'public.posts'::pg_catalog.regclass
         and not tgisinternal
     ) <> 1 then
    raise exception
      'add_location_name_atomic_mutation postcondition failed: existing mutation boundary differs';
  end if;
end;
$postcondition$;

commit;
