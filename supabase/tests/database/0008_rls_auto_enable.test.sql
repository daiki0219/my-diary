begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
  ),
  1::bigint,
  'rls_auto_enable has no unexpected overloads'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  1::bigint,
  'The zero-argument rls_auto_enable function exists once'
);

select is(
  (
    select pg_catalog.pg_get_function_result(function.oid)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'event_trigger',
  'rls_auto_enable returns event_trigger'
);

select is(
  (
    select language.lanname
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'plpgsql',
  'rls_auto_enable uses plpgsql'
);

select is(
  (
    select pg_catalog.pg_get_userbyid(function.proowner)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'postgres',
  'rls_auto_enable is owned by postgres'
);

select ok(
  (
    select function.prosecdef
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'rls_auto_enable is SECURITY DEFINER'
);

select is(
  (
    select function.proconfig
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  array['search_path=pg_catalog']::text[],
  'rls_auto_enable fixes search_path to pg_catalog'
);

select ok(
  (
    select function.provolatile = 'v'
      and function.proparallel = 'u'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'rls_auto_enable remains volatile and parallel unsafe'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_depend as dependency
    join pg_catalog.pg_proc as function
      on function.oid = dependency.objid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where dependency.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
      and dependency.deptype = 'e'
      and namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  0::bigint,
  'rls_auto_enable does not belong to an extension'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ),
  1::bigint,
  'ensure_rls exists once'
);

select is(
  (
    select evtevent
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ),
  'ddl_command_end',
  'ensure_rls runs at ddl_command_end'
);

select ok(
  (
    select pg_catalog.cardinality(evttags) = 3
      and evttags @>
        array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
      and evttags <@
        array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ),
  'ensure_rls has exactly the three expected command tags'
);

select is(
  (
    select evtenabled::text
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ),
  'O'::text,
  'ensure_rls is enabled in origin mode'
);

select is(
  (
    select pg_catalog.pg_get_userbyid(evtowner)
    from pg_catalog.pg_event_trigger
    where evtname = 'ensure_rls'
  ),
  'postgres',
  'ensure_rls is owned by postgres'
);

select ok(
  (
    select event_trigger.evtfoid = function.oid
    from pg_catalog.pg_event_trigger as event_trigger
    join pg_catalog.pg_proc as function
      on function.oid = event_trigger.evtfoid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where event_trigger.evtname = 'ensure_rls'
      and namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
  ),
  'ensure_rls references the zero-argument public.rls_auto_enable function'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where namespace.nspname = 'public'
      and function.proname = 'rls_auto_enable'
      and function.pronargs = 0
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute rls_auto_enable'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.rls_auto_enable()', 'EXECUTE'
  ),
  'anon cannot execute rls_auto_enable'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'public.rls_auto_enable()', 'EXECUTE'
  ),
  'authenticated cannot execute rls_auto_enable'
);

select ok(
  not pg_catalog.has_function_privilege(
    'service_role', 'public.rls_auto_enable()', 'EXECUTE'
  ),
  'service_role cannot execute rls_auto_enable'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticator', 'public.rls_auto_enable()', 'EXECUTE'
  ),
  'authenticator cannot execute rls_auto_enable'
);

select ok(
  pg_catalog.has_function_privilege(
    'postgres', 'public.rls_auto_enable()', 'EXECUTE'
  ),
  'postgres can execute rls_auto_enable'
);

create schema my_diary_rls_auto_fixture;

create table public.my_diary_rls_auto_table (
  id integer primary key
);

create table public.my_diary_rls_auto_partitioned (
  id integer not null
) partition by range (id);

create table public.my_diary_rls_auto_ctas as
select 1::integer as id;

select 1::integer as id
into public.my_diary_rls_auto_select_into;

create table my_diary_rls_auto_fixture.outside_public (
  id integer primary key
);

create table my_diary_rls_auto_fixture.moved_to_public (
  id integer primary key
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'my_diary_rls_auto_table'
  ),
  'CREATE TABLE in public enables RLS'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'my_diary_rls_auto_partitioned'
  ),
  'CREATE TABLE enables RLS on a partitioned table in public'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'my_diary_rls_auto_ctas'
  ),
  'CREATE TABLE AS in public enables RLS'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'my_diary_rls_auto_select_into'
  ),
  'SELECT INTO in public enables RLS'
);

select ok(
  not (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'my_diary_rls_auto_fixture'
      and relation.relname = 'outside_public'
  ),
  'CREATE TABLE outside public does not enable RLS'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'my_diary_rls_auto_table',
        'my_diary_rls_auto_partitioned',
        'my_diary_rls_auto_ctas',
        'my_diary_rls_auto_select_into'
      )
  ),
  0::bigint,
  'Automatic RLS enablement does not create policies'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'my_diary_rls_auto_table',
        'my_diary_rls_auto_partitioned',
        'my_diary_rls_auto_ctas',
        'my_diary_rls_auto_select_into'
      )
      and relation.relforcerowsecurity
  ),
  0::bigint,
  'Automatic RLS enablement does not force RLS'
);

alter table my_diary_rls_auto_fixture.moved_to_public
  set schema public;

select ok(
  not (
    select relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'moved_to_public'
  ),
  'Moving an existing table into public does not enable RLS retroactively'
);

select * from finish();

rollback;
