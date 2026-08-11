begin;

create extension if not exists pgtap with schema extensions;

select plan(94);

-- Exact catalog, owner, security, and ACL boundary.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
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
  ),
  8::bigint,
  'Exactly eight public exchange operation RPCs exist'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join (
      values
        ('my_diary_create_exchange_invitation', '2950'::oidvector,
         array['p_invitee_user_id']::text[], 'uuid'::regtype),
        ('my_diary_accept_exchange_invitation', '2950'::oidvector,
         array['p_invitation_id']::text[], 'uuid'::regtype),
        ('my_diary_reject_exchange_invitation', '2950'::oidvector,
         array['p_invitation_id']::text[], 'boolean'::regtype),
        ('my_diary_cancel_exchange_invitation', '2950'::oidvector,
         array['p_invitation_id']::text[], 'boolean'::regtype),
        ('my_diary_block_exchange_invitations_from_user', '2950'::oidvector,
         array['p_user_id']::text[], 'boolean'::regtype),
        ('my_diary_unblock_exchange_invitations_from_user', '2950'::oidvector,
         array['p_user_id']::text[], 'boolean'::regtype),
        ('my_diary_update_exchange_diary_title', '2950 25'::oidvector,
         array['p_diary_id', 'p_title']::text[], 'uuid'::regtype),
        ('my_diary_archive_exchange_diary', '2950'::oidvector,
         array['p_diary_id']::text[], 'uuid'::regtype)
    ) as expected(function_name, argument_types, argument_names, return_type)
      on expected.function_name = function_definition.proname
     and expected.argument_types = function_definition.proargtypes
     and expected.argument_names = function_definition.proargnames
     and expected.return_type = function_definition.prorettype
    where namespace.nspname = 'public'
  ),
  8::bigint,
  'All RPCs have the exact argument names, types, and return types'
);

select is(
  (
    select pg_catalog.count(*)
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
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  8::bigint,
  'All RPCs are postgres-owned VOLATILE SECURITY DEFINER with empty search_path'
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
    ) as privilege
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
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no EXECUTE on any exchange operation RPC'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'public.my_diary_create_exchange_invitation(uuid)',
      'public.my_diary_accept_exchange_invitation(uuid)',
      'public.my_diary_reject_exchange_invitation(uuid)',
      'public.my_diary_cancel_exchange_invitation(uuid)',
      'public.my_diary_block_exchange_invitations_from_user(uuid)',
      'public.my_diary_unblock_exchange_invitations_from_user(uuid)',
      'public.my_diary_update_exchange_diary_title(uuid,text)',
      'public.my_diary_archive_exchange_diary(uuid)'
    ]) as target(signature)
    where not pg_catalog.has_function_privilege(
      'authenticated', target.signature, 'EXECUTE'
    )
  ),
  'authenticated has EXECUTE on every exact RPC signature'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'public.my_diary_create_exchange_invitation(uuid)',
      'public.my_diary_accept_exchange_invitation(uuid)',
      'public.my_diary_reject_exchange_invitation(uuid)',
      'public.my_diary_cancel_exchange_invitation(uuid)',
      'public.my_diary_block_exchange_invitations_from_user(uuid)',
      'public.my_diary_unblock_exchange_invitations_from_user(uuid)',
      'public.my_diary_update_exchange_diary_title(uuid,text)',
      'public.my_diary_archive_exchange_diary(uuid)'
    ]) as target(signature)
    where pg_catalog.has_function_privilege('anon', target.signature, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'service_role', target.signature, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'authenticator', target.signature, 'EXECUTE'
       )
  ),
  'anon, service_role, and authenticator have no RPC EXECUTE'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_lock_exchange_pair'
      and function_definition.proargtypes = '2950 2950'::oidvector
      and function_definition.proargnames =
        array['p_user_id_one', 'p_user_id_two']::text[]
      and function_definition.prorettype = 'void'::regtype
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  'The private pair-lock helper is exact and hardened'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_lock_exchange_pair(uuid,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_lock_exchange_pair(uuid,uuid)',
    'EXECUTE'
  ),
  'Application roles cannot invoke the private pair-lock helper'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_diaries', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_diary_participants',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  'Direct exchange table mutation and pair-lock access remain closed'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries', 'exchange_diary_participants',
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  4::bigint,
  'Exactly four participant and party SELECT policies remain'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
        'my_diary_exchange_invitations_select_party_noninvalidated'
      and qual like '%status <> ''invalidated''%'
  )
  and not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname = 'my_diary_exchange_invitations_select_pending_party'
  ),
  'Invitation RLS exposes non-invalidated party history only'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_cooldown_pair_idx'
      and indexdef like '%processed_at DESC%'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
  ),
  'Cooldown lookup and pending uniqueness indexes both exist'
);

