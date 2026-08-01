begin;

do $preflight$
declare
  expected_source constant text := $function_body$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog','information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%'
    THEN
      BEGIN
        EXECUTE format(
          'alter table if exists %s enable row level security',
          cmd.object_identity
        );
        RAISE LOG
          'rls_auto_enable: enabled RLS on %',
          cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG
            'rls_auto_enable: failed to enable RLS on %',
            cmd.object_identity;
      END;
    ELSE
      RAISE LOG
        'rls_auto_enable: skip % (either system schema or not in enforced list: %.)',
        cmd.object_identity,
        cmd.schema_name;
    END IF;
  END LOOP;
END;
$function_body$;
  function_count integer;
  zero_argument_count integer;
  function_oid oid;
  function_source text;
  event_trigger_count integer;
begin
  if exists (
    select 1
    from unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role
      where role.rolname = required.role_name
    )
  ) then
    raise exception
      'rls_auto_enable preflight failed: a required Supabase role is missing';
  end if;

  select
    count(*),
    count(*) filter (where function.pronargs = 0)
  into function_count, zero_argument_count
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'rls_auto_enable';

  if function_count > 1
     or (function_count = 1 and zero_argument_count <> 1) then
    raise exception
      'rls_auto_enable preflight failed: unexpected overloads exist';
  end if;

  if function_count = 0 then
    if current_user <> 'postgres' then
      raise exception
        'rls_auto_enable preflight failed: fresh creation must be owned by postgres';
    end if;

    perform pg_catalog.set_config(
      'my_diary.rls_auto_enable_oid_before',
      '',
      true
    );
  else
    select function.oid, function.prosrc
    into function_oid, function_source
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
      and function.prokind = 'f'
      and function.prorettype = 'event_trigger'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.prosecdef
      and function.provolatile = 'v'
      and function.proparallel = 'u'
      and function.proconfig = array['search_path=pg_catalog']::text[]
      and not exists (
        select 1
        from pg_catalog.pg_depend as dependency
        where dependency.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
          and dependency.objid = function.oid
          and dependency.deptype = 'e'
      );

    if function_oid is null then
      raise exception
        'rls_auto_enable preflight failed: existing function attributes differ';
    end if;

    if pg_catalog.regexp_replace(
         function_source,
         '[[:space:]]+',
         '',
         'g'
       ) <> pg_catalog.regexp_replace(
         expected_source,
         '[[:space:]]+',
         '',
         'g'
       ) then
      raise exception
        'rls_auto_enable preflight failed: existing function body differs';
    end if;

    perform pg_catalog.set_config(
      'my_diary.rls_auto_enable_oid_before',
      function_oid::text,
      true
    );
  end if;

  select count(*)
  into event_trigger_count
  from pg_catalog.pg_event_trigger
  where evtname = 'ensure_rls';

  if event_trigger_count > 1 then
    raise exception
      'ensure_rls preflight failed: multiple event triggers exist';
  end if;

  if event_trigger_count = 1 then
    if function_oid is null then
      raise exception
        'ensure_rls preflight failed: target function is missing';
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_event_trigger as event_trigger
      where event_trigger.evtname = 'ensure_rls'
        and event_trigger.evtevent = 'ddl_command_end'
        and event_trigger.evtenabled = 'O'
        and pg_catalog.pg_get_userbyid(event_trigger.evtowner) = 'postgres'
        and event_trigger.evtfoid = function_oid
        and pg_catalog.cardinality(event_trigger.evttags) = 3
        and event_trigger.evttags @>
          array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
        and event_trigger.evttags <@
          array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
    ) then
      raise exception
        'ensure_rls preflight failed: existing event trigger differs';
    end if;
  end if;
end;
$preflight$;

create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog','information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%'
    THEN
      BEGIN
        EXECUTE format(
          'alter table if exists %s enable row level security',
          cmd.object_identity
        );
        RAISE LOG
          'rls_auto_enable: enabled RLS on %',
          cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG
            'rls_auto_enable: failed to enable RLS on %',
            cmd.object_identity;
      END;
    ELSE
      RAISE LOG
        'rls_auto_enable: skip % (either system schema or not in enforced list: %.)',
        cmd.object_identity,
        cmd.schema_name;
    END IF;
  END LOOP;
