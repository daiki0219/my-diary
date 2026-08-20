begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

select set_config(
  'my_diary.maintenance_base_time',
  pg_catalog.statement_timestamp()::text,
  true
);

-- Catalog and least-privilege RPC boundary.
select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_get_maintenance_backlog_summary()'
  ) is not null
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.pronamespace =
      'public'::pg_catalog.regnamespace
      and function_definition.proname =
        'my_diary_get_maintenance_backlog_summary'
  ) = 1,
  'the maintenance summary has one exact zero-argument RPC and no overload'
);

select ok(
  (
    select function_definition.pronargs = 0
      and function_definition.pronargdefaults = 0
      and function_definition.proargtypes = ''::pg_catalog.oidvector
      and function_definition.prorettype = 'record'::pg_catalog.regtype
      and function_definition.proallargtypes = array[
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype,
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype,
        'bigint'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype
      ]::oid[]
      and function_definition.proargmodes =
        array['t', 't', 't', 't', 't', 't']::"char"[]
      and function_definition.proargnames = array[
        'due_confirmed_cleanup_candidate_count',
        'oldest_confirmed_cleanup_due_at',
        'due_unconfirmed_orphan_count',
        'oldest_unconfirmed_orphan_due_at',
        'due_report_evidence_count',
        'oldest_report_evidence_due_at'
      ]::text[]
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
  ),
  'the RPC returns only six fixed count and oldest-due output columns'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    cross join lateral pg_catalog.unnest(function_definition.proargnames)
      as output_column(name)
    where function_definition.oid =
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
      and output_column.name ~
        '(path|bucket|report_id|evidence_id|source_image_id|entry_id|diary_id|user_id|reason|details|snapshot)'
  ),
  0::bigint,
  'the output contract exposes no path, identifier, report detail, or snapshot field'
);

select ok(
  (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig =
        array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
  ),
  'the RPC is a postgres-owned STABLE SECURITY DEFINER with empty search_path'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_get_maintenance_backlog_summary()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_get_maintenance_backlog_summary()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_get_maintenance_backlog_summary()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_get_maintenance_backlog_summary()',
    'EXECUTE'
  ),
  'only authenticated receives the required explicit EXECUTE grant'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as privilege
    where function_definition.oid =
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'PUBLIC cannot execute the maintenance summary RPC'
);

select ok(
  pg_catalog.lower(
    pg_catalog.pg_get_functiondef(
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
    )
  ) like '%my_diary_private.my_diary_is_active_admin()%'
  and pg_catalog.lower(
    pg_catalog.pg_get_functiondef(
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
    )
  ) not similar to '%(insert|update|delete|truncate)[[:space:]]+%'
  and pg_catalog.lower(
    pg_catalog.pg_get_functiondef(
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
    )
  ) not like '%for update%'
  and pg_catalog.lower(
    pg_catalog.pg_get_functiondef(
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
    )
  ) not like '%limit 100%'
  and pg_catalog.lower(
    pg_catalog.pg_get_functiondef(
      'public.my_diary_get_maintenance_backlog_summary()'::pg_catalog.regprocedure
    )
  ) not like '% limit %',
  'the active-admin summary is read-only, lock-free, and uncapped'
);

-- Active admin, ordinary user, non-active admins, and a second unrelated admin.
insert into auth.users (id, email)
values
  ('a3500000-0000-4000-8000-000000000001', 'm1a-owner@example.test'),
  ('b3500000-0000-4000-8000-000000000002', 'm1a-peer@example.test'),
  ('c3500000-0000-4000-8000-000000000003', 'm1a-admin@example.test'),
  ('d3500000-0000-4000-8000-000000000004', 'm1a-suspended@example.test'),
  ('e3500000-0000-4000-8000-000000000005', 'm1a-deactivated@example.test'),
  ('f3500000-0000-4000-8000-000000000006', 'm1a-user@example.test'),
  ('93500000-0000-4000-8000-000000000007', 'm1a-other-admin@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'c3500000-0000-4000-8000-000000000003',
  'd3500000-0000-4000-8000-000000000004',
  'e3500000-0000-4000-8000-000000000005',
  '93500000-0000-4000-8000-000000000007'
);
update public.accounts set status = 'suspended'
where user_id = 'd3500000-0000-4000-8000-000000000004';
update public.accounts set status = 'deactivated'
where user_id = 'e3500000-0000-4000-8000-000000000005';

