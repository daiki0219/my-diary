begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

select has_function(
  'my_diary_private',
  'my_diary_validate_account_timezone',
  array[]::text[],
  'The private account timezone validator exists'
);

select ok(
  (
    select not function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        like '%pg_catalog.pg_timezone_names%'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        like '%invalid account timezone%'
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_account_timezone'
      and function_definition.proargtypes = ''::oidvector
  ),
  'The validator is invoker-security, volatile, hardened, and postgres-owned'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as function_acl
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_account_timezone'
      and function_definition.proargtypes = ''::oidvector
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'my_diary_private.my_diary_validate_account_timezone()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_validate_account_timezone()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_validate_account_timezone()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_validate_account_timezone()',
    'EXECUTE'
  ),
  'No application role can execute the trigger function directly'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger_definition
    join pg_catalog.pg_proc as function_definition
      on function_definition.oid = trigger_definition.tgfoid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where trigger_definition.tgrelid = 'public.accounts'::regclass
      and trigger_definition.tgname = 'my_diary_accounts_validate_timezone'
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgisinternal
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        like '%BEFORE INSERT OR UPDATE OF timezone ON public.accounts%'
      and namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_account_timezone'
  ),
  'The enabled validator covers account INSERT and timezone UPDATE'
);

select col_type_is(
  'public', 'accounts', 'timezone', 'text',
  'accounts.timezone remains text'
);
select col_not_null(
  'public', 'accounts', 'timezone',
  'accounts.timezone remains NOT NULL'
);
select col_default_is(
  'public', 'accounts', 'timezone', 'Asia/Tokyo',
  'accounts.timezone keeps the Asia/Tokyo default'
);
select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_definition.oid)
      like '%char_length(btrim(timezone))%'
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid = 'public.accounts'::regclass
      and constraint_definition.conname = 'my_diary_accounts_timezone_check'
  ),
  'The existing trimmed length CHECK remains in place'
);
select ok(
  (
    select relrowsecurity and not relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.accounts'::regclass
  ),
  'accounts keeps RLS enabled'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
  ),
  2::bigint,
  'accounts keeps only its existing SELECT and UPDATE policies'
);
select ok(
  has_column_privilege(
    'authenticated', 'public.accounts', 'timezone', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.accounts', 'role', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.accounts', 'status', 'UPDATE'
  ),
  'authenticated retains only the timezone update column'
);
select ok(
  not has_table_privilege(
    'anon', 'public.accounts', 'SELECT, INSERT, UPDATE, DELETE'
  ),
  'anon cannot access accounts'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_timezone_names
    where name in (
      'Asia/Tokyo', 'America/New_York', 'Europe/London', 'UTC'
    )
  ),
  4::bigint,
  'The required timezone identifiers exist in the PostgreSQL catalog'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_timezone_names
    where name = 'Invalid/Timezone'
  ),
  0::bigint,
  'The invalid timezone is absent from the PostgreSQL catalog'
);

insert into auth.users (id, email)
values
  ('a2000000-0000-4000-8000-000000000001', 'c3b-active-a@example.test'),
  ('b2000000-0000-4000-8000-000000000002', 'c3b-active-b@example.test'),
  ('c2000000-0000-4000-8000-000000000003', 'c3b-suspended@example.test'),
  ('d2000000-0000-4000-8000-000000000004', 'c3b-deactivated@example.test'),
  ('f2000000-0000-4000-8000-000000000006', 'c3b-insert@example.test');

update public.accounts
set status = case user_id
  when 'c2000000-0000-4000-8000-000000000003' then 'suspended'
  when 'd2000000-0000-4000-8000-000000000004' then 'deactivated'
  else 'active'
end
where user_id in (
  'a2000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000002',
  'c2000000-0000-4000-8000-000000000003',
  'd2000000-0000-4000-8000-000000000004'
);

select set_config(
  'request.jwt.claim.sub',
  'a2000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$update public.accounts set timezone = 'Asia/Tokyo' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  'Asia/Tokyo is accepted'
);
select lives_ok(
  $$update public.accounts set timezone = 'America/New_York' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  'America/New_York is accepted'
);
select lives_ok(
  $$update public.accounts set timezone = 'Europe/London' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  'Europe/London is accepted'
);
select lives_ok(
  $$update public.accounts set timezone = 'UTC' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  'UTC is accepted'
);
select lives_ok(
  $$update public.accounts set timezone = 'US/Eastern' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  'A PostgreSQL and Intl-compatible IANA alias is accepted'
);

select throws_ok(
  $$update public.accounts set timezone = 'Invalid/Timezone' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '23514', 'invalid account timezone',
  'An invalid timezone is rejected through the authenticated direct path'
);
select throws_ok(
  $$update public.accounts set timezone = '' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '23514', 'invalid account timezone',
  'An empty timezone is rejected'
);
select throws_ok(
  $$update public.accounts set timezone = '   ' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '23514', 'invalid account timezone',
  'A whitespace-only timezone is rejected'
);
select throws_ok(
  $$update public.accounts set timezone = 'posix/Asia/Tokyo' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '23514', 'invalid account timezone',
  'The PostgreSQL internal posix duplicate tree is rejected'
);
select throws_ok(
  $$update public.accounts set timezone = 'Factory' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '23514', 'invalid account timezone',
  'The PostgreSQL special Factory zone that Intl cannot format is rejected'
);
select results_eq(
  $$select timezone from public.accounts where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  $$values ('US/Eastern'::text)$$,
  'Rejected updates leave the previously saved timezone unchanged'
);
select is_empty(
  $$update public.accounts set timezone = 'Europe/London' where user_id = 'b2000000-0000-4000-8000-000000000002' returning timezone$$,
  'A cannot update another user timezone'
);
select throws_ok(
  $$update public.accounts set role = 'admin' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '42501', null,
  'A cannot update role'
);
select throws_ok(
  $$update public.accounts set status = 'suspended' where user_id = 'a2000000-0000-4000-8000-000000000001'$$,
  '42501', null,
  'A cannot update status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select is_empty(
  $$update public.accounts set timezone = 'UTC' where user_id = 'c2000000-0000-4000-8000-000000000003' returning timezone$$,
  'A suspended viewer cannot update timezone'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2000000-0000-4000-8000-000000000004',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select is_empty(
  $$update public.accounts set timezone = 'UTC' where user_id = 'd2000000-0000-4000-8000-000000000004' returning timezone$$,
  'A deactivated viewer cannot update timezone'
);

reset role;
delete from public.accounts
where user_id = 'f2000000-0000-4000-8000-000000000006';
select throws_ok(
  $$insert into public.accounts (user_id, timezone) values ('f2000000-0000-4000-8000-000000000006', 'Invalid/Timezone')$$,
  '23514', 'invalid account timezone',
  'An invalid timezone is also rejected on direct account INSERT'
);

select * from finish();

rollback;
