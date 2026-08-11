begin;

do $preflight$
declare
  update_function_oid oid;
  cleanup_function_oid oid;
  status_function_oid oid;
begin
  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_entries') is null
     or pg_catalog.to_regclass('public.exchange_entry_images') is null
     or pg_catalog.to_regclass('public.reports') is null
     or pg_catalog.to_regclass(
       'public.report_exchange_entry_snapshots'
     ) is null
     or pg_catalog.to_regclass('public.report_snapshot_images') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_active_admin()'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_exchange_diary(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_prepare_exchange_entry_tags(text[])'
     ) is null
     or pg_catalog.to_regprocedure('storage.allow_only_operation(text)')
       is null
     or pg_catalog.to_regprocedure('storage.allow_any_operation(text[])')
       is null then
    raise exception
      'harden_exchange_image_evidence_retention preflight failed: required dependency missing';
  end if;

  if pg_catalog.to_regclass(
       'my_diary_private.exchange_entry_image_cleanup_candidates'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_attribute as attribute
       where attribute.attrelid = 'public.reports'::pg_catalog.regclass
         and attribute.attname = 'evidence_delete_after'
         and attribute.attnum > 0
         and not attribute.attisdropped
     )
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_list_due_exchange_image_cleanup_candidates(integer)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_complete_exchange_image_cleanup(text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.my_diary_purge_expired_report_evidence(uuid)'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname in (
           'my_diary_exchange_entry_images_storage_select_report_evidence',
           'my_diary_exchange_entry_images_storage_select_due_maintenance',
           'my_diary_exchange_entry_images_storage_delete_due_maintenance'
         )
     ) then
    raise exception
      'harden_exchange_image_evidence_retention preflight failed: object collision';
  end if;

  select function_definition.oid
  into update_function_oid
  from pg_catalog.pg_proc as function_definition
  where function_definition.oid =
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure
    and function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.proargnames = array[
      'p_entry_id', 'p_title', 'p_body', 'p_mood', 'p_location_name',
      'p_tags', 'p_image_manifest'
    ]::text[]
    and function_definition.prorettype = 'jsonb'::pg_catalog.regtype
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  select function_definition.oid
  into cleanup_function_oid
  from pg_catalog.pg_proc as function_definition
  where function_definition.oid =
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
    and function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.proargnames =
      array['p_storage_path', 'p_owner_id']::text[]
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  select function_definition.oid
  into status_function_oid
  from pg_catalog.pg_proc as function_definition
  where function_definition.oid =
    'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure
    and function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.proargnames =
      array['p_report_id', 'p_status']::text[]
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if update_function_oid is null
     or pg_catalog.pg_get_functiondef(update_function_oid)
          not like '%removedImagePaths%'
     or cleanup_function_oid is null
     or pg_catalog.pg_get_functiondef(cleanup_function_oid)
          not like '%report_snapshot_images%'
     or status_function_oid is null then
    raise exception
      'harden_exchange_image_evidence_retention preflight failed: effective function differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) <> 8
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_guard_authenticated'
      and cmd = 'SELECT'
      and permissive = 'RESTRICTIVE'
      and roles = array['authenticated']::name[]
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_guard_delete_auth'
      and cmd = 'DELETE'
      and permissive = 'RESTRICTIVE'
      and roles = array['authenticated']::name[]
  ) then
    raise exception
      'harden_exchange_image_evidence_retention preflight failed: Storage policy composition differs';
  end if;
end;
$preflight$;

