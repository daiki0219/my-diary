begin;

create extension if not exists pgtap with schema extensions;

select plan(83);

-- Catalog, ownership, RLS, ACL, helper, trigger, and index boundary.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where relation.relkind = 'r'
      and (
        (
          namespace.nspname = 'public'
          and relation.relname in (
            'exchange_diaries',
            'exchange_diary_participants',
            'exchange_invitations',
            'exchange_invitation_blocks'
          )
        )
        or (
          namespace.nspname = 'my_diary_private'
          and relation.relname = 'my_diary_exchange_pair_locks'
        )
      )
  ),
  5::bigint,
  'All five exchange diary foundation tables exist'
);

select is(
  (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s', attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      ) order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.exchange_diaries'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id:uuid:t', 'title:text:f', 'state:text:t',
    'created_by_position:smallint:t',
    'started_at:timestamp with time zone:t',
    'archived_at:timestamp with time zone:f', 'archive_cause:text:f',
    'created_at:timestamp with time zone:t',
    'updated_at:timestamp with time zone:t'
  ]::text[],
  'exchange_diaries has the exact foundation columns'
);

select is(
  (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s', attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      ) order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
        'public.exchange_diary_participants'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id:uuid:t', 'diary_id:uuid:t', 'position:smallint:t',
    'user_id:uuid:f', 'joined_at:timestamp with time zone:t',
    'account_deleted_at:timestamp with time zone:f'
  ]::text[],
  'exchange_diary_participants has the exact foundation columns'
);

