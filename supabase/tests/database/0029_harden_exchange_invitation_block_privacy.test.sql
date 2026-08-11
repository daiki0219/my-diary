begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

-- The replacement RPC keeps the hardened catalog and changes only the
-- externally visible terminal state used for an incoming pending invitation.
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname =
            'my_diary_block_exchange_invitations_from_user'
      and function_definition.proargtypes = '2950'::oidvector
      and function_definition.proargnames = array['p_user_id']::text[]
      and function_definition.prorettype = 'boolean'::regtype
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
            like '%set status = ''rejected''%'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
            not like '%set status = ''invalidated''%'
  ),
  'Block RPC is hardened and writes the ordinary rejected terminal state'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_block_exchange_invitations_from_user(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_block_exchange_invitations_from_user(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_block_exchange_invitations_from_user(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_block_exchange_invitations_from_user(uuid)',
    'EXECUTE'
  ),
  'Block RPC remains executable by authenticated only'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgrelid =
            'public.exchange_invitations'::pg_catalog.regclass
      and trigger_definition.tgname =
            'my_diary_exchange_invitations_state_transition'
      and not trigger_definition.tgisinternal
      and trigger_definition.tgenabled = 'O'
  ),
  'Invitation terminal-state transition trigger is enabled after backfill'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'exchange_invitations'
      and policyname =
            'my_diary_exchange_invitations_select_party_noninvalidated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%status <> ''invalidated''%'
  ),
  'Invitation party SELECT policy remains unchanged'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_cooldown_pair_idx'
      and indexdef like '%rejected%'
      and indexdef like '%cancelled%'
  ),
  'Pending uniqueness and shared rejection/cancellation cooldown indexes remain'
);

select is(
  (select pg_catalog.count(*)
   from public.exchange_invitations
   where status = 'invalidated'),
  0::bigint,
  'Migration leaves no historical invalidated invitation rows'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
            'public.exchange_invitations'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  9::bigint,
  'Privacy hardening adds no public termination-cause column'
);

-- A is the common inviter. A-B is the block path and A-C is the explicit
-- reject control, so one viewer can compare both external outcomes.
insert into auth.users (id, email)
values
  ('a2900000-0000-4000-8000-000000000001', 'e2f1b-a@example.test'),
  ('b2900000-0000-4000-8000-000000000002', 'e2f1b-b@example.test'),
  ('c2900000-0000-4000-8000-000000000003', 'e2f1b-c@example.test');

insert into public.follows (follower_id, following_id)
values
  ('a2900000-0000-4000-8000-000000000001',
   'b2900000-0000-4000-8000-000000000002'),
  ('b2900000-0000-4000-8000-000000000002',
   'a2900000-0000-4000-8000-000000000001'),
  ('a2900000-0000-4000-8000-000000000001',
   'c2900000-0000-4000-8000-000000000003'),
  ('c2900000-0000-4000-8000-000000000003',
   'a2900000-0000-4000-8000-000000000001');

select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config(
  'my_diary.e2f1b_block_invitation',
  public.my_diary_create_exchange_invitation(
    'b2900000-0000-4000-8000-000000000002'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2f1b_block_invitation')::uuid is not null,
  'Inviter receives the UUID for the invitation later ended by block'
);

select set_config(
  'my_diary.e2f1b_reject_invitation',
  public.my_diary_create_exchange_invitation(
    'c2900000-0000-4000-8000-000000000003'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2f1b_reject_invitation')::uuid is not null,
  'Inviter receives the UUID for the explicit-reject control invitation'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_invitations
    where id in (
      current_setting('my_diary.e2f1b_block_invitation')::uuid,
      current_setting('my_diary.e2f1b_reject_invitation')::uuid
    )
      and status = 'pending'
  ),
  2::bigint,
  'Inviter can read both known pending invitation UUIDs before termination'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2f1b_block_invitation')::uuid),
  1::bigint,
  'Block-path invitee sees exactly one original invitation notification'
);
select is(
  public.my_diary_block_exchange_invitations_from_user(
    'a2900000-0000-4000-8000-000000000001'
  ),
  true,
  'Invitee can block the known pending inviter'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'c2900000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2f1b_reject_invitation')::uuid),
  1::bigint,
  'Reject-path invitee sees exactly one original invitation notification'
);
select is(
  public.my_diary_reject_exchange_invitation(
    current_setting('my_diary.e2f1b_reject_invitation')::uuid
  ),
  true,
  'Control invitee explicitly rejects the known pending invitation'
);