select set_config(
  'request.jwt.claim.sub',
  'c3500000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select results_eq(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  $$values (
    0::bigint, null::timestamptz,
    0::bigint, null::timestamptz,
    0::bigint, null::timestamptz
  )$$,
  'an active admin receives one empty summary row with zero counts and NULL oldest values'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3500000-0000-4000-8000-000000000006',
  true
);
set local role authenticated;
select throws_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  '42501', 'Maintenance backlog is unavailable.',
  'an ordinary authenticated user cannot read the maintenance summary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd3500000-0000-4000-8000-000000000004',
  true
);
set local role authenticated;
select throws_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  '42501', 'Maintenance backlog is unavailable.',
  'a suspended admin cannot read the maintenance summary'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e3500000-0000-4000-8000-000000000005',
  true
);
set local role authenticated;
select throws_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  '42501', 'Maintenance backlog is unavailable.',
  'a deactivated admin cannot read the maintenance summary'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select throws_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  '42501', 'Maintenance backlog is unavailable.',
  'an authenticated request without a principal fails closed'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select throws_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  '42501',
  'permission denied for function my_diary_get_maintenance_backlog_summary',
  'an unauthenticated Data API caller has no EXECUTE privilege'
);

reset role;

-- Minimal live Exchange metadata for protected confirmed and orphan paths.
insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values ('d3500000-0000-4000-8000-000000000001', 'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('13500000-0000-4000-8000-000000000001',
   'd3500000-0000-4000-8000-000000000001', 1,
   'a3500000-0000-4000-8000-000000000001'),
  ('23500000-0000-4000-8000-000000000002',
   'd3500000-0000-4000-8000-000000000001', 2,
   'b3500000-0000-4000-8000-000000000002');

insert into public.exchange_entries
  (id, diary_id, author_participant_id, title, body)
values (
  'e3500000-0000-4000-8000-000000000001',
  'd3500000-0000-4000-8000-000000000001',
  '13500000-0000-4000-8000-000000000001',
  'summary fixture', 'summary fixture body'
);

insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values
  ('f3500000-0000-4000-8000-000000000004',
   'e3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000004',
   0),
  ('f3500000-0000-4000-8000-000000000106',
   'e3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000106',
   1);

