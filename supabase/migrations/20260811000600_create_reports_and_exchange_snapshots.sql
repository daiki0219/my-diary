begin;

do $preflight$
declare
  expected_roles text[] := array[
    'anon', 'authenticated', 'service_role', 'authenticator'
  ];
begin
  if exists (
    select 1
    from pg_catalog.unnest(expected_roles) as expected(role_name)
    where not exists (
      select 1 from pg_catalog.pg_roles where rolname = expected.role_name
    )
  ) then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: required Supabase role missing';
  end if;

  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.exchange_entries') is null
     or pg_catalog.to_regclass('public.exchange_entry_tags') is null
     or pg_catalog.to_regclass('public.exchange_entry_images') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.notifications') is null
     or pg_catalog.to_regclass('storage.objects') is null then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: required relation missing';
  end if;

  if pg_catalog.to_regclass('public.reports') is not null
     or pg_catalog.to_regclass(
       'public.report_exchange_entry_snapshots'
     ) is not null
     or pg_catalog.to_regclass('public.report_snapshot_images') is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_active_admin()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_capture_exchange_report_snapshot(uuid,uuid)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_reject_report_status_transition()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_create_exchange_entry_report(uuid,text,text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_create_user_report(uuid,text,text,uuid)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_report_status(uuid,text)'
     ) is not null then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: object collision';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.accounts'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (
        (attribute.attname = 'user_id'
         and attribute.atttypid = 'uuid'::pg_catalog.regtype)
        or (attribute.attname in ('role', 'status')
            and attribute.atttypid = 'text'::pg_catalog.regtype)
      )
  ) <> 3 then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: accounts role/status differs';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_set_updated_at()'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_exchange_diary(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'
     ) is null then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: required helper missing';
  end if;

  if not (
    select function_definition.prosecdef
       and function_definition.provolatile = 'v'
       and function_definition.proconfig = array['search_path=""']::text[]
       and function_definition.proargnames =
         array['p_storage_path', 'p_owner_id']::text[]
       and function_definition.prorettype = 'boolean'::pg_catalog.regtype
       and pg_catalog.pg_get_userbyid(function_definition.proowner) =
         'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
  )
  or not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)',
    'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)',
    'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)',
    'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)',
    'EXECUTE'
  ) then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: exchange cleanup helper differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_exchange_entry_images_storage_delete_owned_orphan',
        'my_diary_exchange_entry_images_storage_guard_delete_auth'
      )
      and cmd = 'DELETE'
      and roles = array['authenticated']::name[]
  ) <> 2
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) <> 8 then
    raise exception
      'create_reports_and_exchange_snapshots preflight failed: exchange Storage policies differ';
  end if;
end;
$preflight$;

create table public.reports (
  id uuid not null default gen_random_uuid(),
  reporter_user_id uuid,
  target_type text not null,
  target_id uuid not null,
  reported_user_id uuid not null,
  reason text not null,
  details text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  constraint my_diary_reports_pkey primary key (id),
  constraint my_diary_reports_reporter_user_id_fkey
    foreign key (reporter_user_id)
    references public.accounts (user_id)
    on delete set null,
  constraint my_diary_reports_target_type_check
    check (target_type in ('exchange_entry', 'user')),
  constraint my_diary_reports_reason_check
    check (
      reason in (
        'harassment',
        'spam',
        'personal_information',
        'sexual_or_inappropriate',
        'threat_or_danger',
        'other'
      )
    ),
  constraint my_diary_reports_details_check
    check (
      details is null
      or (
        pg_catalog.char_length(details) between 1 and 2000
        and details = pg_catalog.regexp_replace(
          details, '^[[:space:]]+|[[:space:]]+$', '', 'g'
        )
      )
    ),
  constraint my_diary_reports_other_details_check
    check (reason <> 'other' or details is not null),
  constraint my_diary_reports_status_check
    check (status in ('pending', 'reviewing', 'resolved', 'dismissed')),
  constraint my_diary_reports_resolution_shape_check
    check (
      (
        status in ('pending', 'reviewing')
        and resolved_at is null
        and resolved_by is null
      )
      or (
        status in ('resolved', 'dismissed')
        and resolved_at is not null
        and resolved_by is not null
      )
    )
);

create unique index my_diary_reports_open_reporter_target_key
  on public.reports (reporter_user_id, target_type, target_id)
  where reporter_user_id is not null
    and status in ('pending', 'reviewing');

create index my_diary_reports_status_created_id_idx
  on public.reports (status, created_at desc, id desc);

