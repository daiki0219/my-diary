begin;

do $preflight$
declare
  existing_public_function_count integer;
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_set_updated_at()'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_exchange_diary(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_normalize_tag_name(text)'
     ) is null then
    raise exception
      'create_exchange_entries preflight failed: required dependency missing';
  end if;

  if pg_catalog.to_regclass('public.exchange_entries') is not null
     or pg_catalog.to_regclass('public.exchange_entry_tags') is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_reject_exchange_entry_rewrite()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_reject_deleted_exchange_entry_tag()'
     ) is not null then
    raise exception
      'create_exchange_entries preflight failed: object collision';
  end if;

  select pg_catalog.count(*)
  into existing_public_function_count
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname in (
      'my_diary_create_exchange_entry',
      'my_diary_update_exchange_entry',
      'my_diary_soft_delete_exchange_entry',
      'my_diary_get_exchange_entry_tags'
    );

  if existing_public_function_count <> 0 then
    raise exception
      'create_exchange_entries preflight failed: RPC name collision';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_constraint as constraint_definition
       where constraint_definition.conrelid =
         'public.exchange_diary_participants'::pg_catalog.regclass
         and constraint_definition.conname =
           'my_diary_exchange_diary_participants_diary_id_id_key'
         and constraint_definition.contype = 'u'
     )
     or not exists (
       select 1
       from pg_catalog.pg_constraint as constraint_definition
       where constraint_definition.conrelid =
         'public.tags'::pg_catalog.regclass
         and constraint_definition.conname =
           'my_diary_tags_normalized_name_key'
         and constraint_definition.contype = 'u'
     ) then
    raise exception
      'create_exchange_entries preflight failed: required uniqueness differs';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'tags'
         and policyname = 'my_diary_tags_select_visible_post'
         and cmd = 'SELECT'
         and roles = array['authenticated']::name[]
     )
     or not exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'post_tags'
         and policyname = 'my_diary_post_tags_select_visible_post'
         and cmd = 'SELECT'
         and roles = array['authenticated']::name[]
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'INSERT, UPDATE, DELETE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'create_exchange_entries preflight failed: existing tag RLS or ACL differs';
  end if;
end;
$preflight$;

create table public.exchange_entries (
  id uuid not null default gen_random_uuid(),
  diary_id uuid not null,
  author_participant_id uuid not null,
  title text,
  body text,
  mood text,
  location_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  redaction_reason text,
  constraint my_diary_exchange_entries_pkey primary key (id),
  constraint my_diary_exchange_entries_diary_id_fkey
    foreign key (diary_id)
    references public.exchange_diaries (id)
    on delete cascade,
  constraint my_diary_exchange_entries_author_diary_fkey
    foreign key (diary_id, author_participant_id)
    references public.exchange_diary_participants (diary_id, id),
  constraint my_diary_exchange_entries_title_check
    check (
      title is null
      or (
        pg_catalog.char_length(title) between 1 and 120
        and title = pg_catalog.regexp_replace(
          title, '^[[:space:]]+|[[:space:]]+$', '', 'g'
        )
      )
    ),
  constraint my_diary_exchange_entries_body_check
    check (
      body is null
      or (
        pg_catalog.char_length(body) between 1 and 10000
        and body = pg_catalog.regexp_replace(
          body, '^[[:space:]]+|[[:space:]]+$', '', 'g'
        )
      )
    ),
  constraint my_diary_exchange_entries_mood_check
    check (
      mood is null
      or mood in ('happy', 'sad', 'tired', 'irritated', 'calm', 'neutral')
    ),
  constraint my_diary_exchange_entries_location_name_check
    check (
      location_name is null
      or (
        pg_catalog.char_length(location_name) between 1 and 100
        and location_name = pg_catalog.regexp_replace(
          location_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'
        )
      )
    ),
  constraint my_diary_exchange_entries_redaction_shape_check
    check (
      (
        deleted_at is null
        and redaction_reason is null
        and body is not null
      )
      or (
        deleted_at is not null
        and redaction_reason in ('user_deleted', 'account_deleted')
        and title is null
        and body is null
        and mood is null
        and location_name is null
      )
    )
);

create index my_diary_exchange_entries_diary_created_id_idx
  on public.exchange_entries (diary_id, created_at, id);

