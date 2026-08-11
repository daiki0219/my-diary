begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.exchange_entries') is null
     or pg_catalog.to_regclass('public.exchange_entry_tags') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('storage.buckets') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_exchange_diary(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_normalize_tag_name(text)'
     ) is null
     or pg_catalog.to_regprocedure('storage.allow_only_operation(text)') is null
     or pg_catalog.to_regprocedure('storage.allow_any_operation(text[])') is null then
    raise exception
      'integrate_exchange_entry_images preflight failed: required dependency missing';
  end if;

  if pg_catalog.to_regclass('public.exchange_entry_images') is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(text,text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'
     ) is not null then
    raise exception
      'integrate_exchange_entry_images preflight failed: object collision';
  end if;

  if exists (
    select 1
    from storage.buckets
    where id = 'exchange-entry-images'
       or name = 'exchange-entry-images'
  ) then
    raise exception
      'integrate_exchange_entry_images preflight failed: bucket collision';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) then
    raise exception
      'integrate_exchange_entry_images preflight failed: Storage policy collision';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entries'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entries_pkey'
      and contype = 'p'
  ) then
    raise exception
      'integrate_exchange_entry_images preflight failed: entry identity differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
      and relation.relrowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'integrate_exchange_entry_images preflight failed: Storage ownership or RLS differs';
  end if;
end;
$preflight$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'exchange-entry-images',
  'exchange-entry-images',
  false,
  6291456,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
);

create table public.exchange_entry_images (
  id uuid not null,
  entry_id uuid not null,
  storage_path text not null,
  sort_order smallint not null,
  created_at timestamptz not null default now(),
  constraint my_diary_exchange_entry_images_pkey primary key (id),
  constraint my_diary_exchange_entry_images_entry_id_fkey
    foreign key (entry_id)
    references public.exchange_entries (id)
    on delete cascade,
  constraint my_diary_exchange_entry_images_storage_path_key
    unique (storage_path),
  constraint my_diary_exchange_entry_images_entry_sort_key
    unique (entry_id, sort_order) deferrable initially immediate,
  constraint my_diary_exchange_entry_images_sort_order_check
    check (sort_order between 0 and 9),
  constraint my_diary_exchange_entry_images_storage_path_length_check
    check (pg_catalog.char_length(storage_path) between 1 and 1024),
  constraint my_diary_exchange_entry_images_identity_path_check
    check (
      case
        when storage_path ~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then pg_catalog.split_part(storage_path, '/', 4)::uuid = id
        else false
      end
    )
);

alter table public.exchange_entry_images owner to postgres;
alter table public.exchange_entry_images enable row level security;

revoke all on table public.exchange_entry_images
  from public, anon, authenticated, service_role, authenticator;
grant select on table public.exchange_entry_images to authenticated;

create policy my_diary_exchange_entry_images_select_participant
on public.exchange_entry_images
for select
to authenticated
using (
  exists (
    select 1
    from public.exchange_entries as entry
    where entry.id = exchange_entry_images.entry_id
      and entry.deleted_at is null
      and my_diary_private.my_diary_can_view_exchange_diary(entry.diary_id)
  )
);

create function
  my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(
    p_storage_path text,
    p_owner_id text
  )
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and storage.allow_only_operation('storage.object.upload')
    and p_owner_id = auth.uid()::text
    and case
      when p_storage_path ~ (
        '^' || auth.uid()::text ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      ) then exists (
        select 1
        from public.exchange_diaries as diary
        where diary.id =
            pg_catalog.split_part(p_storage_path, '/', 2)::uuid
          and diary.state = 'active'
          and my_diary_private.my_diary_can_view_exchange_diary(diary.id)
      )
      else false
    end;
$function$;