create table public.report_exchange_entry_snapshots (
  report_id uuid not null,
  source_entry_id uuid,
  source_diary_id uuid not null,
  source_author_participant_id uuid,
  entry_created_at timestamptz not null,
  entry_updated_at timestamptz not null,
  captured_at timestamptz not null default now(),
  title text,
  body text not null,
  mood text,
  location_name text,
  tag_names text[] not null default array[]::text[],
  constraint my_diary_report_exchange_entry_snapshots_pkey
    primary key (report_id),
  constraint my_diary_report_exchange_entry_snapshots_report_id_fkey
    foreign key (report_id)
    references public.reports (id)
    on delete cascade
    deferrable initially deferred,
  constraint my_diary_report_exchange_entry_snapshots_source_entry_id_fkey
    foreign key (source_entry_id)
    references public.exchange_entries (id)
    on delete set null,
  constraint my_diary_report_exchange_entry_snapshots_source_author_fkey
    foreign key (source_author_participant_id)
    references public.exchange_diary_participants (id)
    on delete set null,
  constraint my_diary_report_exchange_entry_snapshots_body_check
    check (pg_catalog.char_length(body) between 1 and 10000),
  constraint my_diary_report_exchange_entry_snapshots_tag_names_check
    check (
      pg_catalog.cardinality(tag_names) between 0 and 5
      and coalesce(pg_catalog.array_ndims(tag_names), 1) = 1
      and pg_catalog.array_position(tag_names, null::text) is null
    )
);

create table public.report_snapshot_images (
  id uuid not null default gen_random_uuid(),
  report_id uuid not null,
  source_image_id uuid,
  storage_path text not null,
  sort_order smallint not null,
  mime_type text not null,
  size_bytes bigint not null,
  created_at timestamptz not null default now(),
  constraint my_diary_report_snapshot_images_pkey primary key (id),
  constraint my_diary_report_snapshot_images_report_id_fkey
    foreign key (report_id)
    references public.reports (id)
    on delete cascade
    deferrable initially deferred,
  constraint my_diary_report_snapshot_images_source_image_id_fkey
    foreign key (source_image_id)
    references public.exchange_entry_images (id)
    on delete set null,
  constraint my_diary_report_snapshot_images_report_sort_key
    unique (report_id, sort_order),
  constraint my_diary_report_snapshot_images_sort_order_check
    check (sort_order between 0 and 9),
  constraint my_diary_report_snapshot_images_storage_path_check
    check (pg_catalog.char_length(storage_path) between 1 and 1024),
  constraint my_diary_report_snapshot_images_mime_type_check
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  constraint my_diary_report_snapshot_images_size_bytes_check
    check (size_bytes between 1 and 6291456)
);

alter table public.reports owner to postgres;
alter table public.report_exchange_entry_snapshots owner to postgres;
alter table public.report_snapshot_images owner to postgres;

create function my_diary_private.my_diary_is_active_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from public.accounts as account
      where account.user_id = auth.uid()
        and account.role = 'admin'
        and account.status = 'active'
    );
$function$;

create function my_diary_private.my_diary_reject_report_status_transition()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.status is distinct from old.status
     and not (
       (old.status = 'pending'
        and new.status in ('reviewing', 'resolved', 'dismissed'))
       or (old.status = 'reviewing'
           and new.status in ('resolved', 'dismissed'))
     ) then
    raise exception using
      errcode = '23514',
      message = 'Invalid report status transition.';
  end if;

  if new.id is distinct from old.id
     or new.target_type is distinct from old.target_type
     or new.target_id is distinct from old.target_id
     or new.reported_user_id is distinct from old.reported_user_id
     or new.reason is distinct from old.reason
     or new.details is distinct from old.details
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'Report identity and evidence cannot be changed.';
  end if;

  return new;
end;
$function$;

create function
  my_diary_private.my_diary_capture_exchange_report_snapshot(
    p_report_id uuid,
    p_entry_id uuid
  )
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  locked_image_count integer;
  locked_object_count integer;