create table my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id uuid not null,
  storage_path text not null,
  image_id uuid not null,
  entry_id uuid not null,
  diary_id uuid not null,
  owner_user_id uuid not null,
  removed_at timestamptz not null,
  delete_after timestamptz not null,
  constraint my_diary_exchange_image_cleanup_candidates_pkey
    primary key (storage_object_id),
  constraint my_diary_exchange_image_cleanup_candidates_storage_path_key
    unique (storage_path),
  constraint my_diary_exchange_image_cleanup_candidates_path_length_check
    check (pg_catalog.char_length(storage_path) between 1 and 1024),
  constraint my_diary_exchange_image_cleanup_candidates_path_shape_check
    check (
      storage_path ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and pg_catalog.split_part(storage_path, '/', 1)::uuid = owner_user_id
      and pg_catalog.split_part(storage_path, '/', 2)::uuid = diary_id
      and pg_catalog.split_part(storage_path, '/', 3)::uuid = entry_id
      and pg_catalog.split_part(storage_path, '/', 4)::uuid = image_id
    ),
  constraint my_diary_exchange_image_cleanup_candidates_retention_check
    check (delete_after = removed_at + interval '7 days')
);

create index my_diary_exchange_image_cleanup_candidates_due_idx
  on my_diary_private.exchange_entry_image_cleanup_candidates (
    delete_after,
    storage_path
  );

alter table my_diary_private.exchange_entry_image_cleanup_candidates
  owner to postgres;
alter table my_diary_private.exchange_entry_image_cleanup_candidates
  enable row level security;

revoke all on table
  my_diary_private.exchange_entry_image_cleanup_candidates
  from public, anon, authenticated, service_role, authenticator;

-- Existing unreferenced objects cannot be classified reliably as abandoned
-- uploads or previously confirmed images. Treat all of them uniformly as
-- candidates from migration time so old report evidence cannot become
-- user-deletable when the general cleanup helper stops consulting evidence.
-- The migration-wide lock closes the policy-switch window against concurrent
-- Storage INSERT/DELETE while leaving ordinary object reads available.
lock table only storage.objects in share row exclusive mode;

insert into my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id,
  storage_path,
  image_id,
  entry_id,
  diary_id,
  owner_user_id,
  removed_at,
  delete_after
)
select
  storage_object.id,
  storage_object.name,
  pg_catalog.split_part(storage_object.name, '/', 4)::uuid,
  pg_catalog.split_part(storage_object.name, '/', 3)::uuid,
  pg_catalog.split_part(storage_object.name, '/', 2)::uuid,
  pg_catalog.split_part(storage_object.name, '/', 1)::uuid,
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp() + interval '7 days'
from storage.objects as storage_object
where storage_object.bucket_id = 'exchange-entry-images'
  and storage_object.name ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and storage_object.owner_id =
    pg_catalog.split_part(storage_object.name, '/', 1)
  and not exists (
    select 1
    from public.exchange_entry_images as image
    where image.storage_path = storage_object.name
  )
order by storage_object.name, storage_object.id;

alter table public.reports
  add column evidence_delete_after timestamptz;

-- Preserve the existing moderation updated_at value during the conservative
-- backfill. The EXCLUSIVE lock prevents a concurrent status RPC from crossing
-- the temporary trigger-disable window; the transaction restores trigger state
-- and rows together on failure.
lock table only public.reports in exclusive mode;
alter table public.reports
  disable trigger my_diary_reports_set_updated_at;

update public.reports as report
set evidence_delete_after = greatest(
  report.resolved_at + interval '30 days',
  pg_catalog.statement_timestamp() + interval '30 days'
)
where report.status in ('resolved', 'dismissed');

alter table public.reports
  enable trigger my_diary_reports_set_updated_at;

alter table public.reports
  add constraint my_diary_reports_evidence_retention_shape_check
  check (
    (
      status in ('pending', 'reviewing')
      and evidence_delete_after is null
    )
    or (
      status in ('resolved', 'dismissed')
      and evidence_delete_after is not null
      and evidence_delete_after >= resolved_at + interval '30 days'
    )
  );

create index my_diary_report_snapshot_images_storage_path_idx
  on public.report_snapshot_images (storage_path);

