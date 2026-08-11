begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- Hardened trigger catalog and unchanged authorization boundaries.
select ok(
  (
    select
      function_definition.pronargs = 0
      and function_definition.pronargdefaults = 0
      and function_definition.prorettype = 'trigger'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_language as language
      on language.oid = function_definition.prolang
    where function_definition.oid =
      'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()'
        ::pg_catalog.regprocedure
  ),
  'the deactivation archive trigger helper is exact and hardened'
);

select ok(
  not pg_catalog.has_function_privilege(
    'public',
    'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_archive_exchange_diaries_on_deactivation()',
    'EXECUTE'
  ),
  'no application role can execute the lifecycle trigger helper'
);

select ok(
  exists (
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
  ),
  'the enabled non-deferrable lifecycle trigger is attached to accounts'
);

select ok(
  (
    select pg_catalog.pg_get_triggerdef(trigger_definition.oid)
    from pg_catalog.pg_trigger as trigger_definition
    where trigger_definition.tgname =
      'my_diary_accounts_archive_exchange_diaries_on_deactivation'
  ) like
    'CREATE TRIGGER my_diary_accounts_archive_exchange_diaries_on_deactivation AFTER UPDATE OF status ON public.accounts FOR EACH ROW%',
  'the lifecycle trigger fires only after row-level status updates'
);

select ok(
  (
    select relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.accounts'::pg_catalog.regclass
  )
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname in (
        'my_diary_accounts_select_own',
        'my_diary_accounts_update_own_timezone'
      )
      and roles = array['authenticated']::name[]
  ) = 2,
  'accounts ownership, RLS, and its two existing policies are unchanged'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.accounts', 'SELECT'
  )
  and pg_catalog.has_column_privilege(
    'authenticated', 'public.accounts', 'timezone', 'UPDATE'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.accounts', 'status', 'UPDATE'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.accounts', 'role', 'UPDATE'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.accounts', 'user_id', 'UPDATE'
  ),
  'the lifecycle migration does not broaden accounts ACL'
);

select ok(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries', 'exchange_diary_participants',
        'exchange_invitations', 'exchange_invitation_blocks',
        'exchange_entries', 'exchange_entry_tags', 'exchange_entry_images',
        'exchange_notification_preferences', 'exchange_diary_mutes',
        'reports', 'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
  ) = 12
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_diaries', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entries', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entry_images', 'INSERT, UPDATE, DELETE'
  )
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) = 11,
  'exchange table and hardened Storage RLS/ACL boundaries are intact'
);

select ok(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) = 2
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.notifications', 'INSERT, DELETE'
  )
  and pg_catalog.has_column_privilege(
    'authenticated', 'public.notifications', 'is_read', 'UPDATE'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.notifications', 'exchange_diary_id', 'UPDATE'
  ),
  'notification policies and mutation ACL are unchanged'
);

-- Lifecycle fixtures: A owns three active diaries, two with the same B pair.
insert into auth.users (id, email)
values
  ('a2800000-0000-4000-8000-000000000001', 'e2e-a@example.test'),
  ('b2800000-0000-4000-8000-000000000002', 'e2e-b@example.test'),
  ('c2800000-0000-4000-8000-000000000003', 'e2e-c@example.test'),
  ('d2800000-0000-4000-8000-000000000004', 'e2e-d@example.test'),
  ('e2800000-0000-4000-8000-000000000005', 'e2e-e@example.test'),
  ('f2800000-0000-4000-8000-000000000006', 'e2e-f@example.test'),
  ('72800000-0000-4000-8000-000000000007', 'e2e-g@example.test'),
  ('82800000-0000-4000-8000-000000000008', 'e2e-h@example.test'),
  ('92800000-0000-4000-8000-000000000009', 'e2e-i@example.test'),
  ('a2800000-0000-4000-8000-000000000010', 'e2e-j@example.test');