select is(
  (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s:%s', attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull, attribute.attgenerated
      ) order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
        'public.exchange_invitations'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id:uuid:t:', 'inviter_user_id:uuid:t:', 'invitee_user_id:uuid:t:',
    'pair_low_user_id:uuid:f:s', 'pair_high_user_id:uuid:f:s',
    'status:text:t:', 'diary_id:uuid:f:',
    'created_at:timestamp with time zone:t:',
    'processed_at:timestamp with time zone:f:'
  ]::text[],
  'exchange_invitations has DB-generated canonical pair columns'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid =
        'my_diary_private.my_diary_exchange_pair_locks'::pg_catalog.regclass
      and attname = 'pair_low_user_id'
      and attnotnull
  )
  and exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid =
        'public.exchange_invitation_blocks'::pg_catalog.regclass
      and attname = 'blocked_inviter_user_id'
      and attnotnull
  ),
  'Pair lock and invite block identity columns are required'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where relation.relkind = 'r'
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
      and (
        (
          namespace.nspname = 'public'
          and relation.relname in (
            'exchange_diaries', 'exchange_diary_participants',
            'exchange_invitations', 'exchange_invitation_blocks'
          )
        )
        or (
          namespace.nspname = 'my_diary_private'
          and relation.relname = 'my_diary_exchange_pair_locks'
        )
      )
  ),
  5::bigint,
  'All exchange diary tables are owned by postgres'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_diaries', 'exchange_diary_participants',
        'exchange_invitations', 'exchange_invitation_blocks'
      )
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
  ),
  4::bigint,
  'RLS is explicitly enabled on every public exchange diary table'
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
  ),
  4::bigint,
  'Exactly four exchange diary policies exist'
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
      and permissive = 'PERMISSIVE'
  ),
  4::bigint,
  'Every exchange diary policy is authenticated SELECT-only'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_diaries', 'SELECT'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_diary_participants', 'SELECT'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitations', 'SELECT'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_invitation_blocks', 'SELECT'
  ),
  'authenticated has the required read path on all public tables'
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
  ),
  'authenticated has no direct exchange diary mutation privilege'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon', 'public.exchange_diaries', 'SELECT, INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.exchange_invitations', 'SELECT, INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'public', 'public.exchange_invitation_blocks',
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  'PUBLIC and anon have no exchange diary table privileges'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'service_role',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  'Application roles cannot access the private pair lock table'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_diary_participants'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_diary_participants_user_id_fkey'
      and contype = 'f'
      and confrelid = 'public.accounts'::pg_catalog.regclass
      and confdeltype = 'n'
  )
  and exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_diary_participants'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_diary_participants_diary_id_fkey'
      and contype = 'f'
      and confrelid = 'public.exchange_diaries'::pg_catalog.regclass
      and confdeltype = 'c'
  ),
  'Participant FKs preserve tombstones and cascade diary removal'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where contype = 'f'
      and confdeltype = 'c'
      and (
        conrelid = 'public.exchange_invitations'::pg_catalog.regclass
        or conrelid =
          'my_diary_private.my_diary_exchange_pair_locks'::pg_catalog.regclass
        or conrelid =
          'public.exchange_invitation_blocks'::pg_catalog.regclass
      )
  ),
  7::bigint,
  'Invitation, pair lock, and block FKs do not prevent account cleanup'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where convalidated
      and (
        conrelid = 'public.exchange_diaries'::pg_catalog.regclass
        or conrelid =
          'public.exchange_diary_participants'::pg_catalog.regclass
        or conrelid = 'public.exchange_invitations'::pg_catalog.regclass
        or conrelid =
          'my_diary_private.my_diary_exchange_pair_locks'::pg_catalog.regclass
        or conrelid =
          'public.exchange_invitation_blocks'::pg_catalog.regclass
      )
      and contype in ('p', 'u', 'f', 'c')
  ),
  26::bigint,
  'All 26 table constraints are present and validated'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname =
        'my_diary_exchange_diary_participants_diary_user_key'
      and index_definition.indisunique
      and index_definition.indpred is not null
  )
  and exists (
    select 1 from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname =
        'my_diary_exchange_invitations_pending_pair_key'
      and index_definition.indisunique
      and index_definition.indpred is not null
  ),
  'Participant identity and pending pairs use partial unique indexes'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
        'public.exchange_diary_participants'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_diary_participants_diary_id_id_key'
      and contype = 'u'
  ),
  'Future entries can reference a participant together with its diary'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname in (
        'my_diary_reject_exchange_diary_reactivation',
        'my_diary_enforce_exchange_diary_exact_two',
        'my_diary_enforce_exchange_invitation_transition',
        'my_diary_can_view_exchange_diary'
      )
      and function.prosecdef
      and function.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
  ),
  4::bigint,
  'All exchange helper and trigger functions are hardened and postgres-owned'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_can_view_exchange_diary'
      and function.proargtypes = '2950'::oidvector
      and function.proargnames = array['target_diary_id']::text[]
      and function.prorettype = 'boolean'::pg_catalog.regtype
      and function.provolatile = 's'
  ),
  'The read helper accepts a diary ID but no client-supplied viewer ID'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_can_view_exchange_diary(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_can_view_exchange_diary(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_can_view_exchange_diary(uuid)',
    'EXECUTE'
  ),
  'Only authenticated can execute the RLS read helper'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_reject_exchange_diary_reactivation()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_enforce_exchange_diary_exact_two()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_enforce_exchange_invitation_transition()',
    'EXECUTE'
  ),
  'Trigger functions are not directly executable by authenticated'
);

select ok(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two'
    )
      and tgdeferrable
      and tginitdeferred
      and not tgisinternal
  ) = 2
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_exchange_diaries_set_updated_at',
      'my_diary_exchange_diaries_reject_reactivation',
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two',
      'my_diary_exchange_invitations_state_transition'
    )
      and not tgisinternal
  ) = 5,
  'All five triggers exist and both exact-two triggers are initially deferred'
);

-- Constraint fixtures.
insert into auth.users (id, email)
values
  ('a2200000-0000-4000-8000-000000000001', 'e2a-a@example.test'),
  ('b2200000-0000-4000-8000-000000000002', 'e2a-b@example.test'),
  ('c2200000-0000-4000-8000-000000000003', 'e2a-c@example.test'),
  ('d2200000-0000-4000-8000-000000000004', 'e2a-d@example.test'),
  ('e2200000-0000-4000-8000-000000000005', 'e2a-e@example.test'),
  ('f2200000-0000-4000-8000-000000000006', 'e2a-f@example.test'),
  ('12200000-0000-4000-8000-000000000007', 'e2a-g@example.test'),
  ('22200000-0000-4000-8000-000000000008', 'e2a-h@example.test');