-- Reports cover open states, both terminal states, all 30-day boundaries,
-- already-purged data, and both current-admin COI directions.
insert into public.reports (
  id, reporter_user_id, target_type, target_id, reported_user_id,
  reason, status, resolved_at, resolved_by, evidence_delete_after
)
values
  ('73500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000101',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'pending', null, null, null),
  ('73500000-0000-4000-8000-000000000002',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000102',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'reviewing', null, null, null),
  ('73500000-0000-4000-8000-000000000003',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000103',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'resolved',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '30 days' + interval '1 minute',
   'c3500000-0000-4000-8000-000000000003',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     + interval '1 minute'),
  ('73500000-0000-4000-8000-000000000004',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000104',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'resolved',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '30 days',
   'c3500000-0000-4000-8000-000000000003',
   current_setting('my_diary.maintenance_base_time')::timestamptz),
  ('73500000-0000-4000-8000-000000000005',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000105',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'dismissed',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '30 days' - interval '2 hours',
   'c3500000-0000-4000-8000-000000000003',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 hours'),
  ('73500000-0000-4000-8000-000000000006',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000106',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'resolved',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '31 days',
   'c3500000-0000-4000-8000-000000000003',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '1 day'),
  ('73500000-0000-4000-8000-000000000007',
   'c3500000-0000-4000-8000-000000000003', 'user',
   'b3500000-0000-4000-8000-000000000107',
   'b3500000-0000-4000-8000-000000000002', 'spam',
   'resolved',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '30 days' - interval '3 hours',
   '93500000-0000-4000-8000-000000000007',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '3 hours'),
  ('73500000-0000-4000-8000-000000000008',
   'a3500000-0000-4000-8000-000000000001', 'user',
   'b3500000-0000-4000-8000-000000000108',
   'c3500000-0000-4000-8000-000000000003', 'spam',
   'dismissed',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '30 days' - interval '4 hours',
   '93500000-0000-4000-8000-000000000007',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '4 hours');

insert into public.report_exchange_entry_snapshots (
  report_id, source_entry_id, source_diary_id,
  source_author_participant_id, entry_created_at, entry_updated_at,
  title, body, tag_names
)
select
  report.id, null,
  'd3500000-0000-4000-8000-000000000001', null,
  current_setting('my_diary.maintenance_base_time')::timestamptz,
  current_setting('my_diary.maintenance_base_time')::timestamptz,
  'retained evidence', 'retained evidence body', array[]::text[]
from public.reports as report
where report.id in (
  '73500000-0000-4000-8000-000000000001',
  '73500000-0000-4000-8000-000000000002',
  '73500000-0000-4000-8000-000000000003',
  '73500000-0000-4000-8000-000000000004',
  '73500000-0000-4000-8000-000000000005',
  '73500000-0000-4000-8000-000000000007',
  '73500000-0000-4000-8000-000000000008'
);

insert into public.report_snapshot_images (
  report_id, source_image_id, storage_path,
  sort_order, mime_type, size_bytes
)
values
  ('73500000-0000-4000-8000-000000000001', null,
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000005/f3510000-0000-4000-8000-000000000005',
   0, 'image/png', 68),
  ('73500000-0000-4000-8000-000000000001', null,
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000008/f3520000-0000-4000-8000-000000000008',
   1, 'image/png', 68);

-- Confirmed candidates: just before, exact, after, live-protected,
-- evidence-protected, and same-path/wrong-object collision.
insert into my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id, storage_path, image_id, entry_id, diary_id,
  owner_user_id, removed_at, delete_after
)
values
  ('83500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000001/f3510000-0000-4000-8000-000000000001',
   'f3510000-0000-4000-8000-000000000001',
   'e3510000-0000-4000-8000-000000000001',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days' + interval '1 minute',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     + interval '1 minute'),
  ('83500000-0000-4000-8000-000000000002',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000002/f3510000-0000-4000-8000-000000000002',
   'f3510000-0000-4000-8000-000000000002',
   'e3510000-0000-4000-8000-000000000002',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days',
   current_setting('my_diary.maintenance_base_time')::timestamptz),
  ('83500000-0000-4000-8000-000000000003',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000003/f3510000-0000-4000-8000-000000000003',
   'f3510000-0000-4000-8000-000000000003',
   'e3510000-0000-4000-8000-000000000003',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days' - interval '1 hour',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '1 hour'),
  ('83500000-0000-4000-8000-000000000004',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000004',
   'f3500000-0000-4000-8000-000000000004',
   'e3500000-0000-4000-8000-000000000001',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days' - interval '2 hours',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 hours'),
  ('83500000-0000-4000-8000-000000000005',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000005/f3510000-0000-4000-8000-000000000005',
   'f3510000-0000-4000-8000-000000000005',
   'e3510000-0000-4000-8000-000000000005',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days' - interval '3 hours',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '3 hours'),
  ('83500000-0000-4000-8000-000000000006',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000006/f3510000-0000-4000-8000-000000000006',
   'f3510000-0000-4000-8000-000000000006',
   'e3510000-0000-4000-8000-000000000006',
   'd3500000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '7 days' - interval '4 hours',
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '4 hours');

insert into storage.objects
  (id, bucket_id, name, owner_id, metadata, created_at)
values
  ('83500000-0000-4000-8000-000000000003', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000003/f3510000-0000-4000-8000-000000000003',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '10 days'),
  ('83500000-0000-4000-8000-000000000106', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000006/f3510000-0000-4000-8000-000000000006',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '10 days');

-- Orphans: just before, exact, after, malformed, owner mismatch, live,
-- candidate-protected, evidence-protected, and wrong bucket.
insert into storage.objects
  (id, bucket_id, name, owner_id, metadata, created_at)
values
  ('93520000-0000-4000-8000-000000000001', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000001/f3520000-0000-4000-8000-000000000001',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '24 hours' + interval '1 minute'),
  ('93520000-0000-4000-8000-000000000002', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000002/f3520000-0000-4000-8000-000000000002',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '24 hours'),
  ('93520000-0000-4000-8000-000000000003', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000003/f3520000-0000-4000-8000-000000000003',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '25 hours'),
  ('93520000-0000-4000-8000-000000000004', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/not-a-uuid/e3520000-0000-4000-8000-000000000004/f3520000-0000-4000-8000-000000000004',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days'),
  ('93520000-0000-4000-8000-000000000005', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000005/f3520000-0000-4000-8000-000000000005',
   'b3500000-0000-4000-8000-000000000002', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days'),
  ('93520000-0000-4000-8000-000000000006', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000106',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days'),
  ('93520000-0000-4000-8000-000000000007', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000007/f3520000-0000-4000-8000-000000000007',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days'),
  ('93520000-0000-4000-8000-000000000008', 'exchange-entry-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000008/f3520000-0000-4000-8000-000000000008',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days'),
  ('93520000-0000-4000-8000-000000000009', 'post-images',
   'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000009/f3520000-0000-4000-8000-000000000009',
   'a3500000-0000-4000-8000-000000000001', '{}'::jsonb,
   current_setting('my_diary.maintenance_base_time')::timestamptz
     - interval '2 days');

insert into my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id, storage_path, image_id, entry_id, diary_id,
  owner_user_id, removed_at, delete_after
)
values (
  '93520000-0000-4000-8000-000000000007',
  'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000007/f3520000-0000-4000-8000-000000000007',
  'f3520000-0000-4000-8000-000000000007',
  'e3520000-0000-4000-8000-000000000007',
  'd3500000-0000-4000-8000-000000000001',
  'a3500000-0000-4000-8000-000000000001',
  current_setting('my_diary.maintenance_base_time')::timestamptz,
  current_setting('my_diary.maintenance_base_time')::timestamptz
    + interval '7 days'
);

select set_config(
  'request.jwt.claim.sub',
  'c3500000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select results_eq(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  $$values (
    2::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '1 hour',
    2::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '1 hour',
    2::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '2 hours'
  )$$,
  '7d, 24h, and 30d boundaries include exact/after but exclude just-before rows'
);

select is(
  (
    select pg_catalog.cardinality(
      public.my_diary_list_due_exchange_image_cleanup_candidates(100)
    )::bigint
  ),
  (
    select due_confirmed_cleanup_candidate_count
    from public.my_diary_get_maintenance_backlog_summary()
  ),
  'confirmed summary count matches the existing uncapped eligibility set while below 100'
);

select ok(
  public.my_diary_list_due_exchange_image_cleanup_candidates(100) @> array[
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000002/f3510000-0000-4000-8000-000000000002'
  ]::text[]
  and not public.my_diary_list_due_exchange_image_cleanup_candidates(100) && array[
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000001/f3510000-0000-4000-8000-000000000001',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000004',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000005/f3510000-0000-4000-8000-000000000005',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3510000-0000-4000-8000-000000000006/f3510000-0000-4000-8000-000000000006'
  ]::text[],
  'confirmed listing and summary include missing objects and exclude early/live/evidence/collision rows'
);

select is(
  (
    select pg_catalog.cardinality(
      public.my_diary_list_due_unconfirmed_exchange_image_orphans(100)
    )::bigint
  ),
  (
    select due_unconfirmed_orphan_count
    from public.my_diary_get_maintenance_backlog_summary()
  ),
  'orphan summary count matches the existing uncapped eligibility set while below 100'
);

select ok(
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(100) @> array[
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000002/f3520000-0000-4000-8000-000000000002',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000003/f3520000-0000-4000-8000-000000000003'
  ]::text[]
  and not public.my_diary_list_due_unconfirmed_exchange_image_orphans(100) && array[
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000001/f3520000-0000-4000-8000-000000000001',
    'a3500000-0000-4000-8000-000000000001/not-a-uuid/e3520000-0000-4000-8000-000000000004/f3520000-0000-4000-8000-000000000004',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000005/f3520000-0000-4000-8000-000000000005',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3500000-0000-4000-8000-000000000001/f3500000-0000-4000-8000-000000000106',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000007/f3520000-0000-4000-8000-000000000007',
    'a3500000-0000-4000-8000-000000000001/d3500000-0000-4000-8000-000000000001/e3520000-0000-4000-8000-000000000008/f3520000-0000-4000-8000-000000000008'
  ]::text[],
  'orphan listing and summary exclude early/malformed/owner/live/candidate/evidence rows'
);

select is(
  (
    select due_report_evidence_count
    from public.my_diary_get_maintenance_backlog_summary()
  ),
  2::bigint,
  'only due resolved/dismissed evidence remains for the current non-COI admin'
);

select ok(
  exists (
    select 1
    from public.reports as report
    where report.id = '73500000-0000-4000-8000-000000000006'
      and report.status = 'resolved'
      and report.evidence_delete_after <=
        current_setting('my_diary.maintenance_base_time')::timestamptz
  )
  and not exists (
    select 1
    from public.report_exchange_entry_snapshots as snapshot
    where snapshot.report_id = '73500000-0000-4000-8000-000000000006'
  )
  and not exists (
    select 1
    from public.report_snapshot_images as snapshot_image
    where snapshot_image.report_id = '73500000-0000-4000-8000-000000000006'
  ),
  'an already-purged terminal report is present but contributes no backlog'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '93500000-0000-4000-8000-000000000007',
  true
);
set local role authenticated;
select results_eq(
  $$select due_report_evidence_count, oldest_report_evidence_due_at
    from public.my_diary_get_maintenance_backlog_summary()$$,
  $$values (
    4::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '4 hours'
  )$$,
  'an unrelated active admin sees both reports excluded from the first admin by COI'
);

-- Add 101 eligible rows to prove that summary counts are exact, not listing-capped.
reset role;
insert into my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id, storage_path, image_id, entry_id, diary_id,
  owner_user_id, removed_at, delete_after
)
select
  ('83590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'))::uuid,
  'a3500000-0000-4000-8000-000000000001/'
    || 'd3500000-0000-4000-8000-000000000001/'
    || 'e3590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0') || '/'
    || 'f3590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'),
  ('f3590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'))::uuid,
  ('e3590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'))::uuid,
  'd3500000-0000-4000-8000-000000000001',
  'a3500000-0000-4000-8000-000000000001',
  current_setting('my_diary.maintenance_base_time')::timestamptz
    - interval '7 days' - interval '5 hours',
  current_setting('my_diary.maintenance_base_time')::timestamptz
    - interval '5 hours'
from pg_catalog.generate_series(1, 101) as series;

insert into storage.objects
  (id, bucket_id, name, owner_id, metadata, created_at)
select
  ('93590000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'))::uuid,
  'exchange-entry-images',
  'a3500000-0000-4000-8000-000000000001/'
    || 'd3500000-0000-4000-8000-000000000001/'
    || 'e3580000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0') || '/'
    || 'f3580000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0'),
  'a3500000-0000-4000-8000-000000000001',
  '{}'::jsonb,
  current_setting('my_diary.maintenance_base_time')::timestamptz
    - interval '30 hours'
