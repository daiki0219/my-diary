begin;

do $preflight$
declare
  active_admin_function_oid oid := pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_is_active_admin()'
  );
  evidence_function_oid oid := pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'
  );
  status_function_oid oid := pg_catalog.to_regprocedure(
    'public.my_diary_update_report_status(uuid,text)'
  );
  purge_function_oid oid := pg_catalog.to_regprocedure(
    'public.my_diary_purge_expired_report_evidence(uuid)'
  );
begin
  if pg_catalog.to_regrole('anon') is null
     or pg_catalog.to_regrole('authenticated') is null
     or pg_catalog.to_regrole('service_role') is null
     or pg_catalog.to_regrole('authenticator') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.reports') is null
     or pg_catalog.to_regclass(
       'public.report_exchange_entry_snapshots'
     ) is null
     or pg_catalog.to_regclass('public.report_snapshot_images') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or active_admin_function_oid is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'
     ) is null
     or evidence_function_oid is null
     or status_function_oid is null
     or purge_function_oid is null then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: required dependency missing';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.reports'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (
        (attribute.attname = 'id'
         and attribute.atttypid = 'uuid'::pg_catalog.regtype
         and attribute.attnotnull)
        or (attribute.attname = 'reporter_user_id'
            and attribute.atttypid = 'uuid'::pg_catalog.regtype
            and not attribute.attnotnull)
        or (attribute.attname = 'reported_user_id'
            and attribute.atttypid = 'uuid'::pg_catalog.regtype
            and attribute.attnotnull)
        or (attribute.attname = 'status'
            and attribute.atttypid = 'text'::pg_catalog.regtype
            and attribute.attnotnull)
        or (attribute.attname = 'evidence_delete_after'
            and attribute.atttypid =
              'timestamp with time zone'::pg_catalog.regtype
            and not attribute.attnotnull)
      )
  ) <> 5
  or not exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
      'public.report_exchange_entry_snapshots'::pg_catalog.regclass
      and attribute.attname = 'report_id'
      and attribute.atttypid = 'uuid'::pg_catalog.regtype
      and attribute.attnotnull
      and attribute.attnum > 0
      and not attribute.attisdropped
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
      'public.report_snapshot_images'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (
        (attribute.attname = 'report_id'
         and attribute.atttypid = 'uuid'::pg_catalog.regtype
         and attribute.attnotnull)
        or (attribute.attname = 'storage_path'
            and attribute.atttypid = 'text'::pg_catalog.regtype
            and attribute.attnotnull)
      )
  ) <> 2 then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: report column shape differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.reports'::pg_catalog.regclass,
      'public.report_exchange_entry_snapshots'::pg_catalog.regclass,
      'public.report_snapshot_images'::pg_catalog.regclass
    )
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 3
  or not exists (
    select 1
    from pg_catalog.pg_class as relation
    where relation.oid = 'storage.objects'::pg_catalog.regclass
      and relation.relrowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: owner or RLS differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'reports', 'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
  ) <> 3
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and policyname = 'my_diary_reports_select_active_admin'
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and with_check is null
      and pg_catalog.lower(qual) like '%from accounts account%'
      and pg_catalog.lower(qual) like '%account.role%admin%'
      and pg_catalog.lower(qual) like '%account.status%active%'
      and pg_catalog.lower(qual) not like '%reported_user_id%'
      and pg_catalog.lower(qual) not like '%reporter_user_id%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'report_exchange_entry_snapshots'
      and policyname =
        'my_diary_report_exchange_snapshots_select_active_admin'
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and with_check is null
      and pg_catalog.lower(qual) like '%from accounts account%'
      and pg_catalog.lower(qual) not like '%reported_user_id%'
      and pg_catalog.lower(qual) not like '%reporter_user_id%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'report_snapshot_images'
      and policyname =
        'my_diary_report_snapshot_images_select_active_admin'
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and with_check is null
      and pg_catalog.lower(qual) like '%from accounts account%'
      and pg_catalog.lower(qual) not like '%reported_user_id%'
      and pg_catalog.lower(qual) not like '%reporter_user_id%'
  ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: effective report policy differs';
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
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       cross join pg_catalog.unnest(array[
         'public.reports',
         'public.report_exchange_entry_snapshots',
         'public.report_snapshot_images'
       ]) as target(relation_name)
       where pg_catalog.has_table_privilege(
         denied.role_name, target.relation_name, 'SELECT, INSERT, UPDATE, DELETE'
       )
     ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: report ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where (namespace.nspname, function_definition.proname) in (
      ('my_diary_private',
       'my_diary_exchange_entry_image_evidence_select_is_allowed'),
      ('public', 'my_diary_update_report_status'),
      ('public', 'my_diary_purge_expired_report_evidence')
    )
  ) <> 3
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.pronamespace =
      'my_diary_private'::pg_catalog.regnamespace
      and function_definition.proname = 'my_diary_is_active_admin'
  ) <> 1
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargs = 0
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = active_admin_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames = array['p_storage_path']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = evidence_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames =
        array['p_report_id', 'p_status']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = status_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames = array['p_report_id']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = purge_function_oid
  ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: function catalog differs';
  end if;

  if pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%from public.accounts as account%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.user_id = auth.uid()%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.role = ''admin''%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.status = ''active''%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%my_diary_is_active_admin()%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%report_snapshot_images%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       like '%join public.reports%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%for update%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%interval ''30 days''%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       like '%reporter_user_id%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%for update%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%delete from public.report_snapshot_images%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%delete from public.report_exchange_entry_snapshots%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       like '%reporter_user_id%' then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: effective function differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', evidence_function_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', status_function_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', purge_function_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', active_admin_function_oid, 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       cross join pg_catalog.unnest(array[
         active_admin_function_oid, evidence_function_oid,
         status_function_oid, purge_function_oid
       ]) as target(function_oid)
       where pg_catalog.has_function_privilege(
         denied.role_name, target.function_oid, 'EXECUTE'
       )
     )
     or exists (
       select 1
       from pg_catalog.unnest(array[
         active_admin_function_oid, evidence_function_oid,
         status_function_oid, purge_function_oid
       ]) as target(function_oid)
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           (select function_definition.proacl
            from pg_catalog.pg_proc as function_definition
            where function_definition.oid = target.function_oid),
           pg_catalog.acldefault(
             'f',
             (select function_definition.proowner
              from pg_catalog.pg_proc as function_definition
              where function_definition.oid = target.function_oid)
           )
         )
       ) as privilege
       where privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
     ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: function ACL differs';
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
      and policyname like
        'my_diary_exchange_entry_images_storage_guard_%'
      and permissive = 'RESTRICTIVE'
  ) <> 4
  or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and cmd = 'SELECT'
      and pg_catalog.lower(coalesce(qual, '')) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed%'
  ) <> 2
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_select_report_evidence'
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and pg_catalog.lower(qual) like
        '%bucket_id = ''exchange-entry-images''::text%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed(name)%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_guard_authenticated'
      and permissive = 'RESTRICTIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and pg_catalog.lower(qual) like
        '%bucket_id <> ''exchange-entry-images''::text%'
      and pg_catalog.lower(qual) like '%from exchange_entry_images image%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_cleanup_is_allowed(name, owner_id)%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed(name)%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)%'
  ) then
    raise exception
      'harden_report_moderation_conflict_of_interest preflight failed: Storage policy differs';
  end if;