update public.accounts
set status = 'deactivated'
where user_id = 'd2200000-0000-4000-8000-000000000004';

insert into public.exchange_diaries (
  id, title, state, created_by_position, archived_at, archive_cause
)
values
  (
    'a2200000-0000-4000-8000-000000000010', null, 'active', 1,
    null, null
  ),
  (
    'a2200000-0000-4000-8000-000000000020', 'A-D archive', 'archived', 1,
    now(), 'participant_deactivated'
  ),
  (
    'a2200000-0000-4000-8000-000000000030', 'A-E archive', 'archived', 1,
    now(), 'account_deleted'
  ),
  (
    'a2200000-0000-4000-8000-000000000040', 'A-F archive', 'archived', 1,
    now(), 'ended_by_participant'
  ),
  (
    'a2200000-0000-4000-8000-000000000050', null, 'active', 2,
    null, null
  ),
  (
    'a2200000-0000-4000-8000-000000000051', '日', 'active', 1,
    null, null
  ),
  (
    'a2200000-0000-4000-8000-000000000052', repeat('界', 120),
    'active', 1, null, null
  );

insert into public.exchange_diary_participants (
  id, diary_id, position, user_id
)
values
  ('a2200000-0000-4000-8000-000000000101', 'a2200000-0000-4000-8000-000000000010', 1, 'a2200000-0000-4000-8000-000000000001'),
  ('a2200000-0000-4000-8000-000000000102', 'a2200000-0000-4000-8000-000000000010', 2, 'b2200000-0000-4000-8000-000000000002'),
  ('a2200000-0000-4000-8000-000000000201', 'a2200000-0000-4000-8000-000000000020', 1, 'a2200000-0000-4000-8000-000000000001'),
  ('a2200000-0000-4000-8000-000000000202', 'a2200000-0000-4000-8000-000000000020', 2, 'd2200000-0000-4000-8000-000000000004'),
  ('a2200000-0000-4000-8000-000000000301', 'a2200000-0000-4000-8000-000000000030', 1, 'a2200000-0000-4000-8000-000000000001'),
  ('a2200000-0000-4000-8000-000000000302', 'a2200000-0000-4000-8000-000000000030', 2, 'e2200000-0000-4000-8000-000000000005'),
  ('a2200000-0000-4000-8000-000000000401', 'a2200000-0000-4000-8000-000000000040', 1, 'a2200000-0000-4000-8000-000000000001'),
  ('a2200000-0000-4000-8000-000000000402', 'a2200000-0000-4000-8000-000000000040', 2, 'f2200000-0000-4000-8000-000000000006'),
  ('a2200000-0000-4000-8000-000000000501', 'a2200000-0000-4000-8000-000000000050', 1, 'b2200000-0000-4000-8000-000000000002'),
  ('a2200000-0000-4000-8000-000000000502', 'a2200000-0000-4000-8000-000000000050', 2, 'c2200000-0000-4000-8000-000000000003'),
  ('a2200000-0000-4000-8000-000000000511', 'a2200000-0000-4000-8000-000000000051', 1, 'c2200000-0000-4000-8000-000000000003'),
  ('a2200000-0000-4000-8000-000000000512', 'a2200000-0000-4000-8000-000000000051', 2, 'd2200000-0000-4000-8000-000000000004'),
  ('a2200000-0000-4000-8000-000000000521', 'a2200000-0000-4000-8000-000000000052', 1, 'c2200000-0000-4000-8000-000000000003'),
  ('a2200000-0000-4000-8000-000000000522', 'a2200000-0000-4000-8000-000000000052', 2, '12200000-0000-4000-8000-000000000007');

set constraints all immediate;
set constraints all deferred;

select is(
  (select title from public.exchange_diaries where id =
    'a2200000-0000-4000-8000-000000000050'),
  null::text,
  'A NULL exchange diary title is stored as NULL'
);

