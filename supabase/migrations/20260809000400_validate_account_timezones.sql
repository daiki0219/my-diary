begin;

do $preflight$
declare
  accounts_oid oid := pg_catalog.to_regclass('public.accounts');
begin
  if accounts_oid is null
     or pg_catalog.to_regnamespace('my_diary_private') is null then
    raise exception
      'validate_account_timezones preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_validate_account_timezone()'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_trigger
       where tgrelid = accounts_oid
         and tgname = 'my_diary_accounts_validate_timezone'
         and not tgisinternal
     ) then
    raise exception
      'validate_account_timezones preflight failed: validator objects already exist';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = accounts_oid
  )
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname in (
        'my_diary_accounts_select_own',
        'my_diary_accounts_update_own_timezone'
      )
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
  ) <> 2 then
    raise exception
      'validate_account_timezones preflight failed: accounts RLS differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', accounts_oid, 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'timezone', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'role', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'status', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'anon', accounts_oid, 'SELECT, INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'validate_account_timezones preflight failed: accounts ACL differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'pg_catalog.pg_timezone_names', 'SELECT'
     ) then
    raise exception
      'validate_account_timezones preflight failed: timezone catalog is unavailable';
  end if;

  if exists (
    select 1
    from public.accounts as account
    where account.timezone like 'posix/%'
       or account.timezone like 'right/%'
       or account.timezone = 'Factory'
       or not exists (
         select 1
         from pg_catalog.pg_timezone_names as timezone_name
         where timezone_name.name = account.timezone
       )
  ) then
    raise exception
      'validate_account_timezones preflight failed: invalid existing timezone';
  end if;
end;
$preflight$;

create function my_diary_private.my_diary_validate_account_timezone()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  if new.timezone like 'posix/%'
     or new.timezone like 'right/%'
     or new.timezone = 'Factory'
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names as timezone_name
       where timezone_name.name = new.timezone
     ) then
    raise check_violation
      using message = 'invalid account timezone';
  end if;

  return new;
end;
$function$;

alter function my_diary_private.my_diary_validate_account_timezone()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_validate_account_timezone()
  from public, anon, authenticated, service_role, authenticator;

create trigger my_diary_accounts_validate_timezone
before insert or update of timezone on public.accounts
for each row execute function
  my_diary_private.my_diary_validate_account_timezone();

do $postcondition$
declare
  accounts_oid oid := 'public.accounts'::pg_catalog.regclass;
  validator_oid oid;
begin
  select function_definition.oid
  into validator_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'my_diary_private'
    and function_definition.proname = 'my_diary_validate_account_timezone'
    and function_definition.proargtypes = ''::oidvector
    and function_definition.prorettype = 'trigger'::pg_catalog.regtype
    and function_definition.prokind = 'f'
    and language.lanname = 'plpgsql'
    and not function_definition.prosecdef
    and function_definition.provolatile = 'v'
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      like '%pg_catalog.pg_timezone_names%'
    and pg_catalog.pg_get_functiondef(function_definition.oid)
      like '%invalid account timezone%';

  if validator_oid is null
     or exists (
       select 1
       from pg_catalog.aclexplode(
         coalesce(
           (
             select proacl
             from pg_catalog.pg_proc
             where oid = validator_oid
           ),
           pg_catalog.acldefault(
             'f',
             (
               select proowner
               from pg_catalog.pg_proc
               where oid = validator_oid
             )
           )
         )
       ) as function_acl
       where function_acl.grantee = 0
         and function_acl.privilege_type = 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array[
           'anon', 'authenticated', 'service_role', 'authenticator'
         ]
       ) as denied(role_name)
       where pg_catalog.has_function_privilege(
         denied.role_name, validator_oid, 'EXECUTE'
       )
     ) then
    raise exception
      'validate_account_timezones postcondition failed: validator attributes or ACL differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = accounts_oid
      and tgname = 'my_diary_accounts_validate_timezone'
      and tgfoid = validator_oid
      and tgenabled = 'O'
      and not tgisinternal
      and pg_catalog.pg_get_triggerdef(oid)
        like '%BEFORE INSERT OR UPDATE OF timezone ON public.accounts%'
  ) then
    raise exception
      'validate_account_timezones postcondition failed: validator trigger differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = accounts_oid
  )
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname in (
        'my_diary_accounts_select_own',
        'my_diary_accounts_update_own_timezone'
      )
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 2
  or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
  ) <> 2
  or not pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'timezone', 'UPDATE'
     )
  or pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'role', 'UPDATE'
     )
  or pg_catalog.has_column_privilege(
       'authenticated', accounts_oid, 'status', 'UPDATE'
     ) then
    raise exception
      'validate_account_timezones postcondition failed: accounts boundary differs';
  end if;
end;
$postcondition$;

commit;
