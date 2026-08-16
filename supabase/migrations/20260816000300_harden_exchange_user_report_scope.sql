begin;

do $preflight$
declare
  expected_roles text[] := array[
    'anon', 'authenticated', 'service_role', 'authenticator'
  ];
  old_rpc regprocedure :=
    'public.my_diary_create_user_report(uuid,text,text,uuid)'::regprocedure;
begin
  if exists (
    select 1
    from pg_catalog.unnest(expected_roles) as expected(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role_definition
      where role_definition.rolname = expected.role_name
    )
  ) then
    raise exception
      'harden_exchange_user_report_scope preflight failed: required Supabase role missing';
  end if;

  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.exchange_entries') is null
     or pg_catalog.to_regclass('public.reports') is null
     or pg_catalog.to_regclass(
       'public.report_exchange_entry_snapshots'
     ) is null
     or pg_catalog.to_regclass('public.report_snapshot_images') is null then
    raise exception
      'harden_exchange_user_report_scope preflight failed: required relation missing';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_capture_exchange_report_snapshot(uuid,uuid)'
     ) is null then
    raise exception
      'harden_exchange_user_report_scope preflight failed: RPC collision or helper missing';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname = 'my_diary_create_user_report'
  ) <> 1
  or not (
    select function_definition.prosecdef
       and function_definition.provolatile = 'v'
       and function_definition.proconfig = array['search_path=""']::text[]
       and function_definition.proargnames = array[
         'p_user_id', 'p_reason', 'p_details',
         'p_related_exchange_entry_id'
       ]::text[]
       and function_definition.proargtypes =
         '2950 25 25 2950'::pg_catalog.oidvector
       and function_definition.prorettype = 'uuid'::pg_catalog.regtype
       and function_definition.pronargdefaults = 0
       and pg_catalog.pg_get_userbyid(function_definition.proowner) =
         'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = old_rpc
  ) then
    raise exception
      'harden_exchange_user_report_scope preflight failed: old generic RPC differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', old_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege('anon', old_rpc, 'EXECUTE')
     or pg_catalog.has_function_privilege(
       'service_role', old_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', old_rpc, 'EXECUTE'
     ) then
    raise exception
      'harden_exchange_user_report_scope preflight failed: old generic RPC ACL differs';
  end if;

  if not (
    select function_definition.prosecdef
       and function_definition.provolatile = 'v'
       and function_definition.proconfig = array['search_path=""']::text[]
       and function_definition.proargnames = array[
         'p_diary_id', 'p_viewer_user_id', 'p_allow_archived'
       ]::text[]
       and function_definition.prorettype = 'uuid'::pg_catalog.regtype
       and pg_catalog.pg_get_userbyid(function_definition.proowner) =
         'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)'::regprocedure
  ) then
    raise exception
      'harden_exchange_user_report_scope preflight failed: diary lock helper differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.reports', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.reports', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_exchange_entry_snapshots',
       'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_snapshot_images',
       'INSERT, UPDATE, DELETE'
     )
     or not exists (
       select 1
       from pg_catalog.pg_indexes as index_definition
       where index_definition.schemaname = 'public'
         and index_definition.indexname =
           'my_diary_reports_open_reporter_target_key'
         and index_definition.indexdef like
           '%UNIQUE%reporter_user_id, target_type, target_id%'
         and index_definition.indexdef like
           '%status = ANY%pending%reviewing%'
     ) then
    raise exception
      'harden_exchange_user_report_scope preflight failed: report ACL or duplicate semantics differ';
  end if;
end;
$preflight$;

create function public.my_diary_create_exchange_user_report(
  p_diary_id uuid,
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
  viewer_participant_id uuid;
  target_user_id uuid;
  locked_entry_id uuid;
begin
  if p_diary_id is null or viewer_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  begin
    viewer_participant_id :=
      my_diary_private.my_diary_lock_exchange_diary_for_entry(
        p_diary_id, viewer_user_id, true
      );
  exception
    when others then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
  end;

  select participant.user_id
  into target_user_id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
    and participant.id <> viewer_participant_id;

  if target_user_id is null or target_user_id = viewer_user_id then
    raise exception using
      errcode = '42501',
      message = 'Report could not be created.';
  end if;

  if p_related_exchange_entry_id is not null then
    select entry.id
    into locked_entry_id
    from public.exchange_entries as entry
    join public.exchange_diary_participants as author
      on author.id = entry.author_participant_id
     and author.diary_id = entry.diary_id
    where entry.id = p_related_exchange_entry_id
      and entry.diary_id = p_diary_id
      and entry.deleted_at is null
      and entry.body is not null
      and entry.author_participant_id <> viewer_participant_id
      and author.user_id = target_user_id
    for update of entry;

    if locked_entry_id is null then
      raise exception using
        errcode = '42501',
        message = 'Report could not be created.';
    end if;
  end if;

  return public.my_diary_create_user_report(
    target_user_id,
    p_reason,
    p_details,
    p_related_exchange_entry_id
  );
end;
$function$;

alter function
  public.my_diary_create_exchange_user_report(uuid, text, text, uuid)
  owner to postgres;

revoke all on function
  public.my_diary_create_exchange_user_report(uuid, text, text, uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_create_user_report(uuid, text, text, uuid)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  public.my_diary_create_exchange_user_report(uuid, text, text, uuid)
  to authenticated;

do $postcondition$
declare
  successor_rpc regprocedure :=
    'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure;
  old_rpc regprocedure :=
    'public.my_diary_create_user_report(uuid,text,text,uuid)'::regprocedure;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname =
        'my_diary_create_exchange_user_report'
  ) <> 1
  or not (
    select function_definition.prosecdef
       and function_definition.provolatile = 'v'
       and function_definition.proconfig = array['search_path=""']::text[]
       and function_definition.proargnames = array[
         'p_diary_id', 'p_reason', 'p_details',
         'p_related_exchange_entry_id'
       ]::text[]
       and function_definition.proargtypes =
         '2950 25 25 2950'::pg_catalog.oidvector
       and function_definition.prorettype = 'uuid'::pg_catalog.regtype
       and function_definition.pronargdefaults = 0
       and pg_catalog.pg_get_userbyid(function_definition.proowner) =
         'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid = successor_rpc
  ) then
    raise exception
      'harden_exchange_user_report_scope postcondition failed: successor RPC catalog differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', successor_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege('anon', successor_rpc, 'EXECUTE')
     or pg_catalog.has_function_privilege(
       'service_role', successor_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', successor_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', old_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege('anon', old_rpc, 'EXECUTE')
     or pg_catalog.has_function_privilege(
       'service_role', old_rpc, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', old_rpc, 'EXECUTE'
     ) then
    raise exception
      'harden_exchange_user_report_scope postcondition failed: report RPC ACL differs';
  end if;

  if pg_catalog.to_regprocedure(
       'public.my_diary_create_user_report(uuid,text,text,uuid)'
     ) is null
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.reports', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_exchange_entry_snapshots',
       'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.report_snapshot_images',
       'INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'harden_exchange_user_report_scope postcondition failed: generic RPC or table ACL differs';
  end if;
end;
$postcondition$;

commit;