select is(
  (select char_length(title) from public.exchange_diaries where id =
    'a2200000-0000-4000-8000-000000000051'),
  1,
  'A one-codepoint exchange diary title is accepted'
);

select is(
  (select char_length(title) from public.exchange_diaries where id =
    'a2200000-0000-4000-8000-000000000052'),
  120,
  'A 120-codepoint exchange diary title is accepted'
);

select throws_ok(
  pg_catalog.format(
    $$insert into public.exchange_diaries
      (id, title, created_by_position)
      values ('a2200000-0000-4000-8000-000000000053', %L, 1)$$,
    repeat('界', 121)
  ),
  '23514',
  null,
  'A 121-codepoint exchange diary title is rejected'
);

select throws_ok(
  $$insert into public.exchange_diaries
    (id, title, created_by_position)
    values ('a2200000-0000-4000-8000-000000000054', ' padded ', 1)$$,
  '23514',
  null,
  'An untrimmed exchange diary title is rejected'
);

select is(
  (select state from public.exchange_diaries where id =
    'a2200000-0000-4000-8000-000000000010'),
  'active'::text,
  'An active diary with no archive metadata is valid'
);

select throws_ok(
  $$insert into public.exchange_diaries
    (id, state, created_by_position, archived_at, archive_cause)
    values (
      'a2200000-0000-4000-8000-000000000055', 'active', 1,
      now(), 'invalid'
    )$$,
  '23514',
  null,
  'An active diary cannot carry archive metadata'
);

select is(
  (select state from public.exchange_diaries where id =
    'a2200000-0000-4000-8000-000000000020'),
  'archived'::text,
  'An archived diary with complete archive metadata is valid'
);

select throws_ok(
  $$insert into public.exchange_diaries
    (id, state, created_by_position, archived_at, archive_cause)
    values (
      'a2200000-0000-4000-8000-000000000056', 'archived', 1,
      now(), null
    )$$,
  '23514',
  null,
  'An archived diary requires a nonempty archive cause'
);

select throws_ok(
  $$update public.exchange_diaries
    set state = 'active', archived_at = null, archive_cause = null
    where id = 'a2200000-0000-4000-8000-000000000020'$$,
  '23514',
  'Archived exchange diaries cannot be reactivated.',
  'An archived diary cannot return to active'
);

select throws_ok(
  $$insert into public.exchange_diary_participants
    (diary_id, position, user_id)
    values (
      'a2200000-0000-4000-8000-000000000010', 3,
      'c2200000-0000-4000-8000-000000000003'
    )$$,
  '23514',
  null,
  'Participant position 3 is rejected'
);

select throws_ok(
  $$insert into public.exchange_diary_participants
    (diary_id, position, user_id)
    values (
      'a2200000-0000-4000-8000-000000000010', 1,
      'c2200000-0000-4000-8000-000000000003'
    )$$,
  '23505',
  null,
  'A third participant cannot reuse an occupied position'
);

select throws_ok(
  $$insert into public.exchange_diaries
      (id, created_by_position)
      values ('a2200000-0000-4000-8000-000000000057', 1);
    insert into public.exchange_diary_participants
      (diary_id, position, user_id)
      values
      ('a2200000-0000-4000-8000-000000000057', 1,
       '12200000-0000-4000-8000-000000000007'),
      ('a2200000-0000-4000-8000-000000000057', 2,
       '12200000-0000-4000-8000-000000000007')$$,
  '23505',
  null,
  'The same non-null user cannot occupy both positions'
);

select throws_ok(
  $$insert into public.exchange_diaries
      (id, created_by_position)
      values ('a2200000-0000-4000-8000-000000000058', 1);
    insert into public.exchange_diary_participants
      (diary_id, position, user_id)
      values (
        'a2200000-0000-4000-8000-000000000058', 1,
        '12200000-0000-4000-8000-000000000007'
      );
    set constraints all immediate$$,
  '23514',
  'An exchange diary must have exactly two participant rows.',
  'A one-participant diary is rejected when deferred constraints run'
);