-- Accounts and follow fixtures. Auth trigger creates accounts and profiles.
insert into auth.users (id, email)
values
  ('a2300000-0000-4000-8000-000000000001', 'e2a2-a@example.test'),
  ('b2300000-0000-4000-8000-000000000002', 'e2a2-b@example.test'),
  ('c2300000-0000-4000-8000-000000000003', 'e2a2-c@example.test'),
  ('d2300000-0000-4000-8000-000000000004', 'e2a2-d@example.test'),
  ('e2300000-0000-4000-8000-000000000005', 'e2a2-e@example.test'),
  ('f2300000-0000-4000-8000-000000000006', 'e2a2-f@example.test'),
  ('12300000-0000-4000-8000-000000000007', 'e2a2-g@example.test'),
  ('22300000-0000-4000-8000-000000000008', 'e2a2-h@example.test'),
  ('32300000-0000-4000-8000-000000000009', 'e2a2-i@example.test'),
  ('42300000-0000-4000-8000-00000000000a', 'e2a2-j@example.test'),
  ('52300000-0000-4000-8000-00000000000b', 'e2a2-k@example.test'),
  ('62300000-0000-4000-8000-00000000000c', 'e2a2-l@example.test');

insert into public.follows (follower_id, following_id)
values
  ('a2300000-0000-4000-8000-000000000001', 'b2300000-0000-4000-8000-000000000002'),
  ('b2300000-0000-4000-8000-000000000002', 'a2300000-0000-4000-8000-000000000001'),
  ('c2300000-0000-4000-8000-000000000003', 'd2300000-0000-4000-8000-000000000004'),
  ('d2300000-0000-4000-8000-000000000004', 'c2300000-0000-4000-8000-000000000003'),
  ('e2300000-0000-4000-8000-000000000005', 'f2300000-0000-4000-8000-000000000006'),
  ('f2300000-0000-4000-8000-000000000006', 'e2300000-0000-4000-8000-000000000005'),
  ('e2300000-0000-4000-8000-000000000005', '12300000-0000-4000-8000-000000000007'),
  ('12300000-0000-4000-8000-000000000007', 'e2300000-0000-4000-8000-000000000005'),
  ('e2300000-0000-4000-8000-000000000005', '22300000-0000-4000-8000-000000000008'),
  ('22300000-0000-4000-8000-000000000008', 'e2300000-0000-4000-8000-000000000005'),
  ('12300000-0000-4000-8000-000000000007', '22300000-0000-4000-8000-000000000008'),
  ('22300000-0000-4000-8000-000000000008', '12300000-0000-4000-8000-000000000007'),
  ('12300000-0000-4000-8000-000000000007', '32300000-0000-4000-8000-000000000009'),
  ('32300000-0000-4000-8000-000000000009', '12300000-0000-4000-8000-000000000007'),
  ('32300000-0000-4000-8000-000000000009', '42300000-0000-4000-8000-00000000000a'),
  ('42300000-0000-4000-8000-00000000000a', '32300000-0000-4000-8000-000000000009'),
  ('c2300000-0000-4000-8000-000000000003', '52300000-0000-4000-8000-00000000000b');

-- Invitation create: active boundary, mutual follows, generic errors, and pending.
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config(
  'my_diary.e2a2_ab_invitation',
  public.my_diary_create_exchange_invitation(
    'b2300000-0000-4000-8000-000000000002'
  )::text,
  true
);

select ok(
  current_setting('my_diary.e2a2_ab_invitation')::uuid is not null,
  'Mutual-follow invitation creation returns an invitation UUID'
);