create or replace function
  my_diary_private.my_diary_reject_report_status_transition()
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

  if new.status is not distinct from old.status
     and new.evidence_delete_after is distinct from
       old.evidence_delete_after then
    raise exception using
      errcode = '23514',
      message = 'Report evidence retention cannot be changed.';
  end if;

  if new.status is distinct from old.status
     and new.status = 'reviewing'
     and new.evidence_delete_after is not null then
    raise exception using
      errcode = '23514',
      message = 'Invalid report evidence retention.';
  end if;

  if new.status is distinct from old.status
     and new.status in ('resolved', 'dismissed')
     and (
       new.resolved_at is null
       or new.evidence_delete_after is distinct from
          new.resolved_at + interval '30 days'
     ) then
    raise exception using
      errcode = '23514',
      message = 'Invalid report evidence retention.';
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


create or replace function public.my_diary_update_report_status(
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
  transitioned_at timestamptz := pg_catalog.statement_timestamp();
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
        when p_status in ('resolved', 'dismissed') then transitioned_at
        else null
      end,
      resolved_by = case
        when p_status in ('resolved', 'dismissed') then viewer_user_id
        else null
      end,
      evidence_delete_after = case
        when p_status in ('resolved', 'dismissed')
          then transitioned_at + interval '30 days'
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
declare
  locked_storage_object_id uuid;
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

  select storage_object.id
  into locked_storage_object_id
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
      from my_diary_private.exchange_entry_image_cleanup_candidates
        as candidate
      where candidate.storage_object_id = locked_storage_object_id
        and candidate.storage_path = p_storage_path
    );
end;
$function$;

create function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(
    p_storage_path text
  )
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    my_diary_private.my_diary_is_active_admin()
    and exists (
      select 1
      from public.report_snapshot_images as snapshot_image
      where snapshot_image.storage_path = p_storage_path
    );
$function$;