select lives_ok(
  $$insert into public.exchange_diaries
      (id, created_by_position)
      values ('a2200000-0000-4000-8000-000000000060', 1);
    insert into public.exchange_diary_participants
      (diary_id, position, user_id)
      values
      ('a2200000-0000-4000-8000-000000000060', 1,
       '12200000-0000-4000-8000-000000000007'),
      ('a2200000-0000-4000-8000-000000000060', 2,
       '22200000-0000-4000-8000-000000000008');
    set constraints all immediate;
    set constraints all deferred$$,
  'A transaction with exactly positions 1 and 2 succeeds'
);

select throws_ok(
  $$delete from public.exchange_diary_participants
    where diary_id = 'a2200000-0000-4000-8000-000000000060'
      and position = 2;
    set constraints all immediate$$,
  '23514',
  'An exchange diary must have exactly two participant rows.',
  'Deleting only one participant is rejected at the constraint boundary'
);

select lives_ok(
  $$delete from auth.users
    where id = 'e2200000-0000-4000-8000-000000000005';
    set constraints all immediate;
    set constraints all deferred$$,
  'Deleting an account can tombstone its participant without removing the row'
);

select results_eq(
  $$select user_id, position
    from public.exchange_diary_participants
    where diary_id = 'a2200000-0000-4000-8000-000000000030'
      and position = 2$$,
  $$values (null::uuid, 2::smallint)$$,
  'The account FK sets participant user_id to NULL and preserves position'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id)
    values (
      'a2200000-0000-4000-8000-000000000001',
      'a2200000-0000-4000-8000-000000000001'
    )$$,
  '23514',
  null,
  'A self invitation is rejected'
);

select lives_ok(
  $$insert into public.exchange_invitations
    (id, inviter_user_id, invitee_user_id)
    values (
      'a2200000-0000-4000-8000-000000000701',
      'd2200000-0000-4000-8000-000000000004',
      'c2200000-0000-4000-8000-000000000003'
    )$$,
  'A reverse-ordered pair can be inserted'
);

select results_eq(
  $$select pair_low_user_id, pair_high_user_id
    from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000701'$$,
  $$values (
    'c2200000-0000-4000-8000-000000000003'::uuid,
    'd2200000-0000-4000-8000-000000000004'::uuid
  )$$,
  'The database canonicalizes a reverse-ordered invitation pair'
);

insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  'a2200000-0000-4000-8000-000000000702',
  'a2200000-0000-4000-8000-000000000001',
  'b2200000-0000-4000-8000-000000000002'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id)
    values (
      'b2200000-0000-4000-8000-000000000002',
      'a2200000-0000-4000-8000-000000000001'
    )$$,
  '23505',
  null,
  'A second pending invitation for the same unordered pair is rejected'
);

select lives_ok(
  $$insert into public.exchange_invitations
    (id, inviter_user_id, invitee_user_id)
    values (
      'a2200000-0000-4000-8000-000000000703',
      'a2200000-0000-4000-8000-000000000001',
      'c2200000-0000-4000-8000-000000000003'
    )$$,
  'A different unordered pair can have a pending invitation'
);

select lives_ok(
  $$insert into public.exchange_invitations
    (id, inviter_user_id, invitee_user_id, status, processed_at)
    values
    (
      'a2200000-0000-4000-8000-000000000704',
      'a2200000-0000-4000-8000-000000000001',
      'b2200000-0000-4000-8000-000000000002',
      'rejected', now()
    ),
    (
      'a2200000-0000-4000-8000-000000000705',
      'b2200000-0000-4000-8000-000000000002',
      'a2200000-0000-4000-8000-000000000001',
      'cancelled', now()
    )$$,
  'The same pair can retain multiple terminal history rows'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id, status, processed_at)
    values (
      '12200000-0000-4000-8000-000000000007',
      '22200000-0000-4000-8000-000000000008',
      'pending', now()
    )$$,
  '23514',
  null,
  'A pending invitation cannot have processed_at'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id, status, processed_at)
    values (
      '12200000-0000-4000-8000-000000000007',
      '22200000-0000-4000-8000-000000000008',
      'accepted', now()
    )$$,
  '23514',
  null,
  'An accepted invitation requires a diary ID'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id, status)
    values (
      '12200000-0000-4000-8000-000000000007',
      '22200000-0000-4000-8000-000000000008',
      'rejected'
    )$$,
  '23514',
  null,
  'A rejected invitation requires processed_at'
);