from pg_catalog.generate_series(1, 101) as series;

select set_config(
  'request.jwt.claim.sub',
  'c3500000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select results_eq(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  $$values (
    103::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '5 hours',
    103::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '6 hours',
    2::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '2 hours'
  )$$,
  'confirmed and orphan summaries return exact counts and oldest due values above the 100-row listing cap'
);

select ok(
  pg_catalog.cardinality(
    public.my_diary_list_due_exchange_image_cleanup_candidates(100)
  ) = 100
  and pg_catalog.cardinality(
    public.my_diary_list_due_unconfirmed_exchange_image_orphans(100)
  ) = 100
  and (
    select due_confirmed_cleanup_candidate_count = 103
      and due_unconfirmed_orphan_count = 103
    from public.my_diary_get_maintenance_backlog_summary()
  ),
  'existing listings cap at 100 while the summary remains exact at 103'
);

reset role;
select set_config(
  'my_diary.maintenance_state_before',
  (
    select pg_catalog.jsonb_build_object(
      'storage_objects',
        (select pg_catalog.count(*) from storage.objects),
      'cleanup_candidates',
        (select pg_catalog.count(*)
         from my_diary_private.exchange_entry_image_cleanup_candidates),
      'report_snapshots',
        (select pg_catalog.count(*)
         from public.report_exchange_entry_snapshots),
      'report_snapshot_images',
        (select pg_catalog.count(*) from public.report_snapshot_images),
      'reports',
        (select pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'id', report.id,
             'status', report.status,
             'resolved_at', report.resolved_at,
             'evidence_delete_after', report.evidence_delete_after
           ) order by report.id
         ) from public.reports as report)
    )::text
  ),
  true
);