create function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    p_storage_object_id uuid,
    p_storage_path text
  )
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not my_diary_private.my_diary_is_active_admin()
     or not storage.allow_only_operation('storage.object.delete_many')
     or p_storage_path !~
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  perform storage_object.id
  from storage.objects as storage_object
  where storage_object.bucket_id = 'exchange-entry-images'
    and storage_object.id = p_storage_object_id
    and storage_object.name = p_storage_path
  for update;

  if not found then
    return false;
  end if;

  perform candidate.storage_path
  from my_diary_private.exchange_entry_image_cleanup_candidates as candidate
  where candidate.storage_object_id = p_storage_object_id
    and candidate.storage_path = p_storage_path
    and candidate.owner_user_id::text = (
      select storage_object.owner_id
      from storage.objects as storage_object
      where storage_object.bucket_id = 'exchange-entry-images'
        and storage_object.id = p_storage_object_id
        and storage_object.name = p_storage_path
    )
    and candidate.delete_after <= pg_catalog.statement_timestamp()
  for update;

  if not found then
    return false;
  end if;

  return not exists (
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

create function public.my_diary_list_due_exchange_image_cleanup_candidates(
  p_limit integer
)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_limit is null
     or p_limit not between 1 and 100
     or not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Exchange image maintenance is unavailable.';
  end if;

  return array(
    select candidate.storage_path
    from my_diary_private.exchange_entry_image_cleanup_candidates
      as candidate
    where candidate.delete_after <= pg_catalog.statement_timestamp()
      and not exists (
        select 1
        from public.exchange_entry_images as image
        where image.storage_path = candidate.storage_path
      )
      and not exists (
        select 1
        from public.report_snapshot_images as snapshot_image
        where snapshot_image.storage_path = candidate.storage_path
      )
      and (
        not exists (
          select 1
          from storage.objects as storage_object
          where storage_object.bucket_id = 'exchange-entry-images'
            and storage_object.name = candidate.storage_path
        )
        or exists (
          select 1
          from storage.objects as storage_object
          where storage_object.bucket_id = 'exchange-entry-images'
            and storage_object.id = candidate.storage_object_id
            and storage_object.name = candidate.storage_path
        )
      )
    order by candidate.delete_after, candidate.storage_path
    limit p_limit
  );
end;
$function$;

create function public.my_diary_complete_exchange_image_cleanup(
  p_storage_path text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if p_storage_path is null
     or not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Exchange image maintenance is unavailable.';
  end if;

  perform candidate.storage_path
  from my_diary_private.exchange_entry_image_cleanup_candidates as candidate
  where candidate.storage_path = p_storage_path
    and candidate.delete_after <= pg_catalog.statement_timestamp()
  for update;

  if not found
     or exists (
       select 1
       from storage.objects as storage_object
       where storage_object.bucket_id = 'exchange-entry-images'
         and storage_object.name = p_storage_path
     )
     or exists (
       select 1
       from public.exchange_entry_images as image
       where image.storage_path = p_storage_path
     )
     or exists (
       select 1
       from public.report_snapshot_images as snapshot_image
       where snapshot_image.storage_path = p_storage_path
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange image maintenance is unavailable.';
  end if;

  delete from my_diary_private.exchange_entry_image_cleanup_candidates
    as candidate
  where candidate.storage_path = p_storage_path;

  return true;
end;
$function$;

create function public.my_diary_purge_expired_report_evidence(
  p_report_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target_report_id uuid;
begin
  if p_report_id is null
     or not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Report evidence could not be purged.';
  end if;

  select report.id
  into target_report_id
  from public.reports as report
  where report.id = p_report_id
    and report.status in ('resolved', 'dismissed')
    and report.evidence_delete_after is not null
    and report.evidence_delete_after <= pg_catalog.statement_timestamp()
  for update;

  if target_report_id is null then
    raise exception using
      errcode = '42501',
      message = 'Report evidence could not be purged.';
  end if;

  perform snapshot_image.id
  from public.report_snapshot_images as snapshot_image
  where snapshot_image.report_id = target_report_id
  order by snapshot_image.storage_path, snapshot_image.id
  for update;

  perform storage_object.id
  from storage.objects as storage_object
  join public.report_snapshot_images as snapshot_image
    on snapshot_image.report_id = target_report_id
   and snapshot_image.storage_path = storage_object.name
  where storage_object.bucket_id = 'exchange-entry-images'
  order by storage_object.name, storage_object.id
  for update of storage_object;

  delete from public.report_snapshot_images as snapshot_image
  where snapshot_image.report_id = target_report_id;

  delete from public.report_exchange_entry_snapshots as snapshot
  where snapshot.report_id = target_report_id;

  return true;
end;
$function$;

-- The update RPC is redefined below so candidate creation and relation removal
-- remain one transaction and the client no longer receives cleanup paths.
create or replace function public.my_diary_update_exchange_entry_with_images(
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
  canonical_tag text;
  resolved_tag_id uuid;
  manifest_item jsonb;
  manifest_index integer;
  existing_id_text text;
  new_path text;
  path_pattern text;
  locked_row_count integer;
  removed_image_count integer;
  removal_time timestamptz := pg_catalog.statement_timestamp();
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

  -- Reconfirming the same physical object clears its old candidate inside the
  -- object lock. A later removal will start a fresh seven-day clock.
  delete from my_diary_private.exchange_entry_image_cleanup_candidates
    as candidate
  where candidate.storage_path = any(new_paths);

  select pg_catalog.count(*)
  into removed_image_count
  from public.exchange_entry_images as image
  where image.entry_id = locked_entry_id
    and not image.id = any(retained_ids)
    and not image.storage_path = any(new_paths);

  perform storage_object.id
  from storage.objects as storage_object
  join public.exchange_entry_images as image
    on image.entry_id = locked_entry_id
   and image.storage_path = storage_object.name
  where storage_object.bucket_id = 'exchange-entry-images'
    and not image.id = any(retained_ids)
    and not image.storage_path = any(new_paths)
  order by storage_object.name, storage_object.id
  for update of storage_object;

  get diagnostics locked_row_count = row_count;

  if locked_row_count <> removed_image_count then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  insert into my_diary_private.exchange_entry_image_cleanup_candidates (
    storage_object_id,
    storage_path,
    image_id,
    entry_id,
    diary_id,
    owner_user_id,
    removed_at,
    delete_after
  )
  select
    storage_object.id,
    image.storage_path,
    image.id,
    image.entry_id,
    target_diary_id,
    viewer_user_id,
    removal_time,
    removal_time + interval '7 days'
  from public.exchange_entry_images as image
  join storage.objects as storage_object
    on storage_object.bucket_id = 'exchange-entry-images'
   and storage_object.name = image.storage_path
  where image.entry_id = locked_entry_id
    and not image.id = any(retained_ids)
    and not image.storage_path = any(new_paths)
  order by image.storage_path, storage_object.id
  on conflict (storage_object_id) do update
  set storage_path = excluded.storage_path,
      image_id = excluded.image_id,
      entry_id = excluded.entry_id,
      diary_id = excluded.diary_id,
      owner_user_id = excluded.owner_user_id,
      removed_at = excluded.removed_at,
      delete_after = excluded.delete_after;

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

  return pg_catalog.jsonb_build_object('entryId', locked_entry_id);
end;
$function$;

alter function
  my_diary_private.my_diary_reject_report_status_transition()
  owner to postgres;
alter function public.my_diary_update_report_status(uuid, text)
  owner to postgres;
alter function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  owner to postgres;
alter function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)
  owner to postgres;
alter function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid, text)
  owner to postgres;
alter function
  public.my_diary_list_due_exchange_image_cleanup_candidates(integer)
  owner to postgres;
alter function public.my_diary_complete_exchange_image_cleanup(text)
  owner to postgres;
alter function public.my_diary_purge_expired_report_evidence(uuid)
  owner to postgres;
alter function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) owner to postgres;

revoke all on function
  my_diary_private.my_diary_reject_report_status_transition()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_report_status(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_list_due_exchange_image_cleanup_candidates(integer)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_complete_exchange_image_cleanup(text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_purge_expired_report_evidence(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_update_report_status(uuid, text)
  to authenticated;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text, text)
  to authenticated;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)
  to authenticated;
grant execute on function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid, text)
  to authenticated;
grant execute on function
  public.my_diary_list_due_exchange_image_cleanup_candidates(integer)
  to authenticated;
grant execute on function public.my_diary_complete_exchange_image_cleanup(text)
  to authenticated;
grant execute on function public.my_diary_purge_expired_report_evidence(uuid)
  to authenticated;
grant execute on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) to authenticated;

comment on table
  my_diary_private.exchange_entry_image_cleanup_candidates
is 'Evidence-agnostic retention ledger for confirmed exchange images removed from entry manifests.';
comment on column
  public.reports.evidence_delete_after
is 'Earliest trusted purge time for terminal report snapshot evidence; NULL while open.';
comment on function
  public.my_diary_list_due_exchange_image_cleanup_candidates(integer)
is 'Lists only due, unreferenced exchange image paths for active-admin maintenance.';
comment on function public.my_diary_complete_exchange_image_cleanup(text)
is 'Removes a due cleanup candidate only after active-admin Storage deletion is committed.';
comment on function public.my_diary_purge_expired_report_evidence(uuid)
is 'Purges expired exchange-entry snapshot evidence while retaining the report record.';
comment on function public.my_diary_update_exchange_entry_with_images(
  uuid, text, text, text, text, text[], jsonb
) is 'Atomically updates an exchange entry and image manifest, retaining removed confirmed images for trusted cleanup.';

create policy my_diary_exchange_entry_images_storage_select_report_evidence
on storage.objects
for select
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and my_diary_private
    .my_diary_exchange_entry_image_evidence_select_is_allowed(name)
);

