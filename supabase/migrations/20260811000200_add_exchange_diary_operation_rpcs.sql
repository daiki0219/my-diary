begin;

do $preflight$
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.follows') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.exchange_invitations') is null
     or pg_catalog.to_regclass('public.exchange_invitation_blocks') is null
     or pg_catalog.to_regclass(
       'my_diary_private.my_diary_exchange_pair_locks'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_enforce_exchange_diary_exact_two()'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_enforce_exchange_invitation_transition()'
     ) is null then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: required objects are missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where (
      namespace.nspname = 'public'
      and function_definition.proname in (
        'my_diary_create_exchange_invitation',
        'my_diary_accept_exchange_invitation',
        'my_diary_reject_exchange_invitation',
        'my_diary_cancel_exchange_invitation',
        'my_diary_block_exchange_invitations_from_user',
        'my_diary_unblock_exchange_invitations_from_user',
        'my_diary_update_exchange_diary_title',
        'my_diary_archive_exchange_diary'
      )
    ) or (
      namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_lock_exchange_pair'
    )
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: a target function already exists';
  end if;

  if pg_catalog.to_regclass(
       'public.my_diary_exchange_invitations_cooldown_pair_idx'
     ) is not null then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: the cooldown index already exists';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role_definition
      where role_definition.rolname = required.role_name
    )
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: a required role is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.accounts'::pg_catalog.regclass
      and conname = 'my_diary_accounts_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.follows'::pg_catalog.regclass
      and conname = 'my_diary_follows_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
        'my_diary_private.my_diary_exchange_pair_locks'::pg_catalog.regclass
      and conname = 'my_diary_exchange_pair_locks_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
      and indexdef like '%WHERE (status = ''pending''::text)%'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: lock or uniqueness definitions differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 4 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 4 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
  ) <> 4 then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: exchange RLS differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname = 'my_diary_exchange_invitations_select_pending_party'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%status = ''pending''%'
  ) or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
        'my_diary_exchange_invitations_select_party_noninvalidated'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: invitation visibility differs';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array[
        'public.exchange_diaries',
        'public.exchange_diary_participants',
        'public.exchange_invitations',
        'public.exchange_invitation_blocks'
      ]
    ) as target(table_name)
    where not pg_catalog.has_table_privilege(
      'authenticated', target.table_name, 'SELECT'
    )
      or pg_catalog.has_table_privilege(
        'authenticated', target.table_name, 'INSERT, UPDATE, DELETE'
      )
      or pg_catalog.has_table_privilege(
        'anon', target.table_name, 'SELECT, INSERT, UPDATE, DELETE'
      )
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs preflight failed: table ACL differs';
  end if;
end;
$preflight$;

create index my_diary_exchange_invitations_cooldown_pair_idx
  on public.exchange_invitations (
    pair_low_user_id,
    pair_high_user_id,
    processed_at desc,
    id
  )
  where status in ('rejected', 'cancelled');

drop policy my_diary_exchange_invitations_select_pending_party
on public.exchange_invitations;

create policy my_diary_exchange_invitations_select_party_noninvalidated
on public.exchange_invitations
for select
to authenticated
using (
  status <> 'invalidated'
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and (select auth.uid()) in (inviter_user_id, invitee_user_id)
);

