begin;

do $preflight$
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass(
       'public.exchange_diary_participants'
     ) is null then
    raise exception
      'archive_exchange_diaries_on_deactivation preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_trigger as trigger_definition
       where trigger_definition.tgname =
         'my_diary_accounts_archive_exchange_diaries_on_deactivation'
         and not trigger_definition.tgisinternal
     ) then
    raise exception
      'archive_exchange_diaries_on_deactivation preflight failed: target object already exists';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid =
        'public.accounts'::pg_catalog.regclass
      and constraint_definition.conname = 'my_diary_accounts_status_check'
      and constraint_definition.contype = 'c'
      and constraint_definition.convalidated
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid =
        'public.exchange_diaries'::pg_catalog.regclass
      and constraint_definition.conname =
        'my_diary_exchange_diaries_archive_shape_check'
      and constraint_definition.contype = 'c'
      and constraint_definition.convalidated
  ) then
    raise exception
      'archive_exchange_diaries_on_deactivation preflight failed: lifecycle constraints differ';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required_role(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role_definition
      where role_definition.rolname = required_role.role_name
    )
  ) then
    raise exception
      'archive_exchange_diaries_on_deactivation preflight failed: a required role is missing';
  end if;
end;
$preflight$;

create function
  my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target_diary_id uuid;
begin
  if old.status is not distinct from 'deactivated'
     or new.status is distinct from 'deactivated' then
    return new;
  end if;

  for target_diary_id in
    select diary.id
    from public.exchange_diaries as diary
    where diary.state = 'active'
      and exists (
        select 1
        from public.exchange_diary_participants as participant
        where participant.diary_id = diary.id
          and participant.user_id = new.user_id
      )
    order by diary.id
    for update of diary
  loop
    update public.exchange_diaries as diary
    set state = 'archived',
        archived_at = pg_catalog.now(),
        archive_cause = 'participant_deactivated'
    where diary.id = target_diary_id
      and diary.state = 'active';
  end loop;

  return new;
end;
$function$;

alter function
  my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()
  from public, anon, authenticated, service_role, authenticator;

create trigger my_diary_accounts_archive_exchange_diaries_on_deactivation
after update of status on public.accounts
for each row
when (
  old.status is distinct from 'deactivated'
  and new.status = 'deactivated'
)
execute function
  my_diary_private.my_diary_archive_exchange_diaries_on_deactivation();

do $postcondition$
begin
  if not exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function_definition.prolang
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname =
        'my_diary_archive_exchange_diaries_on_deactivation'
      and function_definition.pronargs = 0
      and function_definition.pronargdefaults = 0
      and function_definition.prorettype = 'trigger'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) then
    raise exception
      'archive_exchange_diaries_on_deactivation postcondition failed: function attributes differ';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['public', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as application_role(role_name)
    where pg_catalog.has_function_privilege(
      application_role.role_name,
      'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
      'EXECUTE'
    )
  ) then
    raise exception
      'archive_exchange_diaries_on_deactivation postcondition failed: function ACL differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgname =
        'my_diary_accounts_archive_exchange_diaries_on_deactivation'
      and trigger_definition.tgrelid = 'public.accounts'::pg_catalog.regclass
      and trigger_definition.tgfoid =
        'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()'
          ::pg_catalog.regprocedure
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgisinternal
      and not trigger_definition.tgdeferrable
      and not trigger_definition.tginitdeferred
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid) like
        'CREATE TRIGGER my_diary_accounts_archive_exchange_diaries_on_deactivation AFTER UPDATE OF status ON public.accounts FOR EACH ROW%'
  ) then
    raise exception
      'archive_exchange_diaries_on_deactivation postcondition failed: trigger differs';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.accounts', 'SELECT'
     )
     or not pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'timezone', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'status', 'UPDATE'
     )
     or pg_catalog.has_column_privilege(
       'authenticated', 'public.accounts', 'role', 'UPDATE'
     ) then
    raise exception
      'archive_exchange_diaries_on_deactivation postcondition failed: accounts ACL differs';
  end if;
end;
$postcondition$;

commit;