reset role;
select results_eq(
  $$select inviter_user_id, invitee_user_id, status, processed_at, diary_id
    from public.exchange_invitations
    where id = current_setting('my_diary.e2a2_ab_invitation')::uuid$$,
  $$values (
    'a2300000-0000-4000-8000-000000000001'::uuid,
    'b2300000-0000-4000-8000-000000000002'::uuid,
    'pending'::text, null::timestamptz, null::uuid
  )$$,
  'Created invitation has DB-owned pending shape'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'a2300000-0000-4000-8000-000000000001'
  )$$,
  '22023',
  'Invalid exchange diary operation input.',
  'Self invitation is rejected as malformed input'
);

select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'b2300000-0000-4000-8000-000000000002'
  )$$,
  '42501',
  'Exchange diary operation is unavailable.',
  'A duplicate pending invitation is generically rejected'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'c2300000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub', 'c2300000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'd2300000-0000-4000-8000-000000000004'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A suspended viewer cannot create an invitation'
);

reset role;
update public.accounts set status = 'deactivated'
where user_id = 'c2300000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'd2300000-0000-4000-8000-000000000004'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A deactivated viewer cannot create an invitation'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'c2300000-0000-4000-8000-000000000003';
update public.accounts set status = 'suspended'
where user_id = 'd2300000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'd2300000-0000-4000-8000-000000000004'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A suspended invitee is generically unavailable'
);

reset role;
update public.accounts set status = 'deactivated'
where user_id = 'd2300000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'd2300000-0000-4000-8000-000000000004'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A deactivated invitee is generically unavailable'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'd2300000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    '52300000-0000-4000-8000-00000000000b'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'One-way follow is generically unavailable'
);

select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    '62300000-0000-4000-8000-00000000000c'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'No-follow relation is generically unavailable'
);

select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'An unknown invitee is generically unavailable'
);

-- Accept: party, follow recheck, block recheck, status, and exact-two.
reset role;
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'The inviter cannot accept its own invitation'
);

reset role;
select set_config('request.jwt.claim.sub', '52300000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A third party cannot accept an invitation'
);

reset role;
delete from public.follows
where follower_id = 'a2300000-0000-4000-8000-000000000001'
  and following_id = 'b2300000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Accept rechecks mutual follow after an unfollow'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'a2300000-0000-4000-8000-000000000001',
  'b2300000-0000-4000-8000-000000000002'
);
select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  public.my_diary_block_exchange_invitations_from_user(
    'a2300000-0000-4000-8000-000000000001'
  ),
  true,
  'The invitee can block the inviter before acceptance'
);

select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A block invalidates and prevents acceptance'
);

select is(
  public.my_diary_unblock_exchange_invitations_from_user(
    'a2300000-0000-4000-8000-000000000001'
  ),
  true,
  'The invitee can remove the block'
);

-- The invalidated invitation remains terminal; create a fresh invitation after unblock.
reset role;
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select set_config(
  'my_diary.e2a2_ab_accept_invitation',
  public.my_diary_create_exchange_invitation(
    'b2300000-0000-4000-8000-000000000002'
  )::text,
  true
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'a2300000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_accept_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Accept rejects a suspended inviter'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'a2300000-0000-4000-8000-000000000001';
update public.accounts set status = 'suspended'
where user_id = 'b2300000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_accept_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Accept rejects a suspended invitee'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2300000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config(
  'my_diary.e2a2_ab_diary',
  public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_accept_invitation')::uuid
  )::text,
  true
);

select ok(
  current_setting('my_diary.e2a2_ab_diary')::uuid is not null,
  'Invitee acceptance returns a diary UUID'
);

reset role;
set constraints all immediate;
set constraints all deferred;

select results_eq(
  $$select title, state, created_by_position
    from public.exchange_diaries
    where id = current_setting('my_diary.e2a2_ab_diary')::uuid$$,
  $$values (null::text, 'active'::text, 1::smallint)$$,
  'Accept creates one active NULL-title diary with inviter position 1'
);

select results_eq(
  $$select position, user_id
    from public.exchange_diary_participants
    where diary_id = current_setting('my_diary.e2a2_ab_diary')::uuid
    order by position$$,
  $$values
    (1::smallint, 'a2300000-0000-4000-8000-000000000001'::uuid),
    (2::smallint, 'b2300000-0000-4000-8000-000000000002'::uuid)$$,
  'Accept creates exactly inviter position 1 and invitee position 2'
);