begin
  perform entry_tag.entry_id
  from public.exchange_entry_tags as entry_tag
  where entry_tag.entry_id = p_entry_id
  order by entry_tag.tag_id
  for update;

  perform image.id
  from public.exchange_entry_images as image
  where image.entry_id = p_entry_id
  order by image.id
  for update;

  get diagnostics locked_image_count = row_count;

  perform storage_object.id
  from storage.objects as storage_object
  join public.exchange_entry_images as image
    on image.entry_id = p_entry_id
   and image.storage_path = storage_object.name
  where storage_object.bucket_id = 'exchange-entry-images'
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
  for update of storage_object;

  get diagnostics locked_object_count = row_count;

  if locked_object_count <> locked_image_count then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  insert into public.report_exchange_entry_snapshots (
    report_id,
    source_entry_id,
    source_diary_id,
    source_author_participant_id,
    entry_created_at,
    entry_updated_at,
    title,
    body,
    mood,
    location_name,
    tag_names
  )
  select
    p_report_id,
    entry.id,
    entry.diary_id,
    entry.author_participant_id,
    entry.created_at,
    entry.updated_at,
    entry.title,
    entry.body,
    entry.mood,
    entry.location_name,
    coalesce((
      select pg_catalog.array_agg(tag.name order by tag.normalized_name, tag.id)
      from public.exchange_entry_tags as entry_tag
      join public.tags as tag on tag.id = entry_tag.tag_id
      where entry_tag.entry_id = entry.id
    ), array[]::text[])
  from public.exchange_entries as entry
  where entry.id = p_entry_id
    and entry.deleted_at is null
    and entry.body is not null;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  insert into public.report_snapshot_images (
    report_id,
    source_image_id,
    storage_path,
    sort_order,
    mime_type,
    size_bytes,
    created_at
  )
  select
    p_report_id,
    image.id,
    image.storage_path,
    image.sort_order,
    storage_object.metadata ->> 'mimetype',
    (storage_object.metadata ->> 'size')::bigint,
    image.created_at
  from public.exchange_entry_images as image
  join storage.objects as storage_object
    on storage_object.bucket_id = 'exchange-entry-images'
   and storage_object.name = image.storage_path
  where image.entry_id = p_entry_id
  order by image.sort_order, image.id;
end;
$function$;