create function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    p_storage_path text,
    p_owner_id text
  )
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or not storage.allow_any_operation(array[
      'storage.object.upload',
      'storage.object.delete_many'
    ])
     or p_owner_id <> auth.uid()::text
     or p_storage_path !~ (
       '^' || auth.uid()::text ||
       '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
       '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
       '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     ) then
    return false;
  end if;

  perform storage_object.id
  from storage.objects as storage_object
  where storage_object.bucket_id = 'exchange-entry-images'
    and storage_object.name = p_storage_path
    and storage_object.owner_id = p_owner_id
  for update;

  if not found then
    return false;
  end if;

  return
    my_diary_private.my_diary_can_view_exchange_diary(
      pg_catalog.split_part(p_storage_path, '/', 2)::uuid
    )
    and not exists (
      select 1
      from public.exchange_entry_images as image
      where image.storage_path = p_storage_path
    );
end;
$function$;

alter function
  my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(text, text)
  owner to postgres;
alter function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(text, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(text, text)
  to authenticated;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  to authenticated;

create policy my_diary_exchange_entry_images_storage_select_visible_entry
on storage.objects
for select
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and exists (
    select 1
    from public.exchange_entry_images as image
    where image.storage_path = objects.name
  )
);

create policy my_diary_exchange_entry_images_storage_select_owned_orphan
on storage.objects
for select
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    name, owner_id
  )
);

create policy my_diary_exchange_entry_images_storage_guard_authenticated
on storage.objects
as restrictive
for select
to authenticated
using (
  bucket_id <> 'exchange-entry-images'
  or exists (
    select 1
    from public.exchange_entry_images as image
    where image.storage_path = objects.name
  )
  or my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    name, owner_id
  )
);

create policy my_diary_exchange_entry_images_storage_guard_anon
on storage.objects
as restrictive
for select
to anon
using (bucket_id <> 'exchange-entry-images');

create policy my_diary_exchange_entry_images_storage_insert_participant
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'exchange-entry-images'
  and my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(
    name, owner_id
  )
);

create policy my_diary_exchange_entry_images_storage_guard_insert_auth
on storage.objects
as restrictive
for insert
to authenticated
with check (
  bucket_id <> 'exchange-entry-images'
  or my_diary_private.my_diary_exchange_entry_image_upload_is_allowed(
    name, owner_id
  )
);

create policy my_diary_exchange_entry_images_storage_delete_owned_orphan
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and storage.allow_only_operation('storage.object.delete_many')
  and my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    name, owner_id
  )
);

create policy my_diary_exchange_entry_images_storage_guard_delete_auth
on storage.objects
as restrictive
for delete
to authenticated
using (
  bucket_id <> 'exchange-entry-images'
  or (
    storage.allow_only_operation('storage.object.delete_many')
    and my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
      name, owner_id
    )
  )
);

create function my_diary_private.my_diary_prepare_exchange_entry_tags(
  p_tags text[]
)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  raw_tags text[] := coalesce(p_tags, array[]::text[]);
  canonical_tags text[] := array[]::text[];
  raw_tag text;
  canonical_tag text;