select results_eq(
  $$select status, processed_at is not null, diary_id
    from public.exchange_invitations
    where id = current_setting('my_diary.e2a2_ab_accept_invitation')::uuid$$,
  $$values (
    'accepted'::text, true,
    current_setting('my_diary.e2a2_ab_diary')::uuid
  )$$,
  'Accept atomically links accepted invitation to the new diary'
);

select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_ab_accept_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A terminal invitation cannot be accepted twice'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.exchange_diaries as diary
    join public.exchange_diary_participants as p1
      on p1.diary_id = diary.id and p1.position = 1
    join public.exchange_diary_participants as p2
      on p2.diary_id = diary.id and p2.position = 2
    where p1.user_id = 'a2300000-0000-4000-8000-000000000001'
      and p2.user_id = 'b2300000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'A repeated accept does not create a second diary'
);

-- Cooldown covers rejected/cancelled only; invalidated/accepted history is excluded.
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id, status, processed_at
)
values (
  '12300000-0000-4000-8000-000000000100',
  '12300000-0000-4000-8000-000000000007',
  '22300000-0000-4000-8000-000000000008',
  'rejected', now() - interval '23 hours 59 minutes'
);

select set_config('request.jwt.claim.sub', '12300000-0000-4000-8000-000000000007', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A recent rejected invitation enforces the 24-hour cooldown'
);

reset role;
update public.exchange_invitations
set processed_at = now() - interval '24 hours 1 minute'
where id = '12300000-0000-4000-8000-000000000100';
set local role authenticated;
select set_config(
  'my_diary.e2a2_gh_invitation_one',
  public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2a2_gh_invitation_one')::uuid is not null,
  'A rejected invitation older than 24 hours permits a new invitation'
);

reset role;
update public.exchange_invitations
set status = 'invalidated', processed_at = now(), diary_id = null
where id = current_setting('my_diary.e2a2_gh_invitation_one')::uuid;
set local role authenticated;
select set_config(
  'my_diary.e2a2_gh_invitation_two',
  public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2a2_gh_invitation_two')::uuid is not null,
  'Invalidated history is not a cooldown source'
);

select is(
  public.my_diary_cancel_exchange_invitation(
    current_setting('my_diary.e2a2_gh_invitation_two')::uuid
  ),
  true,
  'Inviter can cancel a pending invitation'
);

select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A recent cancellation enforces the 24-hour cooldown'
);

reset role;
update public.exchange_invitations
set processed_at = now() - interval '24 hours 1 minute'
where id = current_setting('my_diary.e2a2_gh_invitation_two')::uuid;
set local role authenticated;
select set_config(
  'my_diary.e2a2_gh_invitation_three',
  public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2a2_gh_invitation_three')::uuid is not null,
  'A cancellation older than 24 hours permits a new invitation'
);

reset role;
select set_config('request.jwt.claim.sub', '22300000-0000-4000-8000-000000000008', true);
set local role authenticated;
select set_config(
  'my_diary.e2a2_gh_diary',
  public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2a2_gh_invitation_three')::uuid
  )::text,
  true
);

reset role;
select set_config('request.jwt.claim.sub', '12300000-0000-4000-8000-000000000007', true);
set local role authenticated;
select ok(
  public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  ) is not null,
  'Accepted history does not prevent a new pending invitation'
);

select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    '22300000-0000-4000-8000-000000000008'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'The new pending invitation still enforces the one-pending maximum'
);

select ok(
  public.my_diary_create_exchange_invitation(
    '32300000-0000-4000-8000-000000000009'
  ) is not null,
  'Cooldown and pending state for one pair do not affect a different pair'
);

