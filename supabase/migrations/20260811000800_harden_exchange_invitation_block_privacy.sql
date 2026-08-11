begin;

do $preflight$
declare
  invitation_transition_trigger_oid oid;
  block_function_oid oid;
  create_function_oid oid;
begin
  if pg_catalog.to_regclass('public.exchange_invitations') is null
     or pg_catalog.to_regclass('public.exchange_invitation_blocks') is null then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: required tables are missing';
  end if;

  select trigger_definition.oid
  into invitation_transition_trigger_oid
  from pg_catalog.pg_trigger as trigger_definition
  where trigger_definition.tgrelid =
          'public.exchange_invitations'::pg_catalog.regclass
    and trigger_definition.tgname =
          'my_diary_exchange_invitations_state_transition'
    and trigger_definition.tgfoid =
          'my_diary_private.my_diary_enforce_exchange_invitation_transition()'
            ::pg_catalog.regprocedure
    and not trigger_definition.tgisinternal
    and trigger_definition.tgenabled = 'O'
    and not trigger_definition.tgdeferrable
    and not trigger_definition.tginitdeferred
    and pg_catalog.pg_get_triggerdef(trigger_definition.oid) like
          'CREATE TRIGGER my_diary_exchange_invitations_state_transition BEFORE UPDATE OF status ON public.exchange_invitations FOR EACH ROW%';

  if invitation_transition_trigger_oid is null then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: invitation transition trigger differs';
  end if;

  select function_definition.oid
  into block_function_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname =
          'my_diary_block_exchange_invitations_from_user'
    and function_definition.proargtypes = '2950'::oidvector
    and function_definition.proargnames = array['p_user_id']::text[]
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if block_function_oid is null
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%set status = ''invalidated''%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%my_diary_lock_exchange_pair%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%for update%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%on conflict do nothing%' then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: block RPC differs';
  end if;

  select function_definition.oid
  into create_function_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname = 'my_diary_create_exchange_invitation'
    and function_definition.proargtypes = '2950'::oidvector
    and function_definition.proargnames =
          array['p_invitee_user_id']::text[]
    and function_definition.prorettype = 'uuid'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if create_function_oid is null
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%status in (''rejected'', ''cancelled'')%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%processed_at > now() - interval ''24 hours''%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%my_diary_create_exchange_invitation_notification%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%Exchange diary operation is unavailable.%' then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: create RPC cooldown differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 2 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
  ) <> 2 or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
            'my_diary_exchange_invitations_select_party_noninvalidated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%status <> ''invalidated''%'
      and qual like '%my_diary_is_account_active%'
      and qual like '%inviter_user_id%'
      and qual like '%invitee_user_id%'
  ) or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitation_blocks'
      and policyname =
            'my_diary_exchange_invitation_blocks_select_blocker'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%blocker_user_id%'
      and qual like '%my_diary_is_account_active%'
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations', 'SELECT'
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks', 'SELECT'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations', 'INSERT, UPDATE, DELETE'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks',
    'INSERT, UPDATE, DELETE'
  ) or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as application_role(role_name)
    cross join pg_catalog.unnest(
      array[
        'public.exchange_invitations',
        'public.exchange_invitation_blocks'
      ]
    ) as target_table(table_name)
    where pg_catalog.has_table_privilege(
      application_role.role_name,
      target_table.table_name,
      'SELECT, INSERT, UPDATE, DELETE'
    )
  ) or exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation.relacl,
        pg_catalog.acldefault('r', relation.relowner)
      )
    ) as privilege
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and privilege.grantee = 0
      and privilege.privilege_type in (
        'SELECT', 'INSERT', 'UPDATE', 'DELETE'
      )
  ) then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: invitation RLS or ACL differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
      and indexdef like '%WHERE (status = ''pending''::text)%'
  ) or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_cooldown_pair_idx'
      and indexdef like '%processed_at DESC%'
      and indexdef like '%rejected%'
      and indexdef like '%cancelled%'
  ) then
    raise exception
      'harden_exchange_invitation_block_privacy preflight failed: invitation indexes differ';
  end if;
end;
$preflight$;

-- Acquire the lock before disabling the trigger. EXCLUSIVE conflicts with the
-- ROW SHARE / ROW EXCLUSIVE locks used by SELECT FOR UPDATE and DML, preventing
-- a concurrent RPC from holding an invitation row while waiting on ALTER TABLE.
-- Plain SELECT remains available. The trigger state and backfill are in this
-- explicit transaction, so a failure restores both rows and trigger state.
lock table only public.exchange_invitations in exclusive mode;

alter table public.exchange_invitations
  disable trigger my_diary_exchange_invitations_state_transition;

update public.exchange_invitations as invitation
set status = 'rejected'
where invitation.status = 'invalidated';

alter table public.exchange_invitations
  enable trigger my_diary_exchange_invitations_state_transition;