set local role authenticated;
select lives_ok(
  $$select * from public.my_diary_get_maintenance_backlog_summary()$$,
  'the populated read-only summary executes successfully'
);

reset role;
select is(
  pg_catalog.jsonb_build_object(
    'storage_objects',
      (select pg_catalog.count(*) from storage.objects),
    'cleanup_candidates',
      (select pg_catalog.count(*)
       from my_diary_private.exchange_entry_image_cleanup_candidates),
    'report_snapshots',
      (select pg_catalog.count(*)
       from public.report_exchange_entry_snapshots),
    'report_snapshot_images',
      (select pg_catalog.count(*) from public.report_snapshot_images),
    'reports',
      (select pg_catalog.jsonb_agg(
         pg_catalog.jsonb_build_object(
           'id', report.id,
           'status', report.status,
           'resolved_at', report.resolved_at,
           'evidence_delete_after', report.evidence_delete_after
         ) order by report.id
       ) from public.reports as report)
  ),
  current_setting('my_diary.maintenance_state_before')::jsonb,
  'summary execution changes no Storage, candidate, snapshot, report status, or retention state'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
      'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_image_cleanup_candidates_retention_check'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%removed_at + ''7 days''::interval%'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reports'::pg_catalog.regclass
      and conname = 'my_diary_reports_evidence_retention_shape_check'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%resolved_at + ''30 days''::interval%'
  ),
  'existing seven-day and thirty-day retention constraints remain unchanged'
);

