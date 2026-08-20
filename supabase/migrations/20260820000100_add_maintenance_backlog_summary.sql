begin;

do $preflight$
begin
  if pg_catalog.to_regrole('anon') is null
     or pg_catalog.to_regrole('authenticated') is null
     or pg_catalog.to_regrole('service_role') is null
     or pg_catalog.to_regrole('authenticator') is null
     or pg_catalog.to_regclass(
       'my_diary_private.exchange_entry_image_cleanup_candidates'
     ) is null
     or pg_catalog.to_regclass('public.exchange_entry_images') is null
     or pg_catalog.to_regclass('public.report_exchange_entry_snapshots') is null
     or pg_catalog.to_regclass('public.report_snapshot_images') is null
     or pg_catalog.to_regclass('public.reports') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_active_admin()'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_list_due_exchange_image_cleanup_candidates(integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_purge_expired_report_evidence(uuid)'
     ) is null then
    raise exception
      'add_maintenance_backlog_summary preflight failed: required dependency missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    where function_definition.pronamespace =
      'public'::pg_catalog.regnamespace
      and function_definition.proname =
        'my_diary_get_maintenance_backlog_summary'
  ) then
    raise exception
      'add_maintenance_backlog_summary preflight failed: function collision';
  end if;
end;
$preflight$;

create function public.my_diary_get_maintenance_backlog_summary()
returns table (
  due_confirmed_cleanup_candidate_count bigint,
  oldest_confirmed_cleanup_due_at timestamptz,
  due_unconfirmed_orphan_count bigint,
  oldest_unconfirmed_orphan_due_at timestamptz,
  due_report_evidence_count bigint,
  oldest_report_evidence_due_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
begin
  if not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Maintenance backlog is unavailable.';
  end if;

  return query
  with confirmed_cleanup_summary as (
    select
      pg_catalog.count(*)::bigint as due_count,
      pg_catalog.min(candidate.delete_after) as oldest_due_at
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
  ),
  unconfirmed_orphan_summary as (
    select
      pg_catalog.count(*)::bigint as due_count,
      pg_catalog.min(
        storage_object.created_at + interval '24 hours'
      ) as oldest_due_at
    from storage.objects as storage_object
    where storage_object.bucket_id = 'exchange-entry-images'
      and storage_object.name ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and storage_object.owner_id =
        pg_catalog.split_part(storage_object.name, '/', 1)
      and storage_object.created_at <=
        pg_catalog.statement_timestamp() - interval '24 hours'
      and not exists (
        select 1
        from public.exchange_entry_images as image
        where image.storage_path = storage_object.name
      )
      and not exists (
        select 1
        from my_diary_private.exchange_entry_image_cleanup_candidates
          as candidate
        where candidate.storage_object_id = storage_object.id
           or candidate.storage_path = storage_object.name
      )
      and not exists (
        select 1
        from public.report_snapshot_images as snapshot_image
        where snapshot_image.storage_path = storage_object.name
      )
  ),
  report_evidence_summary as (
    select
      pg_catalog.count(*)::bigint as due_count,
      pg_catalog.min(report.evidence_delete_after) as oldest_due_at
    from public.reports as report
    where report.reported_user_id <> viewer_user_id
      and (
        report.reporter_user_id is null
        or report.reporter_user_id <> viewer_user_id
      )
      and report.status in ('resolved', 'dismissed')
      and report.evidence_delete_after is not null
      and report.evidence_delete_after <=
        pg_catalog.statement_timestamp()
      and (
        exists (
          select 1
          from public.report_exchange_entry_snapshots as snapshot
          where snapshot.report_id = report.id
        )
        or exists (
          select 1
          from public.report_snapshot_images as snapshot_image
          where snapshot_image.report_id = report.id
        )
      )
  )
  select
    confirmed_cleanup_summary.due_count,
    confirmed_cleanup_summary.oldest_due_at,
    unconfirmed_orphan_summary.due_count,
    unconfirmed_orphan_summary.oldest_due_at,
    report_evidence_summary.due_count,
    report_evidence_summary.oldest_due_at
  from confirmed_cleanup_summary
  cross join unconfirmed_orphan_summary
  cross join report_evidence_summary;
end;
$function$;

alter function public.my_diary_get_maintenance_backlog_summary()
  owner to postgres;

revoke all on function public.my_diary_get_maintenance_backlog_summary()
  from public, anon, authenticated, service_role, authenticator;
grant execute on function public.my_diary_get_maintenance_backlog_summary()
  to authenticated;

comment on function public.my_diary_get_maintenance_backlog_summary()
is 'Returns exact due counts and oldest due timestamps for maintenance work currently available to the calling active admin.';

do $postcondition$
declare
  summary_function_oid oid :=
    'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure;
begin
  if (
    select not function_definition.prosecdef
      or function_definition.provolatile <> 's'
      or function_definition.proconfig <>
        array['search_path=""']::text[]
      or function_definition.pronargs <> 0
      or function_definition.pronargdefaults <> 0
      or function_definition.prorettype <> 'record'::pg_catalog.regtype
      or function_definition.proallargtypes <> array[
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype,
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype,
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype
      ]::oid[]
      or function_definition.proargmodes <>
        array['t', 't', 't', 't', 't', 't']::"char"[]
      or function_definition.proargnames <> array[
        'due_confirmed_cleanup_candidate_count',
        'oldest_confirmed_cleanup_due_at',
        'due_unconfirmed_orphan_count',
        'oldest_unconfirmed_orphan_due_at',
        'due_report_evidence_count',
        'oldest_report_evidence_due_at'
      ]::text[]
      or pg_catalog.pg_get_userbyid(function_definition.proowner) <>
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = summary_function_oid
  )
  or not pg_catalog.has_function_privilege(
    'authenticated', summary_function_oid, 'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'anon', summary_function_oid, 'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'service_role', summary_function_oid, 'EXECUTE'
  )
  or pg_catalog.has_function_privilege(
    'authenticator', summary_function_oid, 'EXECUTE'
  )
  or exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as privilege
    where function_definition.oid = summary_function_oid
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'add_maintenance_backlog_summary postcondition failed';
  end if;
end;
$postcondition$;

commit;