create table public.exchange_entry_tags (
  entry_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  constraint my_diary_exchange_entry_tags_pkey
    primary key (entry_id, tag_id),
  constraint my_diary_exchange_entry_tags_entry_id_fkey
    foreign key (entry_id)
    references public.exchange_entries (id)
    on delete cascade,
  constraint my_diary_exchange_entry_tags_tag_id_fkey
    foreign key (tag_id)
    references public.tags (id)
    on delete cascade
);

create index my_diary_exchange_entry_tags_tag_entry_idx
  on public.exchange_entry_tags (tag_id, entry_id);

alter table public.exchange_entries owner to postgres;
alter table public.exchange_entry_tags owner to postgres;

create function my_diary_private.my_diary_lock_exchange_diary_for_entry(
  p_diary_id uuid,
  p_viewer_user_id uuid,
  p_allow_archived boolean
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  initial_participant_user_ids uuid[];
  final_participant_user_ids uuid[];
  viewer_participant_id uuid;
  participant_row_count integer;
  locked_account_count integer;
  locked_participant_count integer;
  locked_diary_state text;
begin
  if p_diary_id is null
     or p_viewer_user_id is null
     or p_allow_archived is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  select
    coalesce(
      pg_catalog.array_agg(
        participant.user_id order by participant.user_id
      ) filter (where participant.user_id is not null),
      array[]::uuid[]
    ),
    pg_catalog.count(*)
  into initial_participant_user_ids, participant_row_count
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id;

  if participant_row_count <> 2
     or not p_viewer_user_id = any(initial_participant_user_ids)
     or (
       not p_allow_archived
       and pg_catalog.cardinality(initial_participant_user_ids) <> 2
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  perform account.user_id
  from public.accounts as account
  where account.user_id = any(initial_participant_user_ids)
  order by account.user_id
  for update;

  get diagnostics locked_account_count = row_count;

  if locked_account_count < 1
     or locked_account_count <>
       pg_catalog.cardinality(initial_participant_user_ids) then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  select diary.state
  into locked_diary_state
  from public.exchange_diaries as diary
  where diary.id = p_diary_id
  for update;

  perform participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
  order by participant.position, participant.id
  for update;

  get diagnostics locked_participant_count = row_count;

  select
    coalesce(
      pg_catalog.array_agg(
        participant.user_id order by participant.user_id
      ) filter (where participant.user_id is not null),
      array[]::uuid[]
    ),
    (
      pg_catalog.max(participant.id::text) filter (
        where participant.user_id = p_viewer_user_id
      )
    )::uuid
  into final_participant_user_ids, viewer_participant_id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id;

  if locked_diary_state is null
     or locked_participant_count <> 2
     or final_participant_user_ids is distinct from
       initial_participant_user_ids
     or viewer_participant_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = p_viewer_user_id
         and viewer_account.status = 'active'
     )
     or (
       locked_diary_state = 'active'
       and (
         pg_catalog.cardinality(final_participant_user_ids) <> 2
         or (
           select pg_catalog.count(*)
           from public.accounts as participant_account
           where participant_account.user_id = any(final_participant_user_ids)
             and participant_account.status = 'active'
         ) <> 2
       )
     )
     or (
       locked_diary_state = 'archived'
       and (
         not p_allow_archived
         or not my_diary_private.my_diary_can_view_exchange_diary(
           p_diary_id
         )
       )
     )
     or locked_diary_state not in ('active', 'archived') then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  return viewer_participant_id;
end;
$function$;

create function my_diary_private.my_diary_reject_exchange_entry_rewrite()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.diary_id is distinct from old.diary_id
     or new.author_participant_id is distinct from old.author_participant_id
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Exchange entry identity cannot be changed.';
  end if;

  if old.deleted_at is not null
     and (
       new.deleted_at is distinct from old.deleted_at
       or new.redaction_reason is distinct from old.redaction_reason
       or new.title is not null
       or new.body is not null
       or new.mood is not null
       or new.location_name is not null
     ) then
    raise exception using
      errcode = '23514',
      message = 'A redacted exchange entry cannot be changed.';
  end if;

  return new;
end;
$function$;

create function my_diary_private.my_diary_reject_deleted_exchange_entry_tag()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1
    from public.exchange_entries as entry
    where entry.id = new.entry_id
      and entry.deleted_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'A redacted exchange entry cannot have tags.';
  end if;

  return new;
end;
$function$;

create function public.my_diary_create_exchange_entry(
  p_diary_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_tags text[]
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
  new_entry_id uuid;
  normalized_title text;
  normalized_body text;
  normalized_mood text;
  normalized_location_name text;
  raw_tags text[] := coalesce(p_tags, array[]::text[]);
  canonical_tags text[] := array[]::text[];
  raw_tag text;
  canonical_tag text;
  resolved_tag_id uuid;
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

  if p_diary_id is null
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

  author_participant_id :=
    my_diary_private.my_diary_lock_exchange_diary_for_entry(
      p_diary_id, viewer_user_id, false
    );

  insert into public.exchange_entries (
    diary_id,
    author_participant_id,
    title,
    body,
    mood,
    location_name
  )
  values (
    p_diary_id,
    author_participant_id,
    normalized_title,
    normalized_body,
    normalized_mood,
    normalized_location_name
  )
  returning id into new_entry_id;

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
    values (new_entry_id, resolved_tag_id);
  end loop;

  return new_entry_id;
end;
$function$;

create function public.my_diary_update_exchange_entry(
  p_entry_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_tags text[]
)
returns uuid
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
  raw_tag text;
  canonical_tag text;
  resolved_tag_id uuid;
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
    if pg_catalog.cardinality(p_tags) > 20
       or (
         pg_catalog.cardinality(p_tags) > 0
         and pg_catalog.array_ndims(p_tags) <> 1
       ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    foreach raw_tag in array p_tags loop
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

  return locked_entry_id;
end;
$function$;

create function public.my_diary_soft_delete_exchange_entry(
  p_entry_id uuid
)
returns boolean
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
begin
  if p_entry_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry input.';
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
      target_diary_id, viewer_user_id, true
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

  delete from public.exchange_entry_tags as entry_tag
  where entry_tag.entry_id = locked_entry_id;

  update public.exchange_entries as entry
  set title = null,
      body = null,
      mood = null,
      location_name = null,
      deleted_at = now(),
      redaction_reason = 'user_deleted'
  where entry.id = locked_entry_id;

  return true;
end;
$function$;

create function public.my_diary_get_exchange_entry_tags(
  p_entry_ids uuid[]
)
returns table (
  entry_id uuid,
  tag_id uuid,
  name text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or not my_diary_private.my_diary_is_account_active(auth.uid()) then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  if p_entry_ids is null
     or pg_catalog.cardinality(p_entry_ids) > 50
     or (
       pg_catalog.array_ndims(p_entry_ids) is not null
       and pg_catalog.array_ndims(p_entry_ids) <> 1
     )
     or pg_catalog.array_position(p_entry_ids, null::uuid) is not null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry batch input.';
  end if;

  return query
  select
    entry_tag.entry_id,
    tag.id,
    tag.name
  from public.exchange_entry_tags as entry_tag
  join public.exchange_entries as entry
    on entry.id = entry_tag.entry_id
  join public.tags as tag
    on tag.id = entry_tag.tag_id
  where entry_tag.entry_id = any(p_entry_ids)
    and my_diary_private.my_diary_can_view_exchange_diary(entry.diary_id)
  order by entry_tag.entry_id, tag.name, tag.id;
end;
$function$;

alter function my_diary_private.my_diary_lock_exchange_diary_for_entry(
  uuid, uuid, boolean
) owner to postgres;
alter function my_diary_private.my_diary_reject_exchange_entry_rewrite()
  owner to postgres;
alter function my_diary_private.my_diary_reject_deleted_exchange_entry_tag()
  owner to postgres;
alter function public.my_diary_create_exchange_entry(
  uuid, text, text, text, text, text[]
) owner to postgres;
alter function public.my_diary_update_exchange_entry(
  uuid, text, text, text, text, text[]
) owner to postgres;
alter function public.my_diary_soft_delete_exchange_entry(uuid)
  owner to postgres;
alter function public.my_diary_get_exchange_entry_tags(uuid[])
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_lock_exchange_diary_for_entry(
    uuid, uuid, boolean
  )
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_reject_exchange_entry_rewrite()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_reject_deleted_exchange_entry_tag()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_create_exchange_entry(
  uuid, text, text, text, text, text[]
) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_exchange_entry(
  uuid, text, text, text, text, text[]
) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_soft_delete_exchange_entry(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_get_exchange_entry_tags(uuid[])
  from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_exchange_entry(
  uuid, text, text, text, text, text[]
) to authenticated;
grant execute on function public.my_diary_update_exchange_entry(
  uuid, text, text, text, text, text[]
) to authenticated;
grant execute on function public.my_diary_soft_delete_exchange_entry(uuid)
  to authenticated;
grant execute on function public.my_diary_get_exchange_entry_tags(uuid[])
  to authenticated;

create trigger my_diary_exchange_entries_reject_rewrite
before update on public.exchange_entries
for each row execute function
  my_diary_private.my_diary_reject_exchange_entry_rewrite();

create trigger my_diary_exchange_entries_set_updated_at
before update on public.exchange_entries
for each row execute function public.my_diary_set_updated_at();

create trigger my_diary_exchange_entry_tags_reject_deleted_entry
before insert or update of entry_id on public.exchange_entry_tags
for each row execute function
  my_diary_private.my_diary_reject_deleted_exchange_entry_tag();

alter table public.exchange_entries enable row level security;
alter table public.exchange_entry_tags enable row level security;

revoke all on table public.exchange_entries
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.exchange_entry_tags
  from public, anon, authenticated, service_role, authenticator;

grant select on table public.exchange_entries to authenticated;
grant select on table public.exchange_entry_tags to authenticated;

create policy my_diary_exchange_entries_select_participant
on public.exchange_entries
for select
to authenticated
using (
  my_diary_private.my_diary_can_view_exchange_diary(
    exchange_entries.diary_id
  )
);

create policy my_diary_exchange_entry_tags_select_participant
on public.exchange_entry_tags
for select
to authenticated
using (
  exists (
    select 1
    from public.exchange_entries as entry
    where entry.id = exchange_entry_tags.entry_id
      and my_diary_private.my_diary_can_view_exchange_diary(entry.diary_id)
  )
);

do $postcondition$
declare
  exact_rpc_count integer;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('exchange_entries', 'exchange_entry_tags')
      and relation.relkind = 'r'
  ) <> 2 then
    raise exception
      'create_exchange_entries postcondition failed: tables missing';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
      'public.exchange_entries'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (attribute.attname, attribute.atttypid, attribute.attnotnull) in (
        ('id', 'uuid'::pg_catalog.regtype, true),
        ('diary_id', 'uuid'::pg_catalog.regtype, true),
        ('author_participant_id', 'uuid'::pg_catalog.regtype, true),
        ('title', 'text'::pg_catalog.regtype, false),
        ('body', 'text'::pg_catalog.regtype, false),
        ('mood', 'text'::pg_catalog.regtype, false),
        ('location_name', 'text'::pg_catalog.regtype, false),
        ('created_at', 'timestamptz'::pg_catalog.regtype, true),
        ('updated_at', 'timestamptz'::pg_catalog.regtype, true),
        ('deleted_at', 'timestamptz'::pg_catalog.regtype, false),
        ('redaction_reason', 'text'::pg_catalog.regtype, false)
      )
  ) <> 11 then
    raise exception
      'create_exchange_entries postcondition failed: entry columns differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid =
      'public.exchange_entries'::pg_catalog.regclass
      and constraint_definition.conname in (
        'my_diary_exchange_entries_pkey',
        'my_diary_exchange_entries_diary_id_fkey',
        'my_diary_exchange_entries_author_diary_fkey',
        'my_diary_exchange_entries_title_check',
        'my_diary_exchange_entries_body_check',
        'my_diary_exchange_entries_mood_check',
        'my_diary_exchange_entries_location_name_check',
        'my_diary_exchange_entries_redaction_shape_check'
      )
  ) <> 8
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_constraint as constraint_definition
       where constraint_definition.conrelid =
         'public.exchange_entry_tags'::pg_catalog.regclass
         and constraint_definition.conname in (
           'my_diary_exchange_entry_tags_pkey',
           'my_diary_exchange_entry_tags_entry_id_fkey',
           'my_diary_exchange_entry_tags_tag_id_fkey'
         )
     ) <> 3 then
    raise exception
      'create_exchange_entries postcondition failed: constraints differ';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_indexes
       where schemaname = 'public'
         and indexname =
           'my_diary_exchange_entries_diary_created_id_idx'
         and indexdef like '%(diary_id, created_at, id)%'
     )
     or not exists (
       select 1
       from pg_catalog.pg_indexes
       where schemaname = 'public'
         and indexname =
           'my_diary_exchange_entry_tags_tag_entry_idx'
         and indexdef like '%(tag_id, entry_id)%'
     ) then
    raise exception
      'create_exchange_entries postcondition failed: indexes differ';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_class as relation
       where relation.oid = 'public.exchange_entries'::pg_catalog.regclass
         and relation.relrowsecurity
         and not relation.relforcerowsecurity
         and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
     )
     or not exists (
       select 1
       from pg_catalog.pg_class as relation
       where relation.oid =
         'public.exchange_entry_tags'::pg_catalog.regclass
         and relation.relrowsecurity
         and not relation.relforcerowsecurity
         and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
     ) then
    raise exception
      'create_exchange_entries postcondition failed: RLS or owner differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('exchange_entries', 'exchange_entry_tags')
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 2
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.exchange_entries', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.exchange_entries',
       'INSERT, UPDATE, DELETE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.exchange_entry_tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.exchange_entry_tags',
       'INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'create_exchange_entries postcondition failed: table ACL differs';
  end if;

  select pg_catalog.count(*)
  into exact_rpc_count
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join (
    values
      (
        'my_diary_create_exchange_entry',
        '2950 25 25 25 25 1009'::oidvector,
        array[
          'p_diary_id', 'p_title', 'p_body', 'p_mood',
          'p_location_name', 'p_tags'
        ]::text[],
        'uuid'::regtype,
        'v'::char
      ),
      (
        'my_diary_update_exchange_entry',
        '2950 25 25 25 25 1009'::oidvector,
        array[
          'p_entry_id', 'p_title', 'p_body', 'p_mood',
          'p_location_name', 'p_tags'
        ]::text[],
        'uuid'::regtype,
        'v'::char
      ),
      (
        'my_diary_soft_delete_exchange_entry',
        '2950'::oidvector,
        array['p_entry_id']::text[],
        'boolean'::regtype,
        'v'::char
      ),
      (
        'my_diary_get_exchange_entry_tags',
        '2951'::oidvector,
        array['p_entry_ids', 'entry_id', 'tag_id', 'name']::text[],
        'record'::regtype,
        's'::char
      )
  ) as expected(
    function_name, argument_types, argument_names, return_type, volatility
  )
    on expected.function_name = function_definition.proname
   and expected.argument_types = function_definition.proargtypes
   and expected.argument_names = function_definition.proargnames
   and expected.return_type = function_definition.prorettype
   and expected.volatility = function_definition.provolatile
  where namespace.nspname = 'public'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.pronargdefaults = 0
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if exact_rpc_count <> 4 then
    raise exception
      'create_exchange_entries postcondition failed: RPC definition differs';
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
       ) as privilege
       where namespace.nspname = 'public'
         and function_definition.proname in (
           'my_diary_create_exchange_entry',
           'my_diary_update_exchange_entry',
           'my_diary_soft_delete_exchange_entry',
           'my_diary_get_exchange_entry_tags'
         )
         and privilege.privilege_type = 'EXECUTE'
         and privilege.grantee not in (
           (select oid from pg_catalog.pg_roles where rolname = 'postgres'),
           (select oid from pg_catalog.pg_roles where rolname = 'authenticated')
         )
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_create_exchange_entry(uuid,text,text,text,text,text[])',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_update_exchange_entry(uuid,text,text,text,text,text[])',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_soft_delete_exchange_entry(uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_get_exchange_entry_tags(uuid[])',
       'EXECUTE'
     ) then
    raise exception
      'create_exchange_entries postcondition failed: RPC ACL differs';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'tags'
         and policyname = 'my_diary_tags_select_visible_post'
         and cmd = 'SELECT'
     )
     or not exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'post_tags'
         and policyname = 'my_diary_post_tags_select_visible_post'
         and cmd = 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'create_exchange_entries postcondition failed: existing tags changed';
  end if;
end;
$postcondition$;

commit;