-- Storage delete-many needs SELECT as well as DELETE. This branch is operation
-- scoped, so it does not grant normal admin download/list access to candidates.
create policy my_diary_exchange_entry_images_storage_select_due_maintenance
on storage.objects
for select
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)
);

drop policy my_diary_exchange_entry_images_storage_guard_authenticated
  on storage.objects;

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
  or my_diary_private
    .my_diary_exchange_entry_image_evidence_select_is_allowed(name)
  or my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)
);

create policy my_diary_exchange_entry_images_storage_delete_due_maintenance
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'exchange-entry-images'
  and storage.allow_only_operation('storage.object.delete_many')
  and my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)
);

drop policy my_diary_exchange_entry_images_storage_guard_delete_auth
  on storage.objects;

create policy my_diary_exchange_entry_images_storage_guard_delete_auth
on storage.objects
as restrictive
for delete
to authenticated
using (
  bucket_id <> 'exchange-entry-images'
  or (
    storage.allow_only_operation('storage.object.delete_many')
    and (
      my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
        name, owner_id
      )
      or my_diary_private
        .my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)
    )
  )
);

do $postcondition$
declare
  candidate_table_oid oid :=
    'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass;
  update_function_oid oid :=
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure;
  cleanup_function_oid oid :=
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = candidate_table_oid
      and attribute.attnum > 0
      and not attribute.attisdropped
      and attribute.attname in (
        'storage_object_id', 'storage_path', 'image_id', 'entry_id',
        'diary_id', 'owner_user_id', 'removed_at', 'delete_after'
      )
  ) <> 8
  or not (
    select relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
    from pg_catalog.pg_class as relation
    where relation.oid = candidate_table_oid
  )
  or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'authenticated', 'service_role', 'authenticator']
    ) as application_role(role_name)
    where pg_catalog.has_table_privilege(
      application_role.role_name,
      candidate_table_oid,
      'SELECT, INSERT, UPDATE, DELETE'
    )
  ) then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: candidate privacy differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reports'::pg_catalog.regclass
      and conname = 'my_diary_reports_evidence_retention_shape_check'
      and contype = 'c'
  )
  or exists (
    select 1
    from public.reports as report
    where (
      report.status in ('pending', 'reviewing')
      and report.evidence_delete_after is not null
    ) or (
      report.status in ('resolved', 'dismissed')
      and (
        report.evidence_delete_after is null
        or report.evidence_delete_after <
          report.resolved_at + interval '30 days'
      )
    )
  )
  or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname =
        'my_diary_report_snapshot_images_storage_path_idx'
  ) then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: report retention differs';
  end if;

  if pg_catalog.pg_get_functiondef(update_function_oid)
       like '%removedImagePaths%'
     or pg_catalog.pg_get_functiondef(update_function_oid)
       not like '%exchange_entry_image_cleanup_candidates%'
     or pg_catalog.pg_get_functiondef(cleanup_function_oid)
       like '%report_snapshot_images%'
     or pg_catalog.pg_get_functiondef(cleanup_function_oid)
       not like '%exchange_entry_image_cleanup_candidates%' then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: update or user cleanup contract differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid in (
      'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure,
      'public.my_diary_complete_exchange_image_cleanup(text)'::pg_catalog.regprocedure,
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure,
      update_function_oid
    )
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) <> 5
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'public.my_diary_list_due_exchange_image_cleanup_candidates(integer)'::pg_catalog.regprocedure
  ) then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: function hardening differs';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as application_role(role_name)
    cross join pg_catalog.unnest(array[
      'public.my_diary_list_due_exchange_image_cleanup_candidates(integer)',
      'public.my_diary_complete_exchange_image_cleanup(text)',
      'public.my_diary_purge_expired_report_evidence(uuid)'
    ]) as target_function(function_name)
    where pg_catalog.has_function_privilege(
      application_role.role_name,
      target_function.function_name,
      'EXECUTE'
    )
  ) then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: maintenance ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) <> 11
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_guard_%'
      and permissive = 'RESTRICTIVE'
  ) <> 4
  or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ) then
    raise exception
      'harden_exchange_image_evidence_retention postcondition failed: Storage policy differs';
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
      'harden_exchange_image_evidence_retention postcondition failed: Storage owner or RLS differs';
  end if;
end;
$postcondition$;

commit;