create function my_diary_private.my_diary_lock_exchange_pair(
  p_user_id_one uuid,
  p_user_id_two uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  canonical_low_user_id uuid;
  canonical_high_user_id uuid;
  locked_account_count integer;
begin
  if p_user_id_one is null
     or p_user_id_two is null
     or p_user_id_one = p_user_id_two then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if p_user_id_one < p_user_id_two then
    canonical_low_user_id := p_user_id_one;
    canonical_high_user_id := p_user_id_two;
  else
    canonical_low_user_id := p_user_id_two;
    canonical_high_user_id := p_user_id_one;
  end if;

  perform account.user_id
  from public.accounts as account
  where account.user_id in (canonical_low_user_id, canonical_high_user_id)
  order by account.user_id
  for update;

  get diagnostics locked_account_count = row_count;

  if locked_account_count <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  insert into my_diary_private.my_diary_exchange_pair_locks (
    pair_low_user_id,
    pair_high_user_id
  )
  values (canonical_low_user_id, canonical_high_user_id)
  on conflict do nothing;

  perform pair_lock.pair_low_user_id
  from my_diary_private.my_diary_exchange_pair_locks as pair_lock
  where pair_lock.pair_low_user_id = canonical_low_user_id
    and pair_lock.pair_high_user_id = canonical_high_user_id
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;
end;
$function$;

create function public.my_diary_create_exchange_invitation(
  p_invitee_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  canonical_low_user_id uuid;
  canonical_high_user_id uuid;
  mutual_follow_count integer;
  invitation_id uuid;
begin
  if p_invitee_user_id is null
     or viewer_user_id is not null
        and viewer_user_id = p_invitee_user_id then
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
    p_invitee_user_id
  );

  if viewer_user_id < p_invitee_user_id then
    canonical_low_user_id := viewer_user_id;
    canonical_high_user_id := p_invitee_user_id;
  else
    canonical_low_user_id := p_invitee_user_id;
    canonical_high_user_id := viewer_user_id;
  end if;

  perform invitation.id
  from public.exchange_invitations as invitation
  where invitation.pair_low_user_id = canonical_low_user_id
    and invitation.pair_high_user_id = canonical_high_user_id
  order by invitation.created_at, invitation.id
  for update;

  if not exists (
    select 1
    from public.accounts as viewer_account
    where viewer_account.user_id = viewer_user_id
      and viewer_account.status = 'active'
  ) or not exists (
    select 1
    from public.accounts as invitee_account
    where invitee_account.user_id = p_invitee_user_id
      and invitee_account.status = 'active'
  ) or exists (
    select 1
    from public.exchange_invitation_blocks as invitation_block
    where invitation_block.blocker_user_id = p_invitee_user_id
      and invitation_block.blocked_inviter_user_id = viewer_user_id
  ) or exists (
    select 1
    from public.exchange_invitations as pending_invitation
    where pending_invitation.pair_low_user_id = canonical_low_user_id
      and pending_invitation.pair_high_user_id = canonical_high_user_id
      and pending_invitation.status = 'pending'
  ) or exists (
    select 1
    from public.exchange_invitations as terminal_invitation
    where terminal_invitation.pair_low_user_id = canonical_low_user_id
      and terminal_invitation.pair_high_user_id = canonical_high_user_id
      and terminal_invitation.status in ('rejected', 'cancelled')
      and terminal_invitation.processed_at > now() - interval '24 hours'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform follow_relation.follower_id
  from public.follows as follow_relation
  where (
    follow_relation.follower_id = viewer_user_id
    and follow_relation.following_id = p_invitee_user_id
  ) or (
    follow_relation.follower_id = p_invitee_user_id
    and follow_relation.following_id = viewer_user_id
  )
  order by follow_relation.follower_id, follow_relation.following_id
  for update;

  get diagnostics mutual_follow_count = row_count;

  if mutual_follow_count <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  insert into public.exchange_invitations (
    inviter_user_id,
    invitee_user_id,
    status,
    processed_at,
    diary_id
  )
  values (
    viewer_user_id,
    p_invitee_user_id,
    'pending',
    null,
    null
  )
  returning id into invitation_id;

  return invitation_id;
end;
$function$;

create function public.my_diary_accept_exchange_invitation(
  p_invitation_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  inviter_user_id uuid;
  invitee_user_id uuid;
  locked_inviter_user_id uuid;
  locked_invitee_user_id uuid;
  locked_status text;
  mutual_follow_count integer;
  new_diary_id uuid;
begin
  if p_invitation_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = viewer_user_id
         and viewer_account.status = 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select invitation.inviter_user_id, invitation.invitee_user_id
  into inviter_user_id, invitee_user_id
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id;

  if inviter_user_id is null
     or invitee_user_id is null
     or viewer_user_id <> invitee_user_id then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    inviter_user_id,
    invitee_user_id
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

  select
    invitation.inviter_user_id,
    invitation.invitee_user_id,
    invitation.status
  into
    locked_inviter_user_id,
    locked_invitee_user_id,
    locked_status
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id
  for update;

  if locked_inviter_user_id is null
     or locked_inviter_user_id <> inviter_user_id
     or locked_invitee_user_id <> viewer_user_id
     or locked_status <> 'pending'
     or not exists (
       select 1
       from public.accounts as inviter_account
       where inviter_account.user_id = inviter_user_id
         and inviter_account.status = 'active'
     )
     or not exists (
       select 1
       from public.accounts as invitee_account
       where invitee_account.user_id = viewer_user_id
         and invitee_account.status = 'active'
     )
     or exists (
       select 1
       from public.exchange_invitation_blocks as invitation_block
       where invitation_block.blocker_user_id = viewer_user_id
         and invitation_block.blocked_inviter_user_id = inviter_user_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform follow_relation.follower_id
  from public.follows as follow_relation
  where (
    follow_relation.follower_id = viewer_user_id
    and follow_relation.following_id = inviter_user_id
  ) or (
    follow_relation.follower_id = inviter_user_id
    and follow_relation.following_id = viewer_user_id
  )
  order by follow_relation.follower_id, follow_relation.following_id
  for update;

  get diagnostics mutual_follow_count = row_count;

  if mutual_follow_count <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  insert into public.exchange_diaries (
    title,
    state,
    created_by_position
  )
  values (null, 'active', 1)
  returning id into new_diary_id;

  insert into public.exchange_diary_participants (
    diary_id,
    position,
    user_id
  )
  values
    (new_diary_id, 1, inviter_user_id),
    (new_diary_id, 2, viewer_user_id);

  update public.exchange_invitations as invitation
  set status = 'accepted',
      processed_at = now(),
      diary_id = new_diary_id
  where invitation.id = p_invitation_id
    and invitation.status = 'pending';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  return new_diary_id;
end;
$function$;

create function public.my_diary_reject_exchange_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  inviter_user_id uuid;
  invitee_user_id uuid;
  locked_inviter_user_id uuid;
  locked_invitee_user_id uuid;
  locked_status text;
begin
  if p_invitation_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = viewer_user_id
         and viewer_account.status = 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select invitation.inviter_user_id, invitation.invitee_user_id
  into inviter_user_id, invitee_user_id
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id;

  if inviter_user_id is null
     or invitee_user_id is null
     or viewer_user_id <> invitee_user_id then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    inviter_user_id,
    invitee_user_id
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

  select
    invitation.inviter_user_id,
    invitation.invitee_user_id,
    invitation.status
  into
    locked_inviter_user_id,
    locked_invitee_user_id,
    locked_status
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id
  for update;

  if locked_inviter_user_id is null
     or locked_inviter_user_id <> inviter_user_id
     or locked_invitee_user_id <> viewer_user_id
     or locked_status <> 'pending' then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  update public.exchange_invitations as invitation
  set status = 'rejected',
      processed_at = now(),
      diary_id = null
  where invitation.id = p_invitation_id
    and invitation.status = 'pending';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  return true;
end;
$function$;

create function public.my_diary_cancel_exchange_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  inviter_user_id uuid;
  invitee_user_id uuid;
  locked_inviter_user_id uuid;
  locked_invitee_user_id uuid;
  locked_status text;
begin
  if p_invitation_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = viewer_user_id
         and viewer_account.status = 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select invitation.inviter_user_id, invitation.invitee_user_id
  into inviter_user_id, invitee_user_id
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id;

  if inviter_user_id is null
     or invitee_user_id is null
     or viewer_user_id <> inviter_user_id then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    inviter_user_id,
    invitee_user_id
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

  select
    invitation.inviter_user_id,
    invitation.invitee_user_id,
    invitation.status
  into
    locked_inviter_user_id,
    locked_invitee_user_id,
    locked_status
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id
  for update;

  if locked_inviter_user_id is null
     or locked_inviter_user_id <> viewer_user_id
     or locked_invitee_user_id <> invitee_user_id
     or locked_status <> 'pending' then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  update public.exchange_invitations as invitation
  set status = 'cancelled',
      processed_at = now(),
      diary_id = null
  where invitation.id = p_invitation_id
    and invitation.status = 'pending';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  return true;
end;
$function$;

create function public.my_diary_block_exchange_invitations_from_user(
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
  set status = 'invalidated',
      processed_at = now(),
      diary_id = null
  where invitation.inviter_user_id = p_user_id
    and invitation.invitee_user_id = viewer_user_id
    and invitation.status = 'pending';

  return true;
end;
$function$;

create function public.my_diary_unblock_exchange_invitations_from_user(
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

  if viewer_user_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = viewer_user_id
         and viewer_account.status = 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  if not exists (
    select 1
    from public.accounts as target_account
    where target_account.user_id = p_user_id
  ) then
    perform account.user_id
    from public.accounts as account
    where account.user_id = viewer_user_id
    for update;

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

    return true;
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

  delete from public.exchange_invitation_blocks as invitation_block
  where invitation_block.blocker_user_id = viewer_user_id
    and invitation_block.blocked_inviter_user_id = p_user_id;

  return true;
end;
$function$;

create function public.my_diary_update_exchange_diary_title(
  p_diary_id uuid,
  p_title text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  normalized_title text;
  participant_user_ids uuid[];
  locked_participant_count integer;
  locked_diary_state text;
begin
  if p_diary_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if p_title is null then
    normalized_title := null;
  else
    normalized_title := nullif(
      pg_catalog.regexp_replace(
        p_title,
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
      ),
      ''
    );
  end if;

  if normalized_title is not null
     and pg_catalog.char_length(normalized_title) > 120 then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select pg_catalog.array_agg(participant.user_id order by participant.user_id)
  into participant_user_ids
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
    and participant.user_id is not null;

  if coalesce(pg_catalog.array_length(participant_user_ids, 1), 0) <> 2
     or not viewer_user_id = any(participant_user_ids) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform account.user_id
  from public.accounts as account
  where account.user_id = any(participant_user_ids)
  order by account.user_id
  for update;

  get diagnostics locked_participant_count = row_count;

  if locked_participant_count <> 2
     or exists (
       select 1
       from public.accounts as participant_account
       where participant_account.user_id = any(participant_user_ids)
         and participant_account.status <> 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select diary.state
  into locked_diary_state
  from public.exchange_diaries as diary
  where diary.id = p_diary_id
  for update;

  perform participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
  order by participant.position, participant.id
  for update;

  get diagnostics locked_participant_count = row_count;

  if locked_diary_state is null
     or locked_diary_state <> 'active'
     or locked_participant_count <> 2
     or (
       select pg_catalog.count(*)
       from public.exchange_diary_participants as participant
       join public.accounts as participant_account
         on participant_account.user_id = participant.user_id
       where participant.diary_id = p_diary_id
         and participant.position in (1, 2)
         and participant_account.status = 'active'
     ) <> 2
     or not exists (
       select 1
       from public.exchange_diary_participants as viewer_participant
       where viewer_participant.diary_id = p_diary_id
         and viewer_participant.user_id = viewer_user_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  update public.exchange_diaries as diary
  set title = normalized_title
  where diary.id = p_diary_id
    and diary.state = 'active';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  return p_diary_id;
end;
$function$;

create function public.my_diary_archive_exchange_diary(
  p_diary_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  participant_user_ids uuid[];
  locked_participant_count integer;
  locked_diary_state text;
begin
  if p_diary_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select pg_catalog.array_agg(participant.user_id order by participant.user_id)
  into participant_user_ids
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
    and participant.user_id is not null;

  if coalesce(pg_catalog.array_length(participant_user_ids, 1), 0) <> 2
     or not viewer_user_id = any(participant_user_ids) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform account.user_id
  from public.accounts as account
  where account.user_id = any(participant_user_ids)
  order by account.user_id
  for update;

  get diagnostics locked_participant_count = row_count;

  if locked_participant_count <> 2
     or exists (
       select 1
       from public.accounts as participant_account
       where participant_account.user_id = any(participant_user_ids)
         and participant_account.status <> 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select diary.state
  into locked_diary_state
  from public.exchange_diaries as diary
  where diary.id = p_diary_id
  for update;

  perform participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
  order by participant.position, participant.id
  for update;

  get diagnostics locked_participant_count = row_count;

  if locked_diary_state is null
     or locked_diary_state <> 'active'
     or locked_participant_count <> 2
     or (
       select pg_catalog.count(*)
       from public.exchange_diary_participants as participant
       join public.accounts as participant_account
         on participant_account.user_id = participant.user_id
       where participant.diary_id = p_diary_id
         and participant.position in (1, 2)
         and participant_account.status = 'active'
     ) <> 2
     or not exists (
       select 1
       from public.exchange_diary_participants as viewer_participant
       where viewer_participant.diary_id = p_diary_id
         and viewer_participant.user_id = viewer_user_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  update public.exchange_diaries as diary
  set state = 'archived',
      archived_at = now(),
      archive_cause = 'ended_by_participant'
  where diary.id = p_diary_id
    and diary.state = 'active';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  return p_diary_id;
end;
$function$;

alter function my_diary_private.my_diary_lock_exchange_pair(uuid, uuid)
  owner to postgres;
alter function public.my_diary_create_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_accept_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_reject_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_cancel_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_block_exchange_invitations_from_user(uuid)
  owner to postgres;
alter function public.my_diary_unblock_exchange_invitations_from_user(uuid)
  owner to postgres;
alter function public.my_diary_update_exchange_diary_title(uuid, text)
  owner to postgres;
alter function public.my_diary_archive_exchange_diary(uuid)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_lock_exchange_pair(uuid, uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_create_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_accept_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_reject_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_cancel_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_block_exchange_invitations_from_user(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_unblock_exchange_invitations_from_user(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_update_exchange_diary_title(uuid, text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_archive_exchange_diary(uuid)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_exchange_invitation(uuid)
  to authenticated;
grant execute on function public.my_diary_accept_exchange_invitation(uuid)
  to authenticated;
grant execute on function public.my_diary_reject_exchange_invitation(uuid)
  to authenticated;
grant execute on function public.my_diary_cancel_exchange_invitation(uuid)
  to authenticated;
grant execute on function
  public.my_diary_block_exchange_invitations_from_user(uuid)
  to authenticated;
grant execute on function
  public.my_diary_unblock_exchange_invitations_from_user(uuid)
  to authenticated;
grant execute on function
  public.my_diary_update_exchange_diary_title(uuid, text)
  to authenticated;
grant execute on function public.my_diary_archive_exchange_diary(uuid)
  to authenticated;

do $postcondition$
declare
  public_function_count integer;
begin
  select pg_catalog.count(*)
  into public_function_count
  from pg_catalog.pg_proc as function_definition
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function_definition.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function_definition.prolang
  where namespace.nspname = 'public'
    and function_definition.proname in (
      'my_diary_create_exchange_invitation',
      'my_diary_accept_exchange_invitation',
      'my_diary_reject_exchange_invitation',
      'my_diary_cancel_exchange_invitation',
      'my_diary_block_exchange_invitations_from_user',
      'my_diary_unblock_exchange_invitations_from_user',
      'my_diary_update_exchange_diary_title',
      'my_diary_archive_exchange_diary'
    )
    and language.lanname = 'plpgsql'
    and function_definition.prokind = 'f'
    and function_definition.provolatile = 'v'
    and function_definition.prosecdef
    and function_definition.proconfig = array['search_path=""']::text[]
    and function_definition.pronargdefaults = 0
    and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres';

  if public_function_count <> 8 then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: public function attributes differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join (
      values
        (
          'my_diary_create_exchange_invitation',
          '2950'::oidvector,
          array['p_invitee_user_id']::text[],
          'uuid'::pg_catalog.regtype
        ),
        (
          'my_diary_accept_exchange_invitation',
          '2950'::oidvector,
          array['p_invitation_id']::text[],
          'uuid'::pg_catalog.regtype
        ),
        (
          'my_diary_reject_exchange_invitation',
          '2950'::oidvector,
          array['p_invitation_id']::text[],
          'boolean'::pg_catalog.regtype
        ),
        (
          'my_diary_cancel_exchange_invitation',
          '2950'::oidvector,
          array['p_invitation_id']::text[],
          'boolean'::pg_catalog.regtype
        ),
        (
          'my_diary_block_exchange_invitations_from_user',
          '2950'::oidvector,
          array['p_user_id']::text[],
          'boolean'::pg_catalog.regtype
        ),
        (
          'my_diary_unblock_exchange_invitations_from_user',
          '2950'::oidvector,
          array['p_user_id']::text[],
          'boolean'::pg_catalog.regtype
        ),
        (
          'my_diary_update_exchange_diary_title',
          '2950 25'::oidvector,
          array['p_diary_id', 'p_title']::text[],
          'uuid'::pg_catalog.regtype
        ),
        (
          'my_diary_archive_exchange_diary',
          '2950'::oidvector,
          array['p_diary_id']::text[],
          'uuid'::pg_catalog.regtype
        )
    ) as expected(function_name, argument_types, argument_names, return_type)
      on expected.function_name = function_definition.proname
     and expected.argument_types = function_definition.proargtypes
     and expected.argument_names = function_definition.proargnames
     and expected.return_type = function_definition.prorettype
    where namespace.nspname = 'public'
  ) <> 8 then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: signatures differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function_definition.prolang
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_lock_exchange_pair'
      and function_definition.proargtypes = '2950 2950'::oidvector
      and function_definition.proargnames =
        array['p_user_id_one', 'p_user_id_two']::text[]
      and function_definition.prorettype = 'void'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: pair helper differs';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as privilege
    where (
      (
        namespace.nspname = 'public'
        and function_definition.proname in (
          'my_diary_create_exchange_invitation',
          'my_diary_accept_exchange_invitation',
          'my_diary_reject_exchange_invitation',
          'my_diary_cancel_exchange_invitation',
          'my_diary_block_exchange_invitations_from_user',
          'my_diary_unblock_exchange_invitations_from_user',
          'my_diary_update_exchange_diary_title',
          'my_diary_archive_exchange_diary'
        )
      ) or (
        namespace.nspname = 'my_diary_private'
        and function_definition.proname = 'my_diary_lock_exchange_pair'
      )
    )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: PUBLIC execute remains';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array[
        'public.my_diary_create_exchange_invitation(uuid)',
        'public.my_diary_accept_exchange_invitation(uuid)',
        'public.my_diary_reject_exchange_invitation(uuid)',
        'public.my_diary_cancel_exchange_invitation(uuid)',
        'public.my_diary_block_exchange_invitations_from_user(uuid)',
        'public.my_diary_unblock_exchange_invitations_from_user(uuid)',
        'public.my_diary_update_exchange_diary_title(uuid,text)',
        'public.my_diary_archive_exchange_diary(uuid)'
      ]
    ) as target(signature)
    where not pg_catalog.has_function_privilege(
      'authenticated', target.signature, 'EXECUTE'
    )
      or pg_catalog.has_function_privilege(
        'anon', target.signature, 'EXECUTE'
      )
      or pg_catalog.has_function_privilege(
        'service_role', target.signature, 'EXECUTE'
      )
      or pg_catalog.has_function_privilege(
        'authenticator', target.signature, 'EXECUTE'
      )
  ) or pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_lock_exchange_pair(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: function ACL differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_cooldown_pair_idx'
      and indexdef like '%pair_low_user_id, pair_high_user_id, processed_at DESC, id%'
      and indexdef like '%status = ANY%'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: cooldown index differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgname in (
      'my_diary_exchange_diaries_set_updated_at',
      'my_diary_exchange_diaries_reject_reactivation',
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two',
      'my_diary_exchange_invitations_state_transition'
    )
      and not trigger_definition.tgisinternal
  ) <> 5 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgname in (
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two'
    )
      and trigger_definition.tgdeferrable
      and trigger_definition.tginitdeferred
      and not trigger_definition.tgisinternal
  ) <> 2 then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: trigger boundary differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 4 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
  ) <> 4 or not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
        'my_diary_exchange_invitations_select_party_noninvalidated'
      and qual like '%status <> ''invalidated''%'
  ) or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname = 'my_diary_exchange_invitations_select_pending_party'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: RLS hardening differs';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array[
        'public.exchange_diaries',
        'public.exchange_diary_participants',
        'public.exchange_invitations',
        'public.exchange_invitation_blocks'
      ]
    ) as target(table_name)
    where not pg_catalog.has_table_privilege(
      'authenticated', target.table_name, 'SELECT'
    )
      or pg_catalog.has_table_privilege(
        'authenticated', target.table_name, 'INSERT, UPDATE, DELETE'
      )
      or pg_catalog.has_table_privilege(
        'anon', target.table_name, 'SELECT, INSERT, UPDATE, DELETE'
      )
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  ) then
    raise exception
      'add_exchange_diary_operation_rpcs postcondition failed: table ACL changed';
  end if;
end;
$postcondition$;

commit;