select lives_ok(
  $$update public.exchange_invitations
    set status = 'accepted', processed_at = now(),
        diary_id = 'a2200000-0000-4000-8000-000000000010'
    where id = 'a2200000-0000-4000-8000-000000000702'$$,
  'A pending invitation can transition atomically to accepted'
);

select throws_ok(
  $$update public.exchange_invitations
    set status = 'pending', processed_at = null, diary_id = null
    where id = 'a2200000-0000-4000-8000-000000000704'$$,
  '23514',
  'A terminal exchange invitation cannot change state.',
  'A terminal invitation cannot return to pending'
);

select throws_ok(
  $$update public.exchange_invitations
    set status = 'invalidated'
    where id = 'a2200000-0000-4000-8000-000000000704'$$,
  '23514',
  'A terminal exchange invitation cannot change state.',
  'A terminal invitation cannot change to another terminal state'
);

select throws_ok(
  $$insert into my_diary_private.my_diary_exchange_pair_locks
    (pair_low_user_id, pair_high_user_id)
    values (
      'b2200000-0000-4000-8000-000000000002',
      'a2200000-0000-4000-8000-000000000001'
    )$$,
  '23514',
  null,
  'A noncanonical pair lock is rejected'
);

select lives_ok(
  $$insert into my_diary_private.my_diary_exchange_pair_locks
    (pair_low_user_id, pair_high_user_id)
    values (
      'a2200000-0000-4000-8000-000000000001',
      'b2200000-0000-4000-8000-000000000002'
    )$$,
  'A canonical private pair lock can be created by the database owner'
);

select throws_ok(
  $$insert into public.exchange_invitation_blocks
    (blocker_user_id, blocked_inviter_user_id)
    values (
      'a2200000-0000-4000-8000-000000000001',
      'a2200000-0000-4000-8000-000000000001'
    )$$,
  '23514',
  null,
  'An exchange invitation self-block is rejected'
);

select lives_ok(
  $$insert into public.exchange_invitation_blocks
    (blocker_user_id, blocked_inviter_user_id)
    values (
      'a2200000-0000-4000-8000-000000000001',
      'b2200000-0000-4000-8000-000000000002'
    )$$,
  'A database-owner fixture can create an exchange invitation block'
);

insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id, status, processed_at
)
values
  (
    'a2200000-0000-4000-8000-000000000706',
    'a2200000-0000-4000-8000-000000000001',
    'b2200000-0000-4000-8000-000000000002',
    'invalidated', now()
  );

insert into public.exchange_invitations (
  id, inviter_user_id, invitee_user_id
)
values (
  'a2200000-0000-4000-8000-000000000707',
  'a2200000-0000-4000-8000-000000000001',
  'b2200000-0000-4000-8000-000000000002'
);

-- Participant-only and state-aware RLS boundary.
select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$values ('a2200000-0000-4000-8000-000000000010'::uuid)$$,
  'Active participant A can read the active A-B diary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2200000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$values ('a2200000-0000-4000-8000-000000000010'::uuid)$$,
  'Active participant B can read the active A-B diary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2200000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$select null::uuid where false$$,
  'Nonparticipant C cannot read the A-B diary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_diary_participants
    where diary_id = 'a2200000-0000-4000-8000-000000000010'
  ),
  2::bigint,
  'A visible diary exposes both participant rows to a participant'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2200000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_diary_participants
    where diary_id = 'a2200000-0000-4000-8000-000000000010'
  ),
  0::bigint,
  'A nonparticipant cannot read participant rows and RLS does not recurse'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'b2200000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$select null::uuid where false$$,
  'Active A cannot read an active diary while B is suspended'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2200000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$select null::uuid where false$$,
  'Suspended B cannot read the active diary'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'b2200000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000010'$$,
  $$values ('a2200000-0000-4000-8000-000000000010'::uuid)$$,
  'Reactivating B restores the active diary to A'
);

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000020'$$,
  $$values ('a2200000-0000-4000-8000-000000000020'::uuid)$$,
  'Active A can read an archived diary with deactivated D'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2200000-0000-4000-8000-000000000004',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000020'$$,
  $$select null::uuid where false$$,
  'Deactivated D cannot read its archived diary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000030'$$,
  $$values ('a2200000-0000-4000-8000-000000000030'::uuid)$$,
  'Active A can read an archived diary with a deleted-user tombstone'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'f2200000-0000-4000-8000-000000000006';

