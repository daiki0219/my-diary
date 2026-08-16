begin;

do $preflight$
declare
  old_status_function_oid oid := pg_catalog.to_regprocedure(
    'public.my_diary_update_report_status(uuid,text)'
  );
begin
  if pg_catalog.to_regrole('anon') is null
     or pg_catalog.to_regrole('authenticated') is null
     or pg_catalog.to_regrole('service_role') is null
     or pg_catalog.to_regrole('authenticator') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.reports') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_active_admin()'
     ) is null
     or old_status_function_oid is null then
    raise exception
      'harden_report_status_stale_transitions preflight failed: required dependency missing';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_update_report_status(uuid,text,text)'
     ) is not null
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_proc as function_definition
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = function_definition.pronamespace
       where namespace.nspname = 'public'
         and function_definition.proname =
           'my_diary_update_report_status'
     ) <> 1 then
    raise exception
      'harden_report_status_stale_transitions preflight failed: function collision or overload differs';
  end if;

  if not (
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
    where function_definition.oid = old_status_function_oid
  )
  or not pg_catalog.has_function_privilege(
       'authenticated', old_status_function_oid, 'EXECUTE'
     )
  or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(old_status_function_oid)
     ) not like '%report.reported_user_id <> viewer_user_id%'
  or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(old_status_function_oid)
     ) not like '%report.reporter_user_id is null%'
  or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(old_status_function_oid)
     ) not like '%for update%'
  or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(old_status_function_oid)
     ) not like '%interval ''30 days''%' then
    raise exception
      'harden_report_status_stale_transitions preflight failed: old function contract differs';
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
        or (attribute.attname = 'resolved_at'
            and attribute.atttypid =
              'timestamp with time zone'::pg_catalog.regtype
            and not attribute.attnotnull)
        or (attribute.attname = 'resolved_by'
            and attribute.atttypid = 'uuid'::pg_catalog.regtype
            and not attribute.attnotnull)
        or (attribute.attname = 'evidence_delete_after'
            and attribute.atttypid =
              'timestamp with time zone'::pg_catalog.regtype
            and not attribute.attnotnull)
      )
  ) <> 7 then
    raise exception
      'harden_report_status_stale_transitions preflight failed: report column shape differs';
  end if;
end;
$preflight$;

create function public.my_diary_update_report_status(
  p_report_id uuid,
  p_expected_status text,
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
     or p_expected_status is null
     or p_expected_status not in (
       'pending', 'reviewing', 'resolved', 'dismissed'
     )
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

  if current_status is null then
    raise exception using
      errcode = '42501',
      message = 'Report status could not be updated.';
  end if;

  if current_status <> p_expected_status then
    return false;
  end if;

  if not (
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

alter function public.my_diary_update_report_status(uuid, text, text)
  owner to postgres;

revoke all on function
  public.my_diary_update_report_status(uuid, text, text)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function
  public.my_diary_update_report_status(uuid, text, text)
  to authenticated;

comment on function public.my_diary_update_report_status(uuid, text, text)
is 'Applies a valid report status transition only when an unrelated active admin supplies the locked current status.';

revoke all on function public.my_diary_update_report_status(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
drop function public.my_diary_update_report_status(uuid, text);

do $postcondition$
declare
  status_function_oid oid :=
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure;
begin
  if pg_catalog.to_regprocedure(
       'public.my_diary_update_report_status(uuid,text)'
     ) is not null
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_proc as function_definition
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = function_definition.pronamespace
       where namespace.nspname = 'public'
         and function_definition.proname =
           'my_diary_update_report_status'
     ) <> 1 then
    raise exception
      'harden_report_status_stale_transitions postcondition failed: old function or unexpected overload remains';
  end if;

  if not (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.proargnames = array[
        'p_report_id', 'p_expected_status', 'p_status'
      ]::text[]
      and function_definition.proargtypes =
        '2950 25 25'::pg_catalog.oidvector
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = status_function_oid
  ) then
    raise exception
      'harden_report_status_stale_transitions postcondition failed: successor catalog differs';
  end if;

  if pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%p_expected_status not in%pending%reviewing%resolved%dismissed%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%report.reported_user_id <> viewer_user_id%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%report.reporter_user_id is null%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%for update%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%current_status <> p_expected_status%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%return false%'
     or pg_catalog.lower(
       pg_catalog.pg_get_functiondef(status_function_oid)
     ) not like '%interval ''30 days''%' then
    raise exception
      'harden_report_status_stale_transitions postcondition failed: successor body differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', status_function_oid, 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       where pg_catalog.has_function_privilege(
         denied.role_name, status_function_oid, 'EXECUTE'
       )
     )
     or exists (
       select 1
       from pg_catalog.aclexplode(
         coalesce(
           (select function_definition.proacl
            from pg_catalog.pg_proc as function_definition
            where function_definition.oid = status_function_oid),
           pg_catalog.acldefault(
             'f',
             (select function_definition.proowner
              from pg_catalog.pg_proc as function_definition
              where function_definition.oid = status_function_oid)
           )
         )
       ) as privilege
       where privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
     ) then
    raise exception
      'harden_report_status_stale_transitions postcondition failed: successor ACL differs';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_constraint
       where conrelid = 'public.reports'::pg_catalog.regclass
         and conname = 'my_diary_reports_evidence_retention_shape_check'
         and pg_catalog.pg_get_constraintdef(oid) like
           '%resolved_at + ''30 days''::interval%'
     ) then
    raise exception
      'harden_report_status_stale_transitions postcondition failed: report retention constraint differs';
  end if;
end;
$postcondition$;

commit;