select set_config(
  'request.jwt.claim.sub',
  'c3500000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select is(
  public.my_diary_purge_expired_report_evidence(
    '73500000-0000-4000-8000-000000000004'
  ),
  true,
  'the existing purge removes evidence at the exact thirty-day boundary'
);

select results_eq(
  $$select due_report_evidence_count, oldest_report_evidence_due_at
    from public.my_diary_get_maintenance_backlog_summary()$$,
  $$values (
    1::bigint,
    current_setting('my_diary.maintenance_base_time')::timestamptz
      - interval '2 hours'
  )$$,
  'a purged report row no longer remains in the evidence backlog'
);

reset role;
select ok(
  exists (
    select 1
    from public.reports
    where id = '73500000-0000-4000-8000-000000000004'
      and status = 'resolved'
      and evidence_delete_after =
        current_setting('my_diary.maintenance_base_time')::timestamptz
  )
  and not exists (
    select 1
    from public.report_exchange_entry_snapshots
    where report_id = '73500000-0000-4000-8000-000000000004'
  )
  and not exists (
    select 1
    from public.report_snapshot_images
    where report_id = '73500000-0000-4000-8000-000000000004'
  ),
  'purge retains the terminal report/deadline while summary tracks only remaining evidence'
);

select * from finish();

rollback;