reset role;
select results_eq(
  $$select status, processed_at is not null, diary_id
    from public.exchange_invitations
    where id in (
      current_setting('my_diary.e2f1b_block_invitation')::uuid,
      current_setting('my_diary.e2f1b_reject_invitation')::uuid
    )
    order by id$$,
  $$values
    ('rejected'::text, true, null::uuid),
    ('rejected'::text, true, null::uuid)$$,
  'Block and explicit reject persist the same terminal database shape'
);

select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.jsonb_build_object(
      'row_count', pg_catalog.count(*),
      'shape_count', pg_catalog.count(
        distinct pg_catalog.jsonb_build_object(
          'status', invitation.status,
          'diary_id_is_null', invitation.diary_id is null,
          'processed_at_is_null', invitation.processed_at is null
        )
      )
    )
    from public.exchange_invitations as invitation
    where invitation.id in (
      current_setting('my_diary.e2f1b_block_invitation')::uuid,
      current_setting('my_diary.e2f1b_reject_invitation')::uuid
    )
  ),
  '{"row_count": 2, "shape_count": 1}'::jsonb,
  'Inviter sees both known rows with one indistinguishable external shape'
);
select is(
  (select pg_catalog.count(*) from public.exchange_invitation_blocks
   where blocker_user_id = 'b2900000-0000-4000-8000-000000000002'
     and blocked_inviter_user_id =
       'a2900000-0000-4000-8000-000000000001'),
  0::bigint,
  'Blocked inviter cannot read the block relation'
);
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'b2900000-0000-4000-8000-000000000002'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Create while blocked returns the existing generic unavailable error'
);
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'c2900000-0000-4000-8000-000000000003'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Explicit reject cooldown returns the same generic unavailable error'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2f1b_block_invitation')::uuid),
  1::bigint,
  'Block-induced rejection keeps the original recipient notification visible'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'c2900000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2f1b_reject_invitation')::uuid),
  1::bigint,
  'Explicit rejection keeps the same original recipient notification visible'
);

reset role;
select is(
  (select pg_catalog.count(*)
   from public.notifications
   where exchange_invitation_id in (
     current_setting('my_diary.e2f1b_block_invitation')::uuid,
     current_setting('my_diary.e2f1b_reject_invitation')::uuid
   )),
  2::bigint,
  'Block creates no additional notification compared with explicit reject'
);

select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  public.my_diary_unblock_exchange_invitations_from_user(
    'a2900000-0000-4000-8000-000000000001'
  ),
  true,
  'Blocker can remove the invitation block'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'b2900000-0000-4000-8000-000000000002'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Unblock does not bypass the shared 24-hour rejection cooldown'
);

reset role;
update public.exchange_invitations
set processed_at = now() - interval '24 hours 1 minute'
where id = current_setting('my_diary.e2f1b_block_invitation')::uuid;

select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e2f1b_fresh_block_pair_invitation',
  public.my_diary_create_exchange_invitation(
    'b2900000-0000-4000-8000-000000000002'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2f1b_fresh_block_pair_invitation')::uuid
    is not null,
  'Unblocked pair can create again after the shared 24-hour cooldown'
);

-- Explicit status matrix for active parties and a third party. The fresh A-B
-- invitation supplies pending; the prior block supplies rejected.
reset role;
insert into public.exchange_diaries (id, title, state, created_by_position)
values (
  'a2900000-0000-4000-8000-000000000100',
  null, 'active', 1
);
insert into public.exchange_diary_participants (diary_id, position, user_id)
values
  ('a2900000-0000-4000-8000-000000000100', 1,
   'a2900000-0000-4000-8000-000000000001'),
  ('a2900000-0000-4000-8000-000000000100', 2,
   'b2900000-0000-4000-8000-000000000002');
insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id, status, processed_at, diary_id
)
values
  ('a2900000-0000-4000-8000-000000000101',
   'a2900000-0000-4000-8000-000000000001',
   'b2900000-0000-4000-8000-000000000002',
   'accepted', now(), 'a2900000-0000-4000-8000-000000000100'),
  ('a2900000-0000-4000-8000-000000000102',
   'a2900000-0000-4000-8000-000000000001',
   'b2900000-0000-4000-8000-000000000002',
   'cancelled', now(), null),
  ('a2900000-0000-4000-8000-000000000103',
   'a2900000-0000-4000-8000-000000000001',
   'b2900000-0000-4000-8000-000000000002',
   'invalidated', now(), null);

select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select results_eq(
  $$select status
    from public.exchange_invitations
    where pair_low_user_id =
            'a2900000-0000-4000-8000-000000000001'
      and pair_high_user_id =
            'b2900000-0000-4000-8000-000000000002'
    order by status$$,
  $$values
    ('accepted'::text),
    ('cancelled'::text),
    ('pending'::text),
    ('rejected'::text)$$,
  'Active inviter sees pending and every non-invalidated terminal status'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select results_eq(
  $$select status
    from public.exchange_invitations
    where pair_low_user_id =
            'a2900000-0000-4000-8000-000000000001'
      and pair_high_user_id =
            'b2900000-0000-4000-8000-000000000002'
    order by status$$,
  $$values
    ('accepted'::text),
    ('cancelled'::text),
    ('pending'::text),
    ('rejected'::text)$$,
  'Active invitee sees pending and every non-invalidated terminal status'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'c2900000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.exchange_invitations
   where pair_low_user_id =
           'a2900000-0000-4000-8000-000000000001'
     and pair_high_user_id =
           'b2900000-0000-4000-8000-000000000002'),
  0::bigint,
  'Active third party sees no invitation status for another pair'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.exchange_invitations
   where id = 'a2900000-0000-4000-8000-000000000103'),
  0::bigint,
  'Historical invalidated state remains hidden from an active party'
);

reset role;
select throws_ok(
  $$update public.exchange_invitations
    set status = 'rejected'
    where id = 'a2900000-0000-4000-8000-000000000103'$$,
  '23514', 'A terminal exchange invitation cannot change state.',
  'Transition trigger is active again after the migration backfill'
);

-- Re-block the fresh pending row, age its rejection, and prove the persistent
-- block row still wins. The same terminal row also supplies sequential
-- block-first regressions for accept/reject/cancel without claiming true
-- multi-session concurrency coverage.
select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  public.my_diary_block_exchange_invitations_from_user(
    'a2900000-0000-4000-8000-000000000001'
  ),
  true,
  'Re-block rejects the fresh pending invitation'
);

reset role;
update public.exchange_invitations
set processed_at = now() - interval '24 hours 1 minute'
where pair_low_user_id = 'a2900000-0000-4000-8000-000000000001'
  and pair_high_user_id = 'b2900000-0000-4000-8000-000000000002'
  and status in ('rejected', 'cancelled');

select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
    'b2900000-0000-4000-8000-000000000002'
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'A persistent block rejects create even after rejection cooldown has elapsed'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'b2900000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
    current_setting('my_diary.e2f1b_fresh_block_pair_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Block-first terminal state prevents a later accept'
);
select throws_ok(
  $$select public.my_diary_reject_exchange_invitation(
    current_setting('my_diary.e2f1b_fresh_block_pair_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Block-first terminal state prevents a later explicit reject'
);

reset role;
select set_config(
  'request.jwt.claim.sub', 'a2900000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_cancel_exchange_invitation(
    current_setting('my_diary.e2f1b_fresh_block_pair_invitation')::uuid
  )$$,
  '42501', 'Exchange diary operation is unavailable.',
  'Block-first terminal state prevents a later cancel'
);
select is(
  (select status
   from public.exchange_invitations
   where id =
     current_setting('my_diary.e2f1b_fresh_block_pair_invitation')::uuid),
  'rejected'::text,
  'Sequential block-first operations preserve one rejected final state'
);

reset role;

select * from finish();

rollback;
