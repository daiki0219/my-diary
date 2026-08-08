begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('public.post_images') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null
     or pg_catalog.to_regclass('storage.buckets') is null
     or pg_catalog.to_regclass('storage.objects') is null then
    raise exception
      'integrate_post_image_uploads preflight failed: required objects are missing';
  end if;

  if (
    select count(*)
    from storage.buckets
    where id = 'post-images'
      and name = 'post-images'
      and public is false
      and file_size_limit is null
      and allowed_mime_types is null
  ) <> 1 then
    raise exception
      'integrate_post_image_uploads preflight failed: bucket differs';
  end if;

  if pg_catalog.to_regprocedure(
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
  ) is not null or pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_post_image_path_is_referenced(text)'
  ) is not null then
    raise exception
      'integrate_post_image_uploads preflight failed: function already exists';
  end if;

  if pg_catalog.to_regprocedure('storage.allow_only_operation(text)') is null
     or pg_catalog.to_regprocedure('storage.allow_any_operation(text[])') is null then
    raise exception
      'integrate_post_image_uploads preflight failed: Storage operation helpers are missing';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_post_images_storage_guard_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'RESTRICTIVE'
  ) <> 1 or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_select_owned_orphan',
        'my_diary_post_images_storage_insert_owned_namespace',
        'my_diary_post_images_storage_guard_insert_authenticated',
        'my_diary_post_images_storage_delete_owned_orphan',
        'my_diary_post_images_storage_guard_delete_authenticated'
      )
  ) then
    raise exception
      'integrate_post_image_uploads preflight failed: Storage policies differ';
  end if;
end;
$preflight$;

create function my_diary_private.my_diary_post_image_path_is_referenced(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.post_images
    where post_images.storage_path = p_storage_path
  );
$function$;

alter function
  my_diary_private.my_diary_post_image_path_is_referenced(text)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_post_image_path_is_referenced(text)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  my_diary_private.my_diary_post_image_path_is_referenced(text)
  to authenticated;

update storage.buckets
set file_size_limit = 6291456,
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp'
    ]::text[]
where id = 'post-images';

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