insert into public.exchange_diaries (
  id, created_by_position, state, archived_at, archive_cause, updated_at
)
values
  ('d2800000-0000-4000-8000-000000000001', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000002', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000003', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000004', 1, 'archived',
   '2026-02-01 00:00:00+00', 'ended_by_participant',
   '2026-02-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000005', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000006', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000007', 1, 'active', null, null,
   '2026-01-01 00:00:00+00'),
  ('d2800000-0000-4000-8000-000000000008', 1, 'active', null, null,
   '2026-01-01 00:00:00+00');

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('12800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000001', 1,
   'a2800000-0000-4000-8000-000000000001'),
  ('12800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000001', 2,
   'b2800000-0000-4000-8000-000000000002'),
  ('22800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000002', 1,
   'a2800000-0000-4000-8000-000000000001'),
  ('22800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000002', 2,
   'b2800000-0000-4000-8000-000000000002'),
  ('32800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000003', 1,
   'a2800000-0000-4000-8000-000000000001'),
  ('32800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000003', 2,
   'c2800000-0000-4000-8000-000000000003'),
  ('42800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000004', 1,
   'a2800000-0000-4000-8000-000000000001'),
  ('42800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000004', 2,
   'b2800000-0000-4000-8000-000000000002'),
  ('52800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000005', 1,
   'd2800000-0000-4000-8000-000000000004'),
  ('52800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000005', 2,
   'e2800000-0000-4000-8000-000000000005'),
  ('62800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000006', 1,
   'f2800000-0000-4000-8000-000000000006'),
  ('62800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000006', 2,
   '72800000-0000-4000-8000-000000000007'),
  ('72800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000007', 1,
   '82800000-0000-4000-8000-000000000008'),
  ('72800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000007', 2,
   '92800000-0000-4000-8000-000000000009'),
  ('82800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000008', 1,
   '82800000-0000-4000-8000-000000000008'),
  ('82800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000008', 2,
   'a2800000-0000-4000-8000-000000000010');

set constraints all immediate;
set constraints all deferred;

insert into public.exchange_entries
  (id, diary_id, author_participant_id, body)
values
  ('e2800000-0000-4000-8000-000000000001',
   'd2800000-0000-4000-8000-000000000001',
   '12800000-0000-4000-8000-000000000001', 'A entry'),
  ('e2800000-0000-4000-8000-000000000002',
   'd2800000-0000-4000-8000-000000000001',
   '12800000-0000-4000-8000-000000000002', 'B entry');

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2820000-0000-4000-8000-000000000001',
  'exchange-entry-images',
  'a2800000-0000-4000-8000-000000000001/d2800000-0000-4000-8000-000000000001/e2800000-0000-4000-8000-000000000001/f2800000-0000-4000-8000-000000000001',
  'a2800000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'
);

insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f2800000-0000-4000-8000-000000000001',
  'e2800000-0000-4000-8000-000000000001',
  'a2800000-0000-4000-8000-000000000001/d2800000-0000-4000-8000-000000000001/e2800000-0000-4000-8000-000000000001/f2800000-0000-4000-8000-000000000001',
  0
);

insert into public.exchange_invitations
  (id, inviter_user_id, invitee_user_id, status)
values (
  '12800000-0000-4000-8000-000000000100',
  'a2800000-0000-4000-8000-000000000001',
  'd2800000-0000-4000-8000-000000000004',
  'pending'
);

update public.accounts
set status = 'deactivated'
where user_id = 'a2800000-0000-4000-8000-000000000001';

select is(
  (select status from public.accounts
   where user_id = 'a2800000-0000-4000-8000-000000000001'),
  'deactivated'::text,
  'active to deactivated commits the account transition'
);

select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id in (
     'd2800000-0000-4000-8000-000000000001',
     'd2800000-0000-4000-8000-000000000002',
     'd2800000-0000-4000-8000-000000000003'
   ) and state = 'archived'),
  3::bigint,
  'all three active diaries are archived, including the same-pair pair'
);

select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id in (
     'd2800000-0000-4000-8000-000000000001',
     'd2800000-0000-4000-8000-000000000002',
     'd2800000-0000-4000-8000-000000000003'
   ) and archived_at is not null
     and archive_cause = 'participant_deactivated'),
  3::bigint,
  'automatic archives have DB timestamps and the lifecycle cause'
);

select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id in (
     'd2800000-0000-4000-8000-000000000001',
     'd2800000-0000-4000-8000-000000000002',
     'd2800000-0000-4000-8000-000000000003'
   ) and updated_at > '2026-01-01 00:00:00+00'),
  3::bigint,
  'automatic archive updates each diary updated_at'
);