create function public.my_diary_create_exchange_entry_report(
  p_entry_id uuid,
  p_reason text,
  p_details text
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
  target_user_id uuid;
  locked_entry_id uuid;
  normalized_reason text := pg_catalog.btrim(p_reason);
  normalized_details text := nullif(
    pg_catalog.regexp_replace(
      p_details, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  new_report_id uuid := gen_random_uuid();
begin
  if p_entry_id is null
     or normalized_reason is null
     or normalized_reason not in (
       'harassment',
       'spam',
       'personal_information',
       'sexual_or_inappropriate',
       'threat_or_danger',
       'other'
     )
     or (
       normalized_details is not null
       and pg_catalog.char_length(normalized_details) > 2000
     )
     or (normalized_reason = 'other' and normalized_details is null) then
    raise exception using
      errcode = '22023',
      message = 'Invalid report input.';
  end if;

  select entry.diary_id
  into target_diary_id
  from public.exchange_entries as entry
  where entry.id = p_entry_id;

  if target_diary_id is null then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  begin
    viewer_participant_id :=
      my_diary_private.my_diary_lock_exchange_diary_for_entry(
        target_diary_id, viewer_user_id, true
      );
  exception
    when others then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
  end;

  select entry.id, author.user_id
  into locked_entry_id, target_user_id
  from public.exchange_entries as entry
  join public.exchange_diary_participants as author
    on author.id = entry.author_participant_id
   and author.diary_id = entry.diary_id
  where entry.id = p_entry_id
    and entry.diary_id = target_diary_id
    and entry.deleted_at is null
    and entry.body is not null
    and entry.author_participant_id <> viewer_participant_id
    and author.user_id is not null
  for update of entry;

  if locked_entry_id is null or target_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  if exists (
    select 1
    from public.reports as existing_report
    where existing_report.reporter_user_id = viewer_user_id
      and existing_report.target_type = 'exchange_entry'
      and existing_report.target_id = locked_entry_id
      and existing_report.status in ('pending', 'reviewing')
  ) then
    raise exception using
      errcode = '23505',
      message = 'Report could not be created.';
  end if;

  perform my_diary_private.my_diary_capture_exchange_report_snapshot(
    new_report_id, locked_entry_id
  );

  begin
    insert into public.reports (
      id,
      reporter_user_id,
      target_type,
      target_id,
      reported_user_id,
      reason,
      details
    )
    values (
      new_report_id,
      viewer_user_id,
      'exchange_entry',
      locked_entry_id,
      target_user_id,
      normalized_reason,
      normalized_details
    );
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'Report could not be created.';
  end;

  return new_report_id;
end;
$function$;

create function public.my_diary_create_user_report(
  p_user_id uuid,
  p_reason text,
  p_details text,
  p_related_exchange_entry_id uuid
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
  initial_author_user_id uuid;
  viewer_participant_id uuid;
  locked_entry_id uuid;
  locked_account_count integer;
  normalized_reason text := pg_catalog.btrim(p_reason);
  normalized_details text := nullif(
    pg_catalog.regexp_replace(
      p_details, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  new_report_id uuid := gen_random_uuid();
begin
  if viewer_user_id is null
     or p_user_id is null
     or p_user_id = viewer_user_id
     or normalized_reason is null
     or normalized_reason not in (
       'harassment',
       'spam',
       'personal_information',
       'sexual_or_inappropriate',
       'threat_or_danger',
       'other'
     )
     or (
       normalized_details is not null
       and pg_catalog.char_length(normalized_details) > 2000
     )
     or (normalized_reason = 'other' and normalized_details is null) then
    if normalized_reason is null
       or normalized_reason not in (
         'harassment', 'spam', 'personal_information',
         'sexual_or_inappropriate', 'threat_or_danger', 'other'
       )
       or (normalized_details is not null
           and pg_catalog.char_length(normalized_details) > 2000)
       or (normalized_reason = 'other' and normalized_details is null) then
      raise exception using
        errcode = '22023',
        message = 'Invalid report input.';
    end if;

    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  if p_related_exchange_entry_id is null then
    perform account.user_id
    from public.accounts as account
    where account.user_id in (viewer_user_id, p_user_id)
    order by account.user_id
    for update;

    get diagnostics locked_account_count = row_count;

    if locked_account_count <> 2
       or not exists (
         select 1
         from public.accounts as viewer_account
         where viewer_account.user_id = viewer_user_id
           and viewer_account.status = 'active'
       ) then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
    end if;
  else
    select entry.diary_id, author.user_id
    into target_diary_id, initial_author_user_id
    from public.exchange_entries as entry
    join public.exchange_diary_participants as author
      on author.id = entry.author_participant_id
     and author.diary_id = entry.diary_id
    where entry.id = p_related_exchange_entry_id;

    if target_diary_id is null
       or initial_author_user_id is distinct from p_user_id then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
    end if;

    begin
      viewer_participant_id :=
        my_diary_private.my_diary_lock_exchange_diary_for_entry(
          target_diary_id, viewer_user_id, true
        );
    exception
      when others then
        raise exception using
          errcode = '42501',
          message = 'Report could not be created.';
    end;

    select entry.id
    into locked_entry_id
    from public.exchange_entries as entry
    join public.exchange_diary_participants as author
      on author.id = entry.author_participant_id
     and author.diary_id = entry.diary_id
    where entry.id = p_related_exchange_entry_id
      and entry.diary_id = target_diary_id
      and entry.deleted_at is null
      and entry.body is not null
      and entry.author_participant_id <> viewer_participant_id
      and author.user_id = p_user_id
    for update of entry;

    if locked_entry_id is null then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
    end if;
  end if;

  if exists (
    select 1
    from public.reports as existing_report
    where existing_report.reporter_user_id = viewer_user_id
      and existing_report.target_type = 'user'
      and existing_report.target_id = p_user_id
      and existing_report.status in ('pending', 'reviewing')
  ) then
    raise exception using
      errcode = '23505',
      message = 'Report could not be created.';
  end if;

  if locked_entry_id is not null then
    perform my_diary_private.my_diary_capture_exchange_report_snapshot(
      new_report_id, locked_entry_id
    );
  end if;

  begin
    insert into public.reports (
      id,
      reporter_user_id,
      target_type,
      target_id,
      reported_user_id,
      reason,
      details
    )
    values (
      new_report_id,
      viewer_user_id,
      'user',
      p_user_id,
      p_user_id,
      normalized_reason,
      normalized_details
    );
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'Report could not be created.';
  end;

  return new_report_id;
end;
$function$;

create function public.my_diary_update_report_status(
  p_report_id uuid,
  p_status text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  current_status text;
begin
  if p_report_id is null
     or p_status is null
     or p_status not in ('reviewing', 'resolved', 'dismissed')
     or not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Report status could not be updated.';
  end if;

  select report.status
  into current_status
  from public.reports as report
  where report.id = p_report_id
  for update;

  if current_status is null
     or not (
    (current_status = 'pending'
     and p_status in ('reviewing', 'resolved', 'dismissed'))
    or (current_status = 'reviewing'
        and p_status in ('resolved', 'dismissed'))
  ) then
    raise exception using
      errcode = '42501',
      message = 'Report status could not be updated.';
  end if;

  update public.reports as report
  set status = p_status,
      resolved_at = case
        when p_status in ('resolved', 'dismissed') then now()
        else null
      end,
      resolved_by = case
        when p_status in ('resolved', 'dismissed') then viewer_user_id
        else null
      end
  where report.id = p_report_id;

  return true;
end;
$function$;

create or replace function
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
    )
    and not exists (
      select 1
      from public.report_snapshot_images as snapshot_image
      where snapshot_image.storage_path = p_storage_path
    );
end;
$function$;

alter function my_diary_private.my_diary_is_active_admin()
  owner to postgres;
alter function my_diary_private.my_diary_reject_report_status_transition()
  owner to postgres;
alter function
  my_diary_private.my_diary_capture_exchange_report_snapshot(uuid, uuid)
  owner to postgres;
alter function public.my_diary_create_exchange_entry_report(uuid, text, text)
  owner to postgres;
alter function public.my_diary_create_user_report(uuid, text, text, uuid)
  owner to postgres;
alter function public.my_diary_update_report_status(uuid, text)
  owner to postgres;
alter function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  owner to postgres;

revoke all on function my_diary_private.my_diary_is_active_admin()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_reject_report_status_transition()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_capture_exchange_report_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_create_exchange_entry_report(uuid, text, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_create_user_report(uuid, text, text, uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_update_report_status(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  public.my_diary_create_exchange_entry_report(uuid, text, text)
  to authenticated;
grant execute on function
  public.my_diary_create_user_report(uuid, text, text, uuid)
  to authenticated;
grant execute on function
  public.my_diary_update_report_status(uuid, text)
  to authenticated;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  to authenticated;

create trigger my_diary_reports_reject_status_transition
before update on public.reports
for each row execute function
  my_diary_private.my_diary_reject_report_status_transition();

create trigger my_diary_reports_set_updated_at
before update on public.reports
for each row execute function public.my_diary_set_updated_at();

alter table public.reports enable row level security;
alter table public.report_exchange_entry_snapshots enable row level security;
alter table public.report_snapshot_images enable row level security;

revoke all on table public.reports
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.report_exchange_entry_snapshots
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.report_snapshot_images
  from public, anon, authenticated, service_role, authenticator;

grant select on table public.reports to authenticated;
grant select on table public.report_exchange_entry_snapshots to authenticated;
grant select on table public.report_snapshot_images to authenticated;

create policy my_diary_reports_select_active_admin
on public.reports
for select
to authenticated
using (
  exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.role = 'admin'
      and account.status = 'active'
  )
);

create policy my_diary_report_exchange_snapshots_select_active_admin
on public.report_exchange_entry_snapshots
for select
to authenticated
using (
  exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.role = 'admin'
      and account.status = 'active'
  )
);

create policy my_diary_report_snapshot_images_select_active_admin
on public.report_snapshot_images
for select
to authenticated
using (
  exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.role = 'admin'
      and account.status = 'active'
  )
);

do $postcondition$
declare
  expected_rpc_count integer;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'reports',
        'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 3 then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: table owner or RLS differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'reports',
        'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 3 then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: RLS policy differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.reports', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.reports', 'INSERT, UPDATE, DELETE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.report_exchange_entry_snapshots', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_exchange_entry_snapshots',
       'INSERT, UPDATE, DELETE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.report_snapshot_images', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_snapshot_images',
       'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'public.reports', 'SELECT'
     ) then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: table ACL differs';
  end if;

  select pg_catalog.count(*)
  into expected_rpc_count
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname in (
      'my_diary_create_exchange_entry_report',
      'my_diary_create_user_report',
      'my_diary_update_report_status'
    )
    and function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.pronargdefaults = 0
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if expected_rpc_count <> 3
     or pg_catalog.to_regprocedure(
       'public.my_diary_create_exchange_entry_report(uuid,text,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_create_user_report(uuid,text,text,uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_update_report_status(uuid,text)'
     ) is null
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_create_exchange_entry_report(uuid,text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_create_user_report(uuid,text,text,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_update_report_status(uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.my_diary_update_report_status(uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.my_diary_create_user_report(uuid,text,text,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator',
       'public.my_diary_create_exchange_entry_report(uuid,text,text)',
       'EXECUTE'
     ) then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: RPC catalog or ACL differs';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'my_diary_private.my_diary_is_active_admin()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'my_diary_private.my_diary_capture_exchange_report_snapshot(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: private helper ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) <> 8
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_entries',
        'exchange_entry_tags',
        'exchange_entry_images'
      )
  ) <> 5
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) <> 2 then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: existing RLS changed';
  end if;

  if pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_post_image_path_is_referenced(text)'
     ) is null then
    raise exception
      'create_reports_and_exchange_snapshots postcondition failed: post image foundation changed';
  end if;
end;
$postcondition$;

commit;