-- Reject and cancel only require the acting party to remain active.
reset role;
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  '32300000-0000-4000-8000-000000000100',
  '32300000-0000-4000-8000-000000000009',
  '42300000-0000-4000-8000-00000000000a'
);
select set_config('request.jwt.claim.sub', '32300000-0000-4000-8000-000000000009', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_reject_exchange_invitation(
    '32300000-0000-4000-8000-000000000100'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'The inviter cannot reject an invitation'
);

reset role;
select set_config('request.jwt.claim.sub', '52300000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_reject_exchange_invitation(
    '32300000-0000-4000-8000-000000000100'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A third party cannot reject an invitation'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = '32300000-0000-4000-8000-000000000009';
select set_config('request.jwt.claim.sub', '42300000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select is(
  public.my_diary_reject_exchange_invitation(
    '32300000-0000-4000-8000-000000000100'
  ),
  true,
  'Active invitee can reject while the inviter is non-active'
);

reset role;
select results_eq(
  $$select status, processed_at is not null, diary_id
    from public.exchange_invitations
    where id = '32300000-0000-4000-8000-000000000100'$$,
  $$values ('rejected'::text, true, null::uuid)$$,
  'Reject writes rejected, DB time, and no diary'
);

select set_config('request.jwt.claim.sub', '42300000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_reject_exchange_invitation(
    '32300000-0000-4000-8000-000000000100'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Reject only accepts a pending invitation'
);

reset role;
update public.accounts set status = 'active'
where user_id = '32300000-0000-4000-8000-000000000009';
select set_config('request.jwt.claim.sub', '32300000-0000-4000-8000-000000000009', true);
set local role authenticated;
select results_eq(
  $$select id, status from public.exchange_invitations
    where id = '32300000-0000-4000-8000-000000000100'$$,
  $$values (
    '32300000-0000-4000-8000-000000000100'::uuid,
    'rejected'::text
  )$$,
  'Active inviter can read rejected history without a rejection notification'
);

reset role;
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  '32300000-0000-4000-8000-000000000101',
  '32300000-0000-4000-8000-000000000009',
  '42300000-0000-4000-8000-00000000000a'
);
select set_config('request.jwt.claim.sub', '42300000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_cancel_exchange_invitation(
    '32300000-0000-4000-8000-000000000101'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'The invitee cannot cancel an invitation'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = '42300000-0000-4000-8000-00000000000a';
select set_config('request.jwt.claim.sub', '32300000-0000-4000-8000-000000000009', true);
set local role authenticated;
select is(
  public.my_diary_cancel_exchange_invitation(
    '32300000-0000-4000-8000-000000000101'
  ),
  true,
  'Active inviter can cancel while the invitee is non-active'
);

reset role;
select results_eq(
  $$select status, processed_at is not null, diary_id
    from public.exchange_invitations
    where id = '32300000-0000-4000-8000-000000000101'$$,
  $$values ('cancelled'::text, true, null::uuid)$$,
  'Cancel writes cancelled, DB time, and no diary'
);

select set_config('request.jwt.claim.sub', '32300000-0000-4000-8000-000000000009', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_cancel_exchange_invitation(
    '32300000-0000-4000-8000-000000000101'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Cancel only accepts a pending invitation'
);

reset role;
update public.accounts set status = 'active'
where user_id = '42300000-0000-4000-8000-00000000000a';

-- Block/unblock direction, idempotence, invalidation, and oracle boundary.
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  'e2300000-0000-4000-8000-000000000100',
  'e2300000-0000-4000-8000-000000000005',
  'f2300000-0000-4000-8000-000000000006'
);

select set_config('request.jwt.claim.sub', 'e2300000-0000-4000-8000-000000000005', true);
set local role authenticated;
select is(
  public.my_diary_block_exchange_invitations_from_user(
    'f2300000-0000-4000-8000-000000000006'
  ),
  true,
  'Blocker creates an invitation-block relation'
);
select is(
  public.my_diary_block_exchange_invitations_from_user(
    'f2300000-0000-4000-8000-000000000006'
  ),
  true,
  'Repeated block is idempotent'
);
select throws_ok(
  $$select public.my_diary_block_exchange_invitations_from_user(
    'e2300000-0000-4000-8000-000000000005'
  )$$,
  '22023', 'Invalid exchange diary operation input.',
  'Self block is rejected'
);

reset role;
select results_eq(
  $$select status from public.exchange_invitations
    where id = 'e2300000-0000-4000-8000-000000000100'$$,
  $$values ('pending'::text)$$,
  'Blocking F does not invalidate the reverse E-to-F invitation'
);

insert into public.exchange_diaries (
  id, title, state, created_by_position
)
values (
  'e2300000-0000-4000-8000-000000000200',
  'existing E-G', 'active', 1
);
insert into public.exchange_diary_participants (diary_id, position, user_id)
values
  ('e2300000-0000-4000-8000-000000000200', 1,
   'e2300000-0000-4000-8000-000000000005'),
  ('e2300000-0000-4000-8000-000000000200', 2,
   '12300000-0000-4000-8000-000000000007');
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  'e2300000-0000-4000-8000-000000000101',
  '12300000-0000-4000-8000-000000000007',
  'e2300000-0000-4000-8000-000000000005'
);

select set_config('request.jwt.claim.sub', 'e2300000-0000-4000-8000-000000000005', true);
set local role authenticated;
select is(
  public.my_diary_block_exchange_invitations_from_user(
    '12300000-0000-4000-8000-000000000007'
  ),
  true,
  'Blocking an incoming inviter succeeds'
);

reset role;
select results_eq(
  $$select status, processed_at is not null, diary_id
    from public.exchange_invitations
    where id = 'e2300000-0000-4000-8000-000000000101'$$,
  $$values ('invalidated'::text, true, null::uuid)$$,
  'Block invalidates an incoming pending invitation atomically'
);
select is(
  (select state from public.exchange_diaries
   where id = 'e2300000-0000-4000-8000-000000000200'),
  'active'::text,
  'Block does not alter an existing active diary'
);
select is(
  (select pg_catalog.count(*) from public.follows
   where follower_id in (
     'e2300000-0000-4000-8000-000000000005',
     '12300000-0000-4000-8000-000000000007'
   ) and following_id in (
     'e2300000-0000-4000-8000-000000000005',
     '12300000-0000-4000-8000-000000000007'
   )),
  2::bigint,
  'Block does not alter mutual follows'
);

select set_config('request.jwt.claim.sub', '12300000-0000-4000-8000-000000000007', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'e2300000-0000-4000-8000-000000000005'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A blocked inviter receives the same generic unavailable error'
);
select is(
  (select pg_catalog.count(*) from public.exchange_invitation_blocks
   where blocker_user_id = 'e2300000-0000-4000-8000-000000000005'
     and blocked_inviter_user_id = '12300000-0000-4000-8000-000000000007'),
  0::bigint,
  'Blocked inviter cannot read the block relation'
);
select is(
  (select pg_catalog.count(*) from public.exchange_invitations
   where id = 'e2300000-0000-4000-8000-000000000101'),
  0::bigint,
  'Blocked inviter cannot read the invalidated invitation status'
);

reset role;
select set_config('request.jwt.claim.sub', 'e2300000-0000-4000-8000-000000000005', true);
set local role authenticated;
select is(
  public.my_diary_unblock_exchange_invitations_from_user(
    '12300000-0000-4000-8000-000000000007'
  ),
  true,
  'Unblock removes the relation'
);
select is(
  public.my_diary_unblock_exchange_invitations_from_user(
    '12300000-0000-4000-8000-000000000007'
  ),
  true,
  'Repeated unblock is idempotent'
);

reset role;
select is(
  (select status from public.exchange_invitations
   where id = 'e2300000-0000-4000-8000-000000000101'),
  'invalidated'::text,
  'Unblock never restores an invalidated invitation to pending'
);

select set_config('request.jwt.claim.sub', '12300000-0000-4000-8000-000000000007', true);
set local role authenticated;
select ok(
  public.my_diary_create_exchange_invitation(
    'e2300000-0000-4000-8000-000000000005'
  ) is not null,
  'A new invitation is possible after unblock without cooldown'
);

-- Title update normalization, authorization, participant state, and limits.
reset role;
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid,
    '  Shared title  '
  ),
  current_setting('my_diary.e2a2_ab_diary')::uuid,
  'Participant 1 can update the title'
);