end;
$preflight$;

drop policy my_diary_reports_select_active_admin
  on public.reports;

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
  and reported_user_id <> (select auth.uid())
  and (
    reporter_user_id is null
    or reporter_user_id <> (select auth.uid())
  )
);

drop policy my_diary_report_exchange_snapshots_select_active_admin
  on public.report_exchange_entry_snapshots;

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
  and exists (
    select 1
    from public.reports as report
    where report.id = report_exchange_entry_snapshots.report_id
      and report.reported_user_id <> (select auth.uid())
      and (
        report.reporter_user_id is null
        or report.reporter_user_id <> (select auth.uid())
      )
  )
);

drop policy my_diary_report_snapshot_images_select_active_admin
  on public.report_snapshot_images;

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
  and exists (
    select 1
    from public.reports as report
    where report.id = report_snapshot_images.report_id
      and report.reported_user_id <> (select auth.uid())
      and (
        report.reporter_user_id is null
        or report.reporter_user_id <> (select auth.uid())
      )
  )
);

create or replace function
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
      join public.reports as report
        on report.id = snapshot_image.report_id
      where snapshot_image.storage_path = p_storage_path
        and report.reported_user_id <> auth.uid()
        and (
          report.reporter_user_id is null
          or report.reporter_user_id <> auth.uid()
        )
    );
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
    and report.reported_user_id <> viewer_user_id
    and (
      report.reporter_user_id is null
      or report.reporter_user_id <> viewer_user_id
    )
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

