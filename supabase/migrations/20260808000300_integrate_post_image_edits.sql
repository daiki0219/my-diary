begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('public.post_images') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null
     or pg_catalog.to_regclass('storage.objects') is null then
    raise exception
      'integrate_post_image_edits preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regprocedure(
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'
  ) is not null then
    raise exception
      'integrate_post_image_edits preflight failed: function already exists';
  end if;

  if pg_catalog.to_regprocedure(
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])'
  ) is null or pg_catalog.to_regprocedure(
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
  ) is null then
    raise exception
      'integrate_post_image_edits preflight failed: predecessor RPC is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_post_sort_key'
      and contype = 'u'
      and condeferrable
      and not condeferred
  ) then
    raise exception
      'integrate_post_image_edits preflight failed: image order constraint differs';
  end if;
end;
$preflight$;

create function public.my_diary_update_post_with_images(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
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
  v_locked_post_id uuid;
  v_title text;
  v_body text;
  v_mood text;
  v_visibility text;
  v_raw_tags text[] := coalesce(p_tags, array[]::text[]);
  v_canonical_tags text[] := array[]::text[];
  v_tag_ids uuid[] := array[]::uuid[];
  v_retained_ids uuid[] := array[]::uuid[];
  v_new_paths text[] := array[]::text[];
  v_removed_paths text[] := array[]::text[];
  v_raw_tag text;
  v_canonical_tag text;
  v_tag_id uuid;
  v_manifest_item jsonb;
  v_manifest_index integer;
  v_existing_id_text text;
  v_existing_id uuid;
  v_new_path text;
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

  if p_image_manifest is null
     or pg_catalog.jsonb_typeof(p_image_manifest) <> 'array'
     or pg_catalog.jsonb_array_length(p_image_manifest) > 10 then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  v_path_pattern :=
    '^' || v_user_id::text || '/' || p_post_id::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  for v_manifest_item, v_manifest_index in
    select item, ordinality::integer - 1
    from pg_catalog.jsonb_array_elements(p_image_manifest)
      with ordinality as manifest(item, ordinality)
  loop
    if pg_catalog.jsonb_typeof(v_manifest_item) <> 'object'
       or (
         select pg_catalog.count(*)
         from pg_catalog.jsonb_object_keys(v_manifest_item)
       ) <> 1 then
      raise exception using
        errcode = '22023',
        message = 'Invalid post image input.';
    end if;

    if v_manifest_item ? 'existingId'
       and pg_catalog.jsonb_typeof(v_manifest_item -> 'existingId') = 'string' then
      v_existing_id_text := v_manifest_item ->> 'existingId';

      if v_existing_id_text !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or v_existing_id_text::uuid = any(v_retained_ids) then
        raise exception using
          errcode = '22023',
          message = 'Invalid post image input.';
      end if;

      v_retained_ids := pg_catalog.array_append(
        v_retained_ids,
        v_existing_id_text::uuid
      );
    elsif v_manifest_item ? 'newPath'
       and pg_catalog.jsonb_typeof(v_manifest_item -> 'newPath') = 'string' then
      v_new_path := v_manifest_item ->> 'newPath';

      if pg_catalog.char_length(v_new_path) not between 1 and 1024
         or v_new_path !~ v_path_pattern
         or v_new_path = any(v_new_paths) then
        raise exception using
          errcode = '22023',
          message = 'Invalid post image input.';
      end if;

      v_new_paths := pg_catalog.array_append(v_new_paths, v_new_path);
    else
      raise exception using
        errcode = '22023',
        message = 'Invalid post image input.';
    end if;
  end loop;

  select id
  into v_locked_post_id
  from public.posts
  where id = p_post_id
    and user_id = v_user_id
    and deleted_at is null
  for update;

  if v_locked_post_id is null then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  perform 1
  from public.post_images
  where post_id = v_locked_post_id
  for update;

  select pg_catalog.count(*)
  into v_locked_image_count
  from public.post_images
  where post_id = v_locked_post_id
    and id = any(v_retained_ids);

  if v_locked_image_count <> pg_catalog.cardinality(v_retained_ids) then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  if exists (
    select 1
    from public.post_images
    where storage_path = any(v_new_paths)
  ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  perform 1
  from storage.objects
  where bucket_id = 'post-images'
    and name = any(v_new_paths)
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

  if v_locked_image_count <> pg_catalog.cardinality(v_new_paths) then
    raise exception using
      errcode = '22023',
      message = 'Invalid post image input.';
  end if;

  select coalesce(
    pg_catalog.array_agg(storage_path order by sort_order),
    array[]::text[]
  )
  into v_removed_paths
  from public.post_images
  where post_id = v_locked_post_id
    and not (id = any(v_retained_ids));

  update public.posts
  set title = v_title,
      body = v_body,
      mood = v_mood,
      visibility = v_visibility
  where id = v_locked_post_id;

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

    v_tag_ids := pg_catalog.array_append(v_tag_ids, v_tag_id);
  end loop;

  delete from public.post_tags as existing
  where existing.post_id = v_locked_post_id
    and not (existing.tag_id = any(v_tag_ids));

  insert into public.post_tags (post_id, tag_id)
  select v_locked_post_id, desired.tag_id
  from pg_catalog.unnest(v_tag_ids) as desired(tag_id)
  where not exists (
    select 1
    from public.post_tags as existing
    where existing.post_id = v_locked_post_id
      and existing.tag_id = desired.tag_id
  );

  set constraints public.my_diary_post_images_post_sort_key deferred;

  for v_manifest_item, v_manifest_index in
    select item, ordinality::integer - 1
    from pg_catalog.jsonb_array_elements(p_image_manifest)
      with ordinality as manifest(item, ordinality)
  loop
    if v_manifest_item ? 'existingId' then
      update public.post_images
      set sort_order = v_manifest_index
      where id = (v_manifest_item ->> 'existingId')::uuid
        and post_id = v_locked_post_id;
    else
      insert into public.post_images (post_id, storage_path, sort_order)
      values (
        v_locked_post_id,
        v_manifest_item ->> 'newPath',
        v_manifest_index
      );
    end if;
  end loop;

  delete from public.post_images
  where post_id = v_locked_post_id
    and not (id = any(v_retained_ids))
    and not (storage_path = any(v_new_paths));

  return pg_catalog.jsonb_build_object(
    'postId', v_locked_post_id,
    'removedImagePaths', pg_catalog.to_jsonb(v_removed_paths)
  );
end;
$function$;

alter function public.my_diary_update_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) owner to postgres;

comment on function public.my_diary_update_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) is 'Atomically updates an owned post, canonical tags, and its final ordered image manifest.';

revoke all on function public.my_diary_update_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_update_post_with_images(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  jsonb
) to authenticated;

do $postcondition$
declare
  update_oid oid;
begin
  select function.oid
  into update_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_update_post_with_images'
    and function.proargtypes =
      '2950 25 25 25 25 1009 3802'::oidvector
    and function.proargnames = array[
      'p_post_id',
      'p_title',
      'p_body',
      'p_mood',
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

  if update_oid is null
     or pg_catalog.obj_description(update_oid, 'pg_proc') is null then
    raise exception
      'integrate_post_image_edits postcondition failed: RPC differs';
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
    where function.oid = update_oid
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  )
     or pg_catalog.has_function_privilege('anon', update_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       'authenticated', update_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', update_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', update_oid, 'EXECUTE'
     ) then
    raise exception
      'integrate_post_image_edits postcondition failed: RPC ACL differs';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.post_images', 'INSERT, UPDATE, DELETE'
     )
     or exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like 'my_diary_post_images_storage_%'
         and cmd in ('ALL', 'UPDATE')
     ) then
    raise exception
      'integrate_post_image_edits postcondition failed: mutation boundary differs';
  end if;
end;
$postcondition$;

commit;