reset role;
select is(
  (select title from public.exchange_diaries
   where id = current_setting('my_diary.e2a2_ab_diary')::uuid),
  'Shared title'::text,
  'Title is trimmed before storage'
);

select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid,
    null
  ),
  current_setting('my_diary.e2a2_ab_diary')::uuid,
  'Participant 2 can set a NULL title'
);
select is(
  public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid,
    ''
  ),
  current_setting('my_diary.e2a2_ab_diary')::uuid,
  'Empty title is accepted as NULL'
);
select is(
  public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid,
    E' \t '
  ),
  current_setting('my_diary.e2a2_ab_diary')::uuid,
  'Whitespace-only title is accepted as NULL'
);

reset role;
select is(
  (select title from public.exchange_diaries
   where id = current_setting('my_diary.e2a2_ab_diary')::uuid),
  null::text,
  'Empty and whitespace-only titles are stored as NULL'
);

select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_exchange_diary_title(
      %L::uuid, %L
    )$$,
    current_setting('my_diary.e2a2_ab_diary'),
    repeat('界', 120)
  ),
  'A 120-codepoint title succeeds'
);
select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_exchange_diary_title(
      %L::uuid, %L
    )$$,
    current_setting('my_diary.e2a2_ab_diary'),
    repeat('界', 121)
  ),
  '22023', 'Invalid exchange diary operation input.',
  'A 121-codepoint title is rejected'
);