create or replace function public.my_diary_purge_expired_report_evidence(
  p_report_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
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
    and report.reported_user_id <> viewer_user_id
    and (
      report.reporter_user_id is null
      or report.reporter_user_id <> viewer_user_id
    )
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

alter function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(
    text
  ) owner to postgres;
alter function public.my_diary_update_report_status(uuid, text)
  owner to postgres;
alter function public.my_diary_purge_expired_report_evidence(uuid)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(
    text
  ) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_report_status(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_purge_expired_report_evidence(uuid)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(
    text
  ) to authenticated;
grant execute on function public.my_diary_update_report_status(uuid, text)
  to authenticated;
grant execute on function public.my_diary_purge_expired_report_evidence(uuid)
  to authenticated;

comment on function
  my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(
    text
  ) is 'Authorizes active-admin access to exact report evidence only when the caller is neither the reporter nor the reported user.';
comment on function public.my_diary_update_report_status(uuid, text)
is 'Applies valid report status transitions by an unrelated active admin.';
comment on function public.my_diary_purge_expired_report_evidence(uuid)
is 'Purges expired report evidence only for an unrelated active admin while retaining the report record.';

do $postcondition$
declare
  active_admin_function_oid oid :=
    'my_diary_private.my_diary_is_active_admin()'::pg_catalog.regprocedure;
  evidence_function_oid oid :=
    'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'::pg_catalog.regprocedure;
  status_function_oid oid :=
    'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure;
  purge_function_oid oid :=
    'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'reports', 'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and with_check is null
  ) <> 3
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and policyname = 'my_diary_reports_select_active_admin'
      and pg_catalog.lower(qual) like '%from accounts account%'
      and pg_catalog.lower(qual) like '%reported_user_id <>%auth.uid()%'
      and pg_catalog.lower(qual) like '%reporter_user_id is null%'
      and pg_catalog.lower(qual) like '%reporter_user_id <>%auth.uid()%'
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'report_exchange_entry_snapshots', 'report_snapshot_images'
      )
      and pg_catalog.lower(qual) like '%from reports report%'
      and pg_catalog.lower(qual) like '%reported_user_id <>%auth.uid()%'
      and pg_catalog.lower(qual) like '%reporter_user_id is null%'
      and pg_catalog.lower(qual) like '%reporter_user_id <>%auth.uid()%'
  ) <> 2 then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: report policy differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.reports'::pg_catalog.regclass,
      'public.report_exchange_entry_snapshots'::pg_catalog.regclass,
      'public.report_snapshot_images'::pg_catalog.regclass
    )
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 3
  or not pg_catalog.has_table_privilege(
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
     ) then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: report owner, RLS, or ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where (namespace.nspname, function_definition.proname) in (
      ('my_diary_private',
       'my_diary_exchange_entry_image_evidence_select_is_allowed'),
      ('public', 'my_diary_update_report_status'),
      ('public', 'my_diary_purge_expired_report_evidence')
    )
  ) <> 3
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.pronamespace =
      'my_diary_private'::pg_catalog.regnamespace
      and function_definition.proname = 'my_diary_is_active_admin'
  ) <> 1
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargs = 0
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = active_admin_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames = array['p_storage_path']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = evidence_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames =
        array['p_report_id', 'p_status']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = status_function_oid
  )
  or not (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames = array['p_report_id']::text[]
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = purge_function_oid
  ) then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: function catalog differs';
  end if;

  if pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%from public.accounts as account%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.user_id = auth.uid()%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.role = ''admin''%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(active_admin_function_oid)
     ) not like '%account.status = ''active''%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%join public.reports as report%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%snapshot_image.storage_path = p_storage_path%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%report.reported_user_id <> auth.uid()%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(evidence_function_oid))
       not like '%report.reporter_user_id is null%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%report.reported_user_id <> viewer_user_id%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%report.reporter_user_id is null%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%for update%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(status_function_oid))
       not like '%interval ''30 days''%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%report.reported_user_id <> viewer_user_id%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%report.reporter_user_id is null%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%evidence_delete_after <=%statement_timestamp()%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%delete from public.report_snapshot_images%'
     or pg_catalog.lower(pg_catalog.pg_get_functiondef(purge_function_oid))
       not like '%delete from public.report_exchange_entry_snapshots%' then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: function body differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', evidence_function_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', status_function_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', purge_function_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', active_admin_function_oid, 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       cross join pg_catalog.unnest(array[
         active_admin_function_oid, evidence_function_oid,
         status_function_oid, purge_function_oid
       ]) as target(function_oid)
       where pg_catalog.has_function_privilege(
         denied.role_name, target.function_oid, 'EXECUTE'
       )
     )
     or exists (
       select 1
       from pg_catalog.unnest(array[
         active_admin_function_oid, evidence_function_oid,
         status_function_oid, purge_function_oid
       ]) as target(function_oid)
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           (select function_definition.proacl
            from pg_catalog.pg_proc as function_definition
            where function_definition.oid = target.function_oid),
           pg_catalog.acldefault(
             'f',
             (select function_definition.proowner
              from pg_catalog.pg_proc as function_definition
              where function_definition.oid = target.function_oid)
           )
         )
       ) as privilege
       where privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
     ) then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: function ACL differs';
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
      and policyname like
        'my_diary_exchange_entry_images_storage_guard_%'
      and permissive = 'RESTRICTIVE'
  ) <> 4
  or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and cmd = 'SELECT'
      and pg_catalog.lower(coalesce(qual, '')) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed%'
  ) <> 2
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_select_report_evidence'
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and pg_catalog.lower(qual) like
        '%bucket_id = ''exchange-entry-images''::text%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed(name)%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_guard_authenticated'
      and permissive = 'RESTRICTIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and pg_catalog.lower(qual) like
        '%bucket_id <> ''exchange-entry-images''::text%'
      and pg_catalog.lower(qual) like '%from exchange_entry_images image%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_cleanup_is_allowed(name, owner_id)%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_evidence_select_is_allowed(name)%'
      and pg_catalog.lower(qual) like
        '%my_diary_exchange_entry_image_maintenance_delete_is_allowed(id, name)%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_exchange_entry_images_storage_select_visible_entry'
      and pg_catalog.lower(qual) like '%exchange_entry_images%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
      'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_image_cleanup_candidates_retention_check'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%removed_at + ''7 days''::interval%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reports'::pg_catalog.regclass
      and conname = 'my_diary_reports_evidence_retention_shape_check'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%resolved_at + ''30 days''::interval%'
  )
  or pg_catalog.lower(pg_catalog.pg_get_functiondef(
       'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
     )) not like '%interval ''24 hours''%'
  or pg_catalog.lower(pg_catalog.pg_get_functiondef(
       'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
     )) not like '%report_snapshot_images%' then
    raise exception
      'harden_report_moderation_conflict_of_interest postcondition failed: Storage or retention regression';
  end if;
end;
$postcondition$;

commit;