select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_diaries
    where id = 'a2200000-0000-4000-8000-000000000040'$$,
  $$select null::uuid where false$$,
  'An archived diary is hidden while the other participant is suspended'
);

select results_eq(
  $$select id from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000707'$$,
  $$values ('a2200000-0000-4000-8000-000000000707'::uuid)$$,
  'Active inviter A can read its pending invitation'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2200000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000707'$$,
  $$values ('a2200000-0000-4000-8000-000000000707'::uuid)$$,
  'Active invitee B can read its pending invitation'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2200000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000707'$$,
  $$select null::uuid where false$$,
  'A nonparty cannot read another pair pending invitation'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select results_eq(
  $$select id from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000704'$$,
  $$values ('a2200000-0000-4000-8000-000000000704'::uuid)$$,
  'Rejected invitation history remains visible to its active inviter'
);

select results_eq(
  $$select id from public.exchange_invitations
    where id = 'a2200000-0000-4000-8000-000000000706'$$,
  $$select null::uuid where false$$,
  'An invalidated invitation is not exposed to either party'
);

select results_eq(
  $$select blocker_user_id, blocked_inviter_user_id
    from public.exchange_invitation_blocks
    where blocker_user_id = 'a2200000-0000-4000-8000-000000000001'
      and blocked_inviter_user_id =
        'b2200000-0000-4000-8000-000000000002'$$,
  $$values (
    'a2200000-0000-4000-8000-000000000001'::uuid,
    'b2200000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Only blocker A can read its exchange invitation block'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2200000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_invitation_blocks
    where blocker_user_id = 'a2200000-0000-4000-8000-000000000001'
      and blocked_inviter_user_id =
        'b2200000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'The blocked side cannot detect an exchange invitation block row'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2200000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

select results_eq(
  $$select
      my_diary_private.my_diary_can_view_exchange_diary(
        'a2200000-0000-4000-8000-000000000010'
      ),
      my_diary_private.my_diary_can_view_exchange_diary(
        'ffffffff-ffff-4fff-8fff-ffffffffffff'
      )$$,
  $$values (false, false)$$,
  'The helper returns the same false result for nonowned and unknown diary IDs'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.exchange_diaries$$,
  '42501',
  null,
  'anon cannot read exchange diaries'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2200000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$insert into public.exchange_diaries (created_by_position) values (1)$$,
  '42501',
  null,
  'authenticated cannot directly insert a diary'
);

select throws_ok(
  $$update public.exchange_diary_participants
    set account_deleted_at = now()
    where diary_id = 'a2200000-0000-4000-8000-000000000010'$$,
  '42501',
  null,
  'authenticated cannot directly update participants'
);

select throws_ok(
  $$insert into public.exchange_invitations
    (inviter_user_id, invitee_user_id)
    values (
      'a2200000-0000-4000-8000-000000000001',
      'c2200000-0000-4000-8000-000000000003'
    )$$,
  '42501',
  null,
  'authenticated cannot directly insert an invitation'
);

select throws_ok(
  $$delete from public.exchange_invitation_blocks
    where blocker_user_id = 'a2200000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'authenticated cannot directly delete an invitation block'
);

select throws_ok(
  $$select * from my_diary_private.my_diary_exchange_pair_locks$$,
  '42501',
  null,
  'authenticated cannot inspect private pair locks'
);

reset role;

select * from finish();

rollback;