reset role;
select set_config('request.jwt.claim.sub', '52300000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid, 'forbidden'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A third party cannot update a diary title'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'b2300000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid, 'blocked by state'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Title update fails while the other participant is suspended'
);

-- Archive by either participant, no rearchive/reactivation, and active counterpart.
reset role;
update public.accounts set status = 'active'
where user_id = 'b2300000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.my_diary_archive_exchange_diary(
    current_setting('my_diary.e2a2_ab_diary')::uuid
  ),
  current_setting('my_diary.e2a2_ab_diary')::uuid,
  'Participant 1 can archive the diary'
);

reset role;
select results_eq(
  $$select state, archived_at is not null, archive_cause
    from public.exchange_diaries
    where id = current_setting('my_diary.e2a2_ab_diary')::uuid$$,
  $$values ('archived'::text, true, 'ended_by_participant'::text)$$,
  'Archive writes terminal state, DB time, and the established manual cause'
);

select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_archive_exchange_diary(
    current_setting('my_diary.e2a2_ab_diary')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'An archived diary cannot be archived again'
);
select throws_ok(
  $$select public.my_diary_update_exchange_diary_title(
    current_setting('my_diary.e2a2_ab_diary')::uuid, 'too late'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'An archived diary title cannot be changed'
);

reset role;
select throws_ok(
  $$update public.exchange_diaries
    set state = 'active', archived_at = null, archive_cause = null
    where id = current_setting('my_diary.e2a2_ab_diary')::uuid$$,
  '23514', 'Archived exchange diaries cannot be reactivated.',
  'The existing archived-to-active trigger remains effective'
);

insert into public.exchange_diaries (id, created_by_position)
values ('a2300000-0000-4000-8000-000000000300', 1);
insert into public.exchange_diary_participants (diary_id, position, user_id)
values
  ('a2300000-0000-4000-8000-000000000300', 1,
   'a2300000-0000-4000-8000-000000000001'),
  ('a2300000-0000-4000-8000-000000000300', 2,
   'b2300000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub', 'b2300000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  public.my_diary_archive_exchange_diary(
    'a2300000-0000-4000-8000-000000000300'
  ),
  'a2300000-0000-4000-8000-000000000300'::uuid,
  'Participant 2 can independently archive a diary'
);

reset role;
insert into public.exchange_diaries (id, created_by_position)
values ('a2300000-0000-4000-8000-000000000301', 1);
insert into public.exchange_diary_participants (diary_id, position, user_id)
values
  ('a2300000-0000-4000-8000-000000000301', 1,
   'a2300000-0000-4000-8000-000000000001'),
  ('a2300000-0000-4000-8000-000000000301', 2,
   'b2300000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub', '52300000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_archive_exchange_diary(
    'a2300000-0000-4000-8000-000000000301'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A third party cannot archive a diary'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'b2300000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_archive_exchange_diary(
    'a2300000-0000-4000-8000-000000000301'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Archive fails while the other participant is suspended'
);

-- Generic resource-oracle behavior and direct mutation closure.
reset role;
update public.accounts set status = 'active'
where user_id = 'b2300000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub', 'a2300000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_archive_exchange_diary(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Unknown diary uses the same generic unavailable error'
);
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Unknown invitation uses the same generic unavailable error'
);
select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id)
    values (
      'a2300000-0000-4000-8000-000000000001',
      '62300000-0000-4000-8000-00000000000c'
    )$$,
  '42501', null,
  'authenticated still cannot mutate invitations directly'
);
select throws_ok(
  $$select * from my_diary_private.my_diary_exchange_pair_locks$$,
  '42501', null,
  'authenticated still cannot inspect pair locks directly'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'a2300000-0000-4000-8000-000000000001'
  )$$,
  '42501', null,
  'anon cannot execute exchange operation RPCs'
);

reset role;

select * from finish();

rollback;