create or replace function public.my_diary_block_exchange_invitations_from_user(
  p_user_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
begin
  if p_user_id is null
     or viewer_user_id is not null and viewer_user_id = p_user_id then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    viewer_user_id,
    p_user_id
  );

  if not exists (
    select 1
    from public.accounts as viewer_account
    where viewer_account.user_id = viewer_user_id
      and viewer_account.status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform invitation.id
  from public.exchange_invitations as invitation
  where invitation.inviter_user_id = p_user_id
    and invitation.invitee_user_id = viewer_user_id
    and invitation.status = 'pending'
  order by invitation.created_at, invitation.id
  for update;

  insert into public.exchange_invitation_blocks (
    blocker_user_id,
    blocked_inviter_user_id
  )
  values (viewer_user_id, p_user_id)
  on conflict do nothing;

  update public.exchange_invitations as invitation
  set status = 'rejected',
      processed_at = now(),
      diary_id = null
  where invitation.inviter_user_id = p_user_id
    and invitation.invitee_user_id = viewer_user_id
    and invitation.status = 'pending';

  return true;
end;
$function$;

alter function public.my_diary_block_exchange_invitations_from_user(uuid)
  owner to postgres;

revoke all on function
  public.my_diary_block_exchange_invitations_from_user(uuid)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  public.my_diary_block_exchange_invitations_from_user(uuid)
  to authenticated;

do $postcondition$
declare
  block_function_oid oid;
  create_function_oid oid;
begin
  if exists (
    select 1
    from public.exchange_invitations as invitation
    where invitation.status = 'invalidated'
  ) then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: historical invalidated invitations remain';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgrelid =
            'public.exchange_invitations'::pg_catalog.regclass
      and trigger_definition.tgname =
            'my_diary_exchange_invitations_state_transition'
      and trigger_definition.tgfoid =
            'my_diary_private.my_diary_enforce_exchange_invitation_transition()'
              ::pg_catalog.regprocedure
      and not trigger_definition.tgisinternal
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgdeferrable
      and not trigger_definition.tginitdeferred
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid) like
            'CREATE TRIGGER my_diary_exchange_invitations_state_transition BEFORE UPDATE OF status ON public.exchange_invitations FOR EACH ROW%'
  ) then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: invitation transition trigger is not enabled';
  end if;

  select function_definition.oid
  into block_function_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname =
          'my_diary_block_exchange_invitations_from_user'
    and function_definition.proargtypes = '2950'::oidvector
    and function_definition.proargnames = array['p_user_id']::text[]
    and function_definition.prorettype = 'boolean'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if block_function_oid is null
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%set status = ''rejected''%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          like '%set status = ''invalidated''%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%my_diary_lock_exchange_pair%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%for update%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          not like '%on conflict do nothing%'
     or pg_catalog.pg_get_functiondef(block_function_oid)
          like '%notification%' then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: block RPC differs';
  end if;

  select function_definition.oid
  into create_function_oid
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  where namespace.nspname = 'public'
    and function_definition.proname = 'my_diary_create_exchange_invitation'
    and function_definition.proargtypes = '2950'::oidvector
    and function_definition.proargnames =
          array['p_invitee_user_id']::text[]
    and function_definition.prorettype = 'uuid'::pg_catalog.regtype
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if create_function_oid is null
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%status in (''rejected'', ''cancelled'')%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%processed_at > now() - interval ''24 hours''%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%my_diary_create_exchange_invitation_notification%'
     or pg_catalog.pg_get_functiondef(create_function_oid)
          not like '%Exchange diary operation is unavailable.%' then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: create RPC cooldown differs';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.my_diary_block_exchange_invitations_from_user(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.my_diary_block_exchange_invitations_from_user(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.my_diary_block_exchange_invitations_from_user(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator',
       'public.my_diary_block_exchange_invitations_from_user(uuid)',
       'EXECUTE'
     ) then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: block RPC ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 2 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
  ) <> 2 or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
            'my_diary_exchange_invitations_select_party_noninvalidated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%status <> ''invalidated''%'
      and qual like '%my_diary_is_account_active%'
      and qual like '%inviter_user_id%'
      and qual like '%invitee_user_id%'
  ) or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitation_blocks'
      and policyname =
            'my_diary_exchange_invitation_blocks_select_blocker'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%blocker_user_id%'
      and qual like '%my_diary_is_account_active%'
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations', 'SELECT'
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks', 'SELECT'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations', 'INSERT, UPDATE, DELETE'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks',
    'INSERT, UPDATE, DELETE'
  ) or exists (
    select 1
    from pg_catalog.unnest(
      array['anon', 'service_role', 'authenticator']
    ) as application_role(role_name)
    cross join pg_catalog.unnest(
      array[
        'public.exchange_invitations',
        'public.exchange_invitation_blocks'
      ]
    ) as target_table(table_name)
    where pg_catalog.has_table_privilege(
      application_role.role_name,
      target_table.table_name,
      'SELECT, INSERT, UPDATE, DELETE'
    )
  ) or exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation.relacl,
        pg_catalog.acldefault('r', relation.relowner)
      )
    ) as privilege
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and privilege.grantee = 0
      and privilege.privilege_type in (
        'SELECT', 'INSERT', 'UPDATE', 'DELETE'
      )
  ) or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
  ) or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_cooldown_pair_idx'
      and indexdef like '%rejected%'
      and indexdef like '%cancelled%'
  ) then
    raise exception
      'harden_exchange_invitation_block_privacy postcondition failed: invitation security boundary differs';
  end if;
end;
$postcondition$;

commit;