create policy my_diary_post_images_storage_select_owned_orphan
on storage.objects
for select
to authenticated
using (
  bucket_id = 'post-images'
  and auth.uid() is not null
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

create policy my_diary_post_images_storage_insert_owned_namespace
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'post-images'
  and auth.uid() is not null
  and storage.allow_only_operation('storage.object.upload')
  and owner_id = auth.uid()::text
  and name ~ (
    '^' || auth.uid()::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
  and my_diary_private.my_diary_is_account_active(auth.uid())
);

create policy my_diary_post_images_storage_guard_insert_authenticated
on storage.objects
as restrictive
for insert
to authenticated
with check (
  bucket_id <> 'post-images'
  or (
    auth.uid() is not null
    and storage.allow_only_operation('storage.object.upload')
    and owner_id = auth.uid()::text
    and name ~ (
      '^' || auth.uid()::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
    and my_diary_private.my_diary_is_account_active(auth.uid())
  )
);

create policy my_diary_post_images_storage_delete_owned_orphan
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'post-images'
  and auth.uid() is not null
  and storage.allow_only_operation('storage.object.delete_many')
  and owner_id = auth.uid()::text
  and name ~ (
    '^' || auth.uid()::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
  and not my_diary_private.my_diary_post_image_path_is_referenced(name)
);

create policy my_diary_post_images_storage_guard_delete_authenticated
on storage.objects
as restrictive
for delete
to authenticated
using (
  bucket_id <> 'post-images'
  or (
    auth.uid() is not null
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

create function public.my_diary_create_post_with_images(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
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
  v_title text;
  v_body text;
  v_mood text;
  v_visibility text;
  v_raw_tags text[] := coalesce(p_tags, array[]::text[]);
  v_canonical_tags text[] := array[]::text[];
  v_image_paths text[] := coalesce(p_image_paths, array[]::text[]);
  v_raw_tag text;
  v_canonical_tag text;
  v_tag_id uuid;
  v_image_path text;
  v_path_pattern text;
  v_locked_image_count integer;
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

  v_title := nullif(
    pg_catalog.regexp_replace(
      p_title,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );
  v_body := pg_catalog.regexp_replace(
    p_body,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  v_mood := nullif(pg_catalog.btrim(p_mood), '');
  v_visibility := pg_catalog.btrim(p_visibility);

  if p_post_id is null
     or (v_title is not null and pg_catalog.char_length(v_title) > 120)
     or v_body is null
     or pg_catalog.char_length(v_body) not between 1 and 10000
     or (v_mood is not null and v_mood not in (
       'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
     ))
     or v_visibility is null
     or v_visibility not in ('private', 'followers', 'public') then
    raise exception using
      errcode = '22023',
      message = 'Invalid post input.';
  end if;

  if pg_catalog.cardinality(v_raw_tags) > 20
     or (
       pg_catalog.cardinality(v_raw_tags) > 0
       and pg_catalog.array_ndims(v_raw_tags) <> 1
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  foreach v_raw_tag in array v_raw_tags loop
    if v_raw_tag is null then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    v_canonical_tag :=
      my_diary_private.my_diary_normalize_tag_name(v_raw_tag);

    if v_canonical_tag is null
       or pg_catalog.char_length(v_canonical_tag) not between 1 and 30
       or pg_catalog.strpos(v_canonical_tag, ',') > 0
       or pg_catalog.strpos(v_canonical_tag, '#') > 0
       or v_canonical_tag ~ '[[:cntrl:]]' then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    if not (v_canonical_tag = any(v_canonical_tags)) then
      v_canonical_tags := pg_catalog.array_append(
        v_canonical_tags,
        v_canonical_tag
      );
    end if;
  end loop;

  select coalesce(
    pg_catalog.array_agg(tag_name order by tag_name),
    array[]::text[]
  )
  into v_canonical_tags
  from pg_catalog.unnest(v_canonical_tags) as canonical(tag_name);

  if pg_catalog.cardinality(v_canonical_tags) > 5 then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  if pg_catalog.cardinality(v_image_paths) > 10
     or (
       pg_catalog.cardinality(v_image_paths) > 0
       and pg_catalog.array_ndims(v_image_paths) <> 1
     )
     or (
       select pg_catalog.count(*) <> pg_catalog.count(distinct image_path)
       from pg_catalog.unnest(v_image_paths) as images(image_path)
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  v_path_pattern :=
    '^' || v_user_id::text || '/' || p_post_id::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  foreach v_image_path in array v_image_paths loop
    if v_image_path is null
       or pg_catalog.char_length(v_image_path) not between 1 and 1024
       or v_image_path !~ v_path_pattern then
      raise exception using
        errcode = '22023',
        message = 'Invalid post image input.';
    end if;
  end loop;

  perform 1
  from storage.objects
  where bucket_id = 'post-images'
    and name = any(v_image_paths)
    and owner_id = v_user_id::text
    and metadata ->> 'mimetype' in (
      'image/jpeg',
      'image/png',
      'image/webp'
    )
    and case
      when metadata ->> 'size' ~ '^[0-9]+$'
      then (metadata ->> 'size')::numeric between 1 and 6291456
      else false
    end
  for update;

  get diagnostics v_locked_image_count = row_count;

  if v_locked_image_count <> pg_catalog.cardinality(v_image_paths) then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  insert into public.posts (
    id,
    user_id,
    title,
    body,
    mood,
    visibility
  )
  values (
    p_post_id,
    v_user_id,
    v_title,
    v_body,
    v_mood,
    v_visibility
  );

  foreach v_canonical_tag in array v_canonical_tags loop
    insert into public.tags (name, normalized_name)
    values (v_canonical_tag, v_canonical_tag)
    on conflict (normalized_name) do nothing;

    select id
    into v_tag_id
    from public.tags
    where normalized_name = v_canonical_tag;

    if v_tag_id is null then
      raise exception using
        errcode = '40001',
        message = 'Tag resolution must be retried.';
    end if;

    insert into public.post_tags (post_id, tag_id)
    values (p_post_id, v_tag_id);
  end loop;

  insert into public.post_images (post_id, storage_path, sort_order)
  select
    p_post_id,
    image_path,
    ordinality::integer - 1
  from pg_catalog.unnest(v_image_paths) with ordinality
    as images(image_path, ordinality);

  return p_post_id;
end;
$function$;

alter function public.my_diary_create_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  text[]
) owner to postgres;

comment on function public.my_diary_create_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  text[]
) is 'Atomically creates an owned post, canonical tags, and ordered image metadata.';

revoke all on function public.my_diary_create_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  text[]
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  text[]
) to authenticated;

do $postcondition$
declare
  create_oid oid;
begin
  if (
    select count(*)
    from storage.buckets
    where id = 'post-images'
      and name = 'post-images'
      and public is false
      and file_size_limit = 6291456
      and allowed_mime_types = array[
        'image/jpeg',
        'image/png',
        'image/webp'
      ]::text[]
  ) <> 1 then
    raise exception
      'integrate_post_image_uploads postcondition failed: bucket differs';
  end if;

  select function.oid
  into create_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_create_post_with_images'
    and function.proargtypes =
      '2950 25 25 25 25 1009 1009'::oidvector
    and function.proargnames = array[
      'p_post_id',
      'p_title',
      'p_body',
      'p_mood',
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

  if create_oid is null
     or pg_catalog.obj_description(create_oid, 'pg_proc') is null then
    raise exception
      'integrate_post_image_uploads postcondition failed: RPC differs';
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
    where function.oid = create_oid
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  )
     or pg_catalog.has_function_privilege('anon', create_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       'authenticated', create_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', create_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', create_oid, 'EXECUTE'
     ) then
    raise exception
      'integrate_post_image_uploads postcondition failed: RPC ACL differs';
  end if;

  if pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_post_image_path_is_referenced(text)'
     ) is null
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'my_diary_private.my_diary_post_image_path_is_referenced(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'my_diary_private.my_diary_post_image_path_is_referenced(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'my_diary_private.my_diary_post_image_path_is_referenced(text)',
       'EXECUTE'
     ) then
    raise exception
      'integrate_post_image_uploads postcondition failed: helper differs';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_select_visible_post',
        'my_diary_post_images_storage_guard_authenticated',
        'my_diary_post_images_storage_guard_anon',
        'my_diary_post_images_storage_select_owned_orphan',
        'my_diary_post_images_storage_insert_owned_namespace',
        'my_diary_post_images_storage_guard_insert_authenticated',
        'my_diary_post_images_storage_delete_owned_orphan',
        'my_diary_post_images_storage_guard_delete_authenticated'
      )
  ) <> 8 or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ) then
    raise exception
      'integrate_post_image_uploads postcondition failed: Storage policies differ';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.post_images', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'public.post_images', 'SELECT, INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'service_role', 'public.post_images', 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'integrate_post_image_uploads postcondition failed: table ACL differs';
  end if;
end;
$postcondition$;

commit;