END;
$function$;

revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated, service_role, authenticator;

do $create_event_trigger$
begin
  if not exists (
    select 1
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ) then
    execute $ddl$
      create event trigger ensure_rls
      on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      execute function public.rls_auto_enable()
    $ddl$;
  end if;
end;
$create_event_trigger$;

do $postcondition$
declare
  expected_source constant text := $function_body$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog','information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%'
    THEN
      BEGIN
        EXECUTE format(
          'alter table if exists %s enable row level security',
          cmd.object_identity
        );
        RAISE LOG
          'rls_auto_enable: enabled RLS on %',
          cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG
            'rls_auto_enable: failed to enable RLS on %',
            cmd.object_identity;
      END;
    ELSE
      RAISE LOG
        'rls_auto_enable: skip % (either system schema or not in enforced list: %.)',
        cmd.object_identity,
        cmd.schema_name;
    END IF;
  END LOOP;
END;
$function_body$;
  function_oid oid;
  function_source text;
  function_count integer;
  function_oid_before oid;
begin
  select count(*)
  into function_count
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'rls_auto_enable';

  if function_count <> 1 then
    raise exception
      'rls_auto_enable postcondition failed: expected exactly one function';
  end if;

  select function.oid, function.prosrc
  into function_oid, function_source
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'rls_auto_enable'
    and function.pronargs = 0
    and function.prokind = 'f'
    and function.prorettype = 'event_trigger'::pg_catalog.regtype
    and language.lanname = 'plpgsql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.prosecdef
    and function.provolatile = 'v'
    and function.proparallel = 'u'
    and function.proconfig = array['search_path=pg_catalog']::text[]
    and not exists (
      select 1
      from pg_catalog.pg_depend as dependency
      where dependency.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
        and dependency.objid = function.oid
        and dependency.deptype = 'e'
    );

  if function_oid is null then
    raise exception
      'rls_auto_enable postcondition failed: function attributes differ';
  end if;

  if pg_catalog.regexp_replace(
       function_source,
       '[[:space:]]+',
       '',
       'g'
     ) <> pg_catalog.regexp_replace(
       expected_source,
       '[[:space:]]+',
       '',
       'g'
     ) then
    raise exception
      'rls_auto_enable postcondition failed: function body differs';
  end if;

  function_oid_before := nullif(
    pg_catalog.current_setting(
      'my_diary.rls_auto_enable_oid_before',
      true
    ),
    ''
  )::oid;

  if function_oid_before is not null
     and function_oid <> function_oid_before then
    raise exception
      'rls_auto_enable postcondition failed: function OID changed';
  end if;

  if exists (
    select 1
    from pg_catalog.aclexplode(
      coalesce(
        (
          select function.proacl
          from pg_catalog.pg_proc as function
          where function.oid = function_oid
        ),
        pg_catalog.acldefault(
          'f',
          (
            select function.proowner
            from pg_catalog.pg_proc as function
            where function.oid = function_oid
          )
        )
      )
    ) as privilege
    where privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'rls_auto_enable postcondition failed: PUBLIC can execute';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', function_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', function_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', function_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', function_oid, 'EXECUTE'
     ) then
    raise exception
      'rls_auto_enable postcondition failed: an application role can execute';
  end if;

  if not pg_catalog.has_function_privilege(
    'postgres', function_oid, 'EXECUTE'
  ) then
    raise exception
      'rls_auto_enable postcondition failed: postgres cannot execute';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_event_trigger as event_trigger
    where event_trigger.evtname = 'ensure_rls'
      and event_trigger.evtevent = 'ddl_command_end'
      and event_trigger.evtenabled = 'O'
      and pg_catalog.pg_get_userbyid(event_trigger.evtowner) = 'postgres'
      and event_trigger.evtfoid = function_oid
      and pg_catalog.cardinality(event_trigger.evttags) = 3
      and event_trigger.evttags @>
        array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
      and event_trigger.evttags <@
        array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
  ) then
    raise exception
      'ensure_rls postcondition failed: event trigger differs';
  end if;
end;
$postcondition$;

commit;