begin
  if pg_catalog.cardinality(raw_tags) > 20
     or (
       pg_catalog.cardinality(raw_tags) > 0
       and pg_catalog.array_ndims(raw_tags) <> 1
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  foreach raw_tag in array raw_tags loop
    if raw_tag is null then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    canonical_tag :=
      my_diary_private.my_diary_normalize_tag_name(raw_tag);

    if canonical_tag is null
       or pg_catalog.char_length(canonical_tag) not between 1 and 30
       or pg_catalog.strpos(canonical_tag, ',') > 0
       or pg_catalog.strpos(canonical_tag, '#') > 0
       or canonical_tag ~ '[[:cntrl:]]' then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    if not canonical_tag = any(canonical_tags) then
      canonical_tags := pg_catalog.array_append(
        canonical_tags, canonical_tag
      );
    end if;
  end loop;

  select coalesce(
    pg_catalog.array_agg(tag_name order by tag_name),
    array[]::text[]
  )
  into canonical_tags
  from pg_catalog.unnest(canonical_tags) as canonical(tag_name);

  if pg_catalog.cardinality(canonical_tags) > 5 then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  return canonical_tags;
end;
$function$;

alter function
  my_diary_private.my_diary_prepare_exchange_entry_tags(text[])
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_prepare_exchange_entry_tags(text[])
  from public, anon, authenticated, service_role, authenticator;

create function public.my_diary_create_exchange_entry_with_images(
  p_entry_id uuid,
  p_diary_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
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
  viewer_user_id uuid := auth.uid();
  author_participant_id uuid;
  normalized_title text;
  normalized_body text;
  normalized_mood text;
  normalized_location_name text;
  canonical_tags text[];
  image_paths text[] := coalesce(p_image_paths, array[]::text[]);
  image_path text;
  path_pattern text;
  resolved_tag_id uuid;
  canonical_tag text;
  locked_image_count integer;
begin
  normalized_title := nullif(
    pg_catalog.regexp_replace(
      p_title, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  normalized_body := pg_catalog.regexp_replace(
    p_body, '^[[:space:]]+|[[:space:]]+$', '', 'g'
  );
  normalized_mood := nullif(pg_catalog.btrim(p_mood), '');
  normalized_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );

  if p_entry_id is null
     or p_diary_id is null
     or (
       normalized_title is not null
       and pg_catalog.char_length(normalized_title) > 120
     )
     or normalized_body is null
     or pg_catalog.char_length(normalized_body) not between 1 and 10000
     or (
       normalized_mood is not null
       and normalized_mood not in (
         'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
       )
     )
     or (
       normalized_location_name is not null
       and pg_catalog.char_length(normalized_location_name) > 100
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry input.';
  end if;

  canonical_tags :=
    my_diary_private.my_diary_prepare_exchange_entry_tags(p_tags);

  if pg_catalog.cardinality(image_paths) > 10
     or (
       pg_catalog.cardinality(image_paths) > 0
       and pg_catalog.array_ndims(image_paths) <> 1
     )
     or pg_catalog.array_position(image_paths, null::text) is not null
     or (
       select pg_catalog.count(*) <> pg_catalog.count(distinct candidate_path)
       from pg_catalog.unnest(image_paths) as paths(candidate_path)
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  path_pattern :=
    '^' || viewer_user_id::text || '/' || p_diary_id::text || '/' ||
    p_entry_id::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  foreach image_path in array image_paths loop
    if pg_catalog.char_length(image_path) not between 1 and 1024
       or image_path !~ path_pattern then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
    end if;
  end loop;

  author_participant_id :=
    my_diary_private.my_diary_lock_exchange_diary_for_entry(
      p_diary_id, viewer_user_id, false
    );

  perform object.id
  from storage.objects as object
  where object.bucket_id = 'exchange-entry-images'
    and object.name = any(image_paths)
    and object.owner_id = viewer_user_id::text
    and object.metadata ->> 'mimetype' in (
      'image/jpeg', 'image/png', 'image/webp'
    )
    and case
      when object.metadata ->> 'size' ~ '^[0-9]+$'
      then (object.metadata ->> 'size')::numeric between 1 and 6291456
      else false
    end
  order by object.name, object.id
  for update;

  get diagnostics locked_image_count = row_count;

  if locked_image_count <> pg_catalog.cardinality(image_paths) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  if exists (
       select 1
       from public.exchange_entry_images as image
       where image.storage_path = any(image_paths)
          or image.id = any(
            select pg_catalog.split_part(candidate_path, '/', 4)::uuid
            from pg_catalog.unnest(image_paths) as paths(candidate_path)
          )
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  if exists (
       select 1
       from public.exchange_entries as entry
       where entry.id = p_entry_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  begin
    insert into public.exchange_entries (
      id,
      diary_id,
      author_participant_id,
      title,
      body,
      mood,
      location_name
    )
    values (
      p_entry_id,
      p_diary_id,
      author_participant_id,
      normalized_title,
      normalized_body,
      normalized_mood,
      normalized_location_name
    );
  exception
    when unique_violation then
      raise exception using
        errcode = '42501',
        message = 'Exchange entry operation is unavailable.';
  end;

  foreach canonical_tag in array canonical_tags loop
    insert into public.tags (name, normalized_name)
    values (canonical_tag, canonical_tag)
    on conflict (normalized_name) do nothing;

    select tag.id
    into resolved_tag_id
    from public.tags as tag
    where tag.normalized_name = canonical_tag;

    if resolved_tag_id is null then
      raise exception using
        errcode = '40001',
        message = 'Tag resolution must be retried.';
    end if;

    insert into public.exchange_entry_tags (entry_id, tag_id)
    values (p_entry_id, resolved_tag_id);
  end loop;

  begin
    insert into public.exchange_entry_images (
      id,
      entry_id,
      storage_path,
      sort_order
    )
    select
      pg_catalog.split_part(candidate_path, '/', 4)::uuid,
      p_entry_id,
      candidate_path,
      (ordinality - 1)::smallint
    from pg_catalog.unnest(image_paths) with ordinality
      as paths(candidate_path, ordinality);
  exception
    when unique_violation then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
  end;

  return p_entry_id;
end;
$function$;

create function public.my_diary_update_exchange_entry_with_images(
  p_entry_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
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
  viewer_user_id uuid := auth.uid();
  target_diary_id uuid;
  viewer_participant_id uuid;
  locked_entry_id uuid;
  normalized_title text;
  normalized_body text;
  normalized_mood text;
  normalized_location_name text;
  canonical_tags text[] := array[]::text[];
  resolved_tag_ids uuid[] := array[]::uuid[];
  retained_ids uuid[] := array[]::uuid[];
  new_paths text[] := array[]::text[];
  new_ids uuid[] := array[]::uuid[];
  removed_paths text[] := array[]::text[];
  canonical_tag text;
  resolved_tag_id uuid;
  manifest_item jsonb;
  manifest_index integer;
  existing_id_text text;
  new_path text;
  path_pattern text;
  locked_row_count integer;
begin
  normalized_title := nullif(
    pg_catalog.regexp_replace(
      p_title, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  normalized_body := pg_catalog.regexp_replace(
    p_body, '^[[:space:]]+|[[:space:]]+$', '', 'g'
  );
  normalized_mood := nullif(pg_catalog.btrim(p_mood), '');
  normalized_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );

  if p_entry_id is null
     or (
       normalized_title is not null
       and pg_catalog.char_length(normalized_title) > 120
     )
     or normalized_body is null
     or pg_catalog.char_length(normalized_body) not between 1 and 10000
     or (
       normalized_mood is not null
       and normalized_mood not in (
         'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
       )
     )
     or (
       normalized_location_name is not null
       and pg_catalog.char_length(normalized_location_name) > 100
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry input.';
  end if;

  if p_tags is not null then
    canonical_tags :=
      my_diary_private.my_diary_prepare_exchange_entry_tags(p_tags);
  end if;

  if p_image_manifest is null
     or pg_catalog.jsonb_typeof(p_image_manifest) <> 'array'
     or pg_catalog.jsonb_array_length(p_image_manifest) > 10 then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  select entry.diary_id
  into target_diary_id
  from public.exchange_entries as entry
  where entry.id = p_entry_id;

  if target_diary_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  viewer_participant_id :=
    my_diary_private.my_diary_lock_exchange_diary_for_entry(
      target_diary_id, viewer_user_id, false
    );

  select entry.id
  into locked_entry_id
  from public.exchange_entries as entry
  where entry.id = p_entry_id
    and entry.diary_id = target_diary_id
    and entry.author_participant_id = viewer_participant_id
    and entry.deleted_at is null
  for update;

  if locked_entry_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  perform image.id
  from public.exchange_entry_images as image
  where image.entry_id = locked_entry_id
  order by image.id
  for update;

  path_pattern :=
    '^' || viewer_user_id::text || '/' || target_diary_id::text || '/' ||
    p_entry_id::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  for manifest_item, manifest_index in
    select item, ordinality::integer - 1
    from pg_catalog.jsonb_array_elements(p_image_manifest)
      with ordinality as manifest(item, ordinality)
  loop
    if pg_catalog.jsonb_typeof(manifest_item) <> 'object'
       or (
         select pg_catalog.count(*)
         from pg_catalog.jsonb_object_keys(manifest_item)
       ) <> 1 then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
    end if;

    if manifest_item ? 'existingId'
       and pg_catalog.jsonb_typeof(manifest_item -> 'existingId') = 'string' then
      existing_id_text := manifest_item ->> 'existingId';

      if existing_id_text !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or existing_id_text::uuid = any(retained_ids) then
        raise exception using
          errcode = '22023',
          message = 'Invalid exchange entry image input.';
      end if;

      retained_ids := pg_catalog.array_append(
        retained_ids, existing_id_text::uuid
      );
    elsif manifest_item ? 'newPath'
       and pg_catalog.jsonb_typeof(manifest_item -> 'newPath') = 'string' then
      new_path := manifest_item ->> 'newPath';

      if pg_catalog.char_length(new_path) not between 1 and 1024
         or new_path !~ path_pattern
         or new_path = any(new_paths)
         or pg_catalog.split_part(new_path, '/', 4)::uuid = any(new_ids) then
        raise exception using
          errcode = '22023',
          message = 'Invalid exchange entry image input.';
      end if;

      new_paths := pg_catalog.array_append(new_paths, new_path);
      new_ids := pg_catalog.array_append(
        new_ids, pg_catalog.split_part(new_path, '/', 4)::uuid
      );
    else
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
    end if;
  end loop;

  select pg_catalog.count(*)
  into locked_row_count
  from public.exchange_entry_images as image
  where image.entry_id = locked_entry_id
    and image.id = any(retained_ids);

  if locked_row_count <> pg_catalog.cardinality(retained_ids) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  perform storage_object.id
  from storage.objects as storage_object
  where storage_object.bucket_id = 'exchange-entry-images'
    and storage_object.name = any(new_paths)
    and storage_object.owner_id = viewer_user_id::text
    and storage_object.metadata ->> 'mimetype' in (
      'image/jpeg', 'image/png', 'image/webp'
    )
    and case
      when storage_object.metadata ->> 'size' ~ '^[0-9]+$'
      then (storage_object.metadata ->> 'size')::numeric
        between 1 and 6291456
      else false
    end
  order by storage_object.name, storage_object.id
  for update;

  get diagnostics locked_row_count = row_count;

  if locked_row_count <> pg_catalog.cardinality(new_paths)
     or exists (
       select 1
       from public.exchange_entry_images as image
       where image.storage_path = any(new_paths)
          or image.id = any(new_ids)
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  select coalesce(
    pg_catalog.array_agg(image.storage_path order by image.sort_order),
    array[]::text[]
  )
  into removed_paths
  from public.exchange_entry_images as image
  where image.entry_id = locked_entry_id
    and not image.id = any(retained_ids);

  update public.exchange_entries as entry
  set title = normalized_title,
      body = normalized_body,
      mood = normalized_mood,
      location_name = normalized_location_name
  where entry.id = locked_entry_id;

  if p_tags is not null then
    foreach canonical_tag in array canonical_tags loop
      insert into public.tags (name, normalized_name)
      values (canonical_tag, canonical_tag)
      on conflict (normalized_name) do nothing;

      select tag.id
      into resolved_tag_id
      from public.tags as tag
      where tag.normalized_name = canonical_tag;

      if resolved_tag_id is null then
        raise exception using
          errcode = '40001',
          message = 'Tag resolution must be retried.';
      end if;

      resolved_tag_ids := pg_catalog.array_append(
        resolved_tag_ids, resolved_tag_id
      );
    end loop;

    delete from public.exchange_entry_tags as existing
    where existing.entry_id = locked_entry_id
      and not existing.tag_id = any(resolved_tag_ids);

    insert into public.exchange_entry_tags (entry_id, tag_id)
    select locked_entry_id, desired.tag_id
    from pg_catalog.unnest(resolved_tag_ids) as desired(tag_id)
    where not exists (
      select 1
      from public.exchange_entry_tags as existing
      where existing.entry_id = locked_entry_id
        and existing.tag_id = desired.tag_id
    );
  end if;

  set constraints public.my_diary_exchange_entry_images_entry_sort_key
    deferred;

  begin
    for manifest_item, manifest_index in
      select item, ordinality::integer - 1
      from pg_catalog.jsonb_array_elements(p_image_manifest)
        with ordinality as manifest(item, ordinality)
    loop
      if manifest_item ? 'existingId' then
        update public.exchange_entry_images as image
        set sort_order = manifest_index::smallint
        where image.id = (manifest_item ->> 'existingId')::uuid
          and image.entry_id = locked_entry_id;
      else
        insert into public.exchange_entry_images (
          id, entry_id, storage_path, sort_order
        )
        values (
          pg_catalog.split_part(manifest_item ->> 'newPath', '/', 4)::uuid,
          locked_entry_id,
          manifest_item ->> 'newPath',
          manifest_index::smallint
        );
      end if;
    end loop;

    delete from public.exchange_entry_images as image
    where image.entry_id = locked_entry_id
      and not image.id = any(retained_ids)
      and not image.storage_path = any(new_paths);
  exception
    when unique_violation then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
  end;

  return pg_catalog.jsonb_build_object(
    'entryId', locked_entry_id,
    'removedImagePaths', pg_catalog.to_jsonb(removed_paths)
  );
end;
$function$;

alter function public.my_diary_create_exchange_entry_with_images(
  uuid, uuid, text, text, text, text, text[], text[]
) owner to postgres;
alter function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) owner to postgres;

comment on function public.my_diary_create_exchange_entry_with_images(
  uuid, uuid, text, text, text, text, text[], text[]
) is 'Atomically creates an exchange entry, canonical tags, and ordered private image metadata.';
comment on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) is 'Atomically updates an exchange entry, canonical tags, and its final ordered private image manifest.';

revoke all on function public.my_diary_create_exchange_entry_with_images(
  uuid, uuid, text, text, text, text, text[], text[]
) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_exchange_entry_with_images(
  uuid, uuid, text, text, text, text, text[], text[]
) to authenticated;
grant execute on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) to authenticated;

do $postcondition$
declare
  create_oid oid;
  update_oid oid;
begin
  if (
    select pg_catalog.count(*)
    from storage.buckets
    where id = 'exchange-entry-images'
      and name = 'exchange-entry-images'
      and public is false
      and file_size_limit = 6291456
      and allowed_mime_types =
        array['image/jpeg', 'image/png', 'image/webp']::text[]
  ) <> 1 then
    raise exception
      'integrate_exchange_entry_images postcondition failed: bucket differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    where relation.oid =
        'public.exchange_entry_images'::pg_catalog.regclass
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: metadata ownership or RLS differs';
  end if;

  if (
    select pg_catalog.array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
        'public.exchange_entry_images'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'id:uuid:t',
    'entry_id:uuid:t',
    'storage_path:text:t',
    'sort_order:smallint:t',
    'created_at:timestamp with time zone:t'
  ]::text[] then
    raise exception
      'integrate_exchange_entry_images postcondition failed: metadata columns differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_entry_images'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_images_entry_id_fkey'
      and contype = 'f'
      and confrelid = 'public.exchange_entries'::pg_catalog.regclass
      and confdeltype = 'c'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_entry_images'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_images_entry_sort_key'
      and contype = 'u'
      and condeferrable
      and not condeferred
  ) or (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_entry_images'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_entry_images_pkey',
        'my_diary_exchange_entry_images_storage_path_key',
        'my_diary_exchange_entry_images_sort_order_check',
        'my_diary_exchange_entry_images_storage_path_length_check',
        'my_diary_exchange_entry_images_identity_path_check'
      )
  ) <> 5 then
    raise exception
      'integrate_exchange_entry_images postcondition failed: metadata constraints differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_entry_images'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 1 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_entry_images'
  ) <> 1 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) <> 8 or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: RLS policies differ';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.exchange_entry_images', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'public.exchange_entry_images',
       'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon',
       'public.exchange_entry_images',
       'SELECT, INSERT, UPDATE, DELETE'
     )
     or exists (
       select 1
       from pg_catalog.pg_class as relation
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           relation.relacl,
           pg_catalog.acldefault('r', relation.relowner)
         )
       ) as privilege
       where relation.oid =
           'public.exchange_entry_images'::pg_catalog.regclass
         and privilege.grantee = 0
     ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: metadata ACL differs';
  end if;

  select function_definition.oid
  into create_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname =
      'my_diary_create_exchange_entry_with_images'
    and function_definition.proargtypes =
      '2950 2950 25 25 25 25 1009 1009'::oidvector
    and function_definition.proargnames = array[
      'p_entry_id',
      'p_diary_id',
      'p_title',
      'p_body',
      'p_mood',
      'p_location_name',
      'p_tags',
      'p_image_paths'
    ]::text[]
    and function_definition.prorettype = 'uuid'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  select function_definition.oid
  into update_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname =
      'my_diary_update_exchange_entry_with_images'
    and function_definition.proargtypes =
      '2950 25 25 25 25 1009 3802'::oidvector
    and function_definition.proargnames = array[
      'p_entry_id',
      'p_title',
      'p_body',
      'p_mood',
      'p_location_name',
      'p_tags',
      'p_image_manifest'
    ]::text[]
    and function_definition.prorettype = 'jsonb'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if create_oid is null
     or update_oid is null
     or pg_catalog.obj_description(create_oid, 'pg_proc') is null
     or pg_catalog.obj_description(update_oid, 'pg_proc') is null
     or exists (
       select 1
       from pg_catalog.pg_proc as function_definition
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = function_definition.pronamespace
       where namespace.nspname = 'public'
         and function_definition.proname in (
           'my_diary_create_exchange_entry_with_images',
           'my_diary_update_exchange_entry_with_images'
         )
         and function_definition.oid not in (create_oid, update_oid)
     ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: RPC catalog differs';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(array[create_oid, update_oid]) as target(oid)
    where not pg_catalog.has_function_privilege(
            'authenticated', target.oid, 'EXECUTE'
          )
       or pg_catalog.has_function_privilege('anon', target.oid, 'EXECUTE')
       or pg_catalog.has_function_privilege(
            'service_role', target.oid, 'EXECUTE'
          )
       or pg_catalog.has_function_privilege(
            'authenticator', target.oid, 'EXECUTE'
          )
  ) or exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as privilege
    where function_definition.oid in (create_oid, update_oid)
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: RPC ACL differs';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_create_exchange_entry(uuid,text,text,text,text,text[])'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_exchange_entry(uuid,text,text,text,text,text[])'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_soft_delete_exchange_entry(uuid)'
     ) is null
     or (
       select pg_catalog.count(*)
       from storage.buckets
       where id = 'post-images'
         and name = 'post-images'
         and public is false
         and file_size_limit = 6291456
         and allowed_mime_types =
           array['image/jpeg', 'image/png', 'image/webp']::text[]
     ) <> 1 then
    raise exception
      'integrate_exchange_entry_images postcondition failed: predecessor compatibility differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'integrate_exchange_entry_images postcondition failed: Storage owner changed';
  end if;
end;
$postcondition$;

commit;