select results_eq(
  $$select state, archived_at, archive_cause, updated_at
    from public.exchange_diaries
    where id = 'd2800000-0000-4000-8000-000000000004'$$,
  $$values (
      'archived'::text, '2026-02-01 00:00:00+00'::timestamptz,
      'ended_by_participant'::text,
      '2026-02-01 00:00:00+00'::timestamptz
    )$$,
  'an existing manual archive keeps all lifecycle metadata'
);

select results_eq(
  $$select state, archived_at, archive_cause
    from public.exchange_diaries
    where id = 'd2800000-0000-4000-8000-000000000005'$$,
  $$values ('active'::text, null::timestamptz, null::text)$$,
  'a nonparticipant diary is unchanged'
);

select is(
  (select status from public.exchange_invitations
   where id = '12800000-0000-4000-8000-000000000100'),
  'pending'::text,
  'deactivation does not transition pending invitations'
);

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.notifications),
      (select pg_catalog.count(*) from public.reports)$$,
  $$values (0::bigint, 0::bigint)$$,
  'deactivation creates no notification and no report or evidence row'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'b2800000-0000-4000-8000-000000000002', true
);
set local role authenticated;

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.exchange_diaries
       where id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_diary_participants
       where diary_id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entries
       where diary_id = 'd2800000-0000-4000-8000-000000000001')$$,
  $$values (1::bigint, 2::bigint, 2::bigint)$$,
  'the active counterpart sees the archived diary, participants, and entries'
);

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.exchange_entry_images
       where id = 'f2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from storage.objects
       where bucket_id = 'exchange-entry-images'
         and name like '%/f2800000-0000-4000-8000-000000000001')$$,
  $$values (1::bigint, 1::bigint)$$,
  'the active counterpart sees image metadata and its referenced Storage row'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2800000-0000-4000-8000-000000000001', true
);
set local role authenticated;

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.exchange_diaries
       where id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entries
       where diary_id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entry_images
       where id = 'f2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from storage.objects
       where bucket_id = 'exchange-entry-images'
         and name like '%/f2800000-0000-4000-8000-000000000001')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'the deactivated participant sees none of the archived diary data'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2800000-0000-4000-8000-000000000004', true
);
set local role authenticated;

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.exchange_diaries
       where id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entries
       where diary_id = 'd2800000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entry_images
       where id = 'f2800000-0000-4000-8000-000000000001')$$,
  $$values (0::bigint, 0::bigint, 0::bigint)$$,
  'an active nonparticipant sees none of the archived diary data'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2800000-0000-4000-8000-000000000002', true
);
set local role authenticated;

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2800000-0000-4000-8000-000000000001',
      null, 'blocked by archive', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'the active counterpart cannot create in the automatic archive'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      'e2800000-0000-4000-8000-000000000002',
      null, 'blocked by archive', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'the active counterpart cannot edit in the automatic archive'
);

select lives_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      'e2800000-0000-4000-8000-000000000002'
    )$$,
  'the active counterpart can soft delete their own archived entry'
);

reset role;
select results_eq(
  $$select body, deleted_at is not null, redaction_reason
    from public.exchange_entries
    where id = 'e2800000-0000-4000-8000-000000000002'$$,
  $$values (null::text, true, 'user_deleted'::text)$$,
  'archived self-delete keeps the expected redacted shape'
);

select set_config(
  'my_diary.e2e_first_archived_at',
  (select archived_at::text from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000001'), true
);
select set_config(
  'my_diary.e2e_first_updated_at',
  (select updated_at::text from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000001'), true
);

update public.accounts
set status = 'active'
where user_id = 'a2800000-0000-4000-8000-000000000001';

select ok(
  (select status = 'active' from public.accounts
   where user_id = 'a2800000-0000-4000-8000-000000000001')
  and (
    select pg_catalog.count(*) = 3
    from public.exchange_diaries
    where id in (
      'd2800000-0000-4000-8000-000000000001',
      'd2800000-0000-4000-8000-000000000002',
      'd2800000-0000-4000-8000-000000000003'
    ) and state = 'archived'
  ),
  'reactivation restores the account but none of its diaries'
);

select ok(
  (select archived_at =
      current_setting('my_diary.e2e_first_archived_at')::timestamptz
     and updated_at =
      current_setting('my_diary.e2e_first_updated_at')::timestamptz
     and archive_cause = 'participant_deactivated'
   from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000001'),
  'reactivation does not rewrite automatic archive metadata'
);

-- Suspended remains temporary, while suspended to deactivated archives.
update public.accounts
set status = 'suspended'
where user_id = 'f2800000-0000-4000-8000-000000000006';

select results_eq(
  $$select state, archived_at, archive_cause
    from public.exchange_diaries
    where id = 'd2800000-0000-4000-8000-000000000006'$$,
  $$values ('active'::text, null::timestamptz, null::text)$$,
  'active to suspended does not archive the diary'
);

select set_config(
  'request.jwt.claim.sub',
  'f2800000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000006'),
  0::bigint,
  'the suspended participant cannot see the still-active diary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '72800000-0000-4000-8000-000000000007', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000006'),
  0::bigint,
  'the active counterpart cannot see a diary with a suspended participant'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'f2800000-0000-4000-8000-000000000006';
select set_config(
  'request.jwt.claim.sub',
  'f2800000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select ok(
  (select state = 'active' from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000006'),
  'suspended to active restores the same active diary for that participant'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '72800000-0000-4000-8000-000000000007', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000006'),
  1::bigint,
  'suspended to active restores the same diary for the counterpart'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'f2800000-0000-4000-8000-000000000006';
update public.accounts
set status = 'deactivated'
where user_id = 'f2800000-0000-4000-8000-000000000006';

select results_eq(
  $$select state, archived_at is not null, archive_cause
    from public.exchange_diaries
    where id = 'd2800000-0000-4000-8000-000000000006'$$,
  $$values ('archived'::text, true, 'participant_deactivated'::text)$$,
  'suspended to deactivated archives the active diary'
);

update public.accounts
set status = 'deactivated'
where user_id = 'b2800000-0000-4000-8000-000000000002';

select ok(
  (select archived_at =
      current_setting('my_diary.e2e_first_archived_at')::timestamptz
     and updated_at =
      current_setting('my_diary.e2e_first_updated_at')::timestamptz
     and archive_cause = 'participant_deactivated'
   from public.exchange_diaries
   where id = 'd2800000-0000-4000-8000-000000000001'),
  'deactivating the other participant does not overwrite the first archive'
);

-- A forced diary failure rolls the account and every earlier diary update back.
create function pg_temp.my_diary_force_deactivation_archive_failure()
returns trigger
language plpgsql
as $function$
begin
  if new.id = 'd2800000-0000-4000-8000-000000000008'
     and new.state = 'archived' then
    raise exception 'Forced deactivation archive failure.';
  end if;
  return new;
end;
$function$;

create trigger my_diary_test_force_deactivation_archive_failure
before update of state on public.exchange_diaries
for each row execute function
  pg_temp.my_diary_force_deactivation_archive_failure();

select throws_ok(
  $$update public.accounts
    set status = 'deactivated'
    where user_id = '82800000-0000-4000-8000-000000000008'$$,
  'P0001', 'Forced deactivation archive failure.',
  'a late archive failure aborts the account status statement'
);

drop trigger my_diary_test_force_deactivation_archive_failure
  on public.exchange_diaries;

select is(
  (select status from public.accounts
   where user_id = '82800000-0000-4000-8000-000000000008'),
  'active'::text,
  'the failed status statement rolls the account back to active'
);

select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id in (
     'd2800000-0000-4000-8000-000000000007',
     'd2800000-0000-4000-8000-000000000008'
   ) and state = 'active'),
  2::bigint,
  'the failed status statement rolls every affected diary back to active'
);

select is(
  (select pg_catalog.count(*) from public.exchange_diaries
   where id in (
     'd2800000-0000-4000-8000-000000000007',
     'd2800000-0000-4000-8000-000000000008'
   ) and archived_at is null
     and archive_cause is null
     and updated_at = '2026-01-01 00:00:00+00'),
  2::bigint,
  'the failed status statement rolls all archive metadata back atomically'
);

select * from finish();

rollback;
