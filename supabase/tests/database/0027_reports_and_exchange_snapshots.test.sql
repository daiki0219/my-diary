begin;

create extension if not exists pgtap with schema extensions;

select plan(96);

-- Exact schema, ownership, RLS, ACL, indexes, triggers, and RPC catalog.
select columns_are(
  'public', 'reports',
  array[
    'id', 'reporter_user_id', 'target_type', 'target_id',
    'reported_user_id', 'reason', 'details', 'status', 'created_at',
    'updated_at', 'resolved_at', 'resolved_by', 'evidence_delete_after'
  ],
  'reports has the exact common moderation columns'
);

select columns_are(
  'public', 'report_exchange_entry_snapshots',
  array[
    'report_id', 'source_entry_id', 'source_diary_id',
    'source_author_participant_id', 'entry_created_at',
    'entry_updated_at', 'captured_at', 'title', 'body', 'mood',
    'location_name', 'tag_names'
  ],
  'exchange report snapshots have the exact evidence columns'
);

select columns_are(
  'public', 'report_snapshot_images',
  array[
    'id', 'report_id', 'source_image_id', 'storage_path', 'sort_order',
    'mime_type', 'size_bytes', 'created_at'
  ],
  'report snapshot images have the exact reference-hold columns'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.reports'::pg_catalog.regclass,
      'public.report_exchange_entry_snapshots'::pg_catalog.regclass,
      'public.report_snapshot_images'::pg_catalog.regclass
    )
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ),
  3::bigint,
  'all report tables are postgres-owned with explicit non-forced RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'reports', 'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  3::bigint,
  'the three report tables have active-admin SELECT policies only'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.reports', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.reports', 'INSERT, UPDATE, DELETE'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.report_exchange_entry_snapshots', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.report_exchange_entry_snapshots',
    'INSERT, UPDATE, DELETE'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.report_snapshot_images', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.report_snapshot_images',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.reports', 'SELECT'
  ),
  'authenticated receives report SELECT only and anon receives no access'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_reports_open_reporter_target_key'
      and indexdef like '%UNIQUE%reporter_user_id, target_type, target_id%'
      and indexdef like '%status = ANY%pending%reviewing%'
  ),
  'open-report uniqueness is a partial reporter/type/target index'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_reports_status_created_id_idx'
      and indexdef like '%status, created_at DESC, id DESC%'
  ),
  'moderation status pagination has a stable index'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgrelid = 'public.reports'::pg_catalog.regclass
      and not tgisinternal
      and tgname in (
        'my_diary_reports_reject_status_transition',
        'my_diary_reports_set_updated_at'
      )
  ),
  2::bigint,
  'reports has transition and updated_at triggers'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.reports'::pg_catalog.regclass
      and conname = 'my_diary_reports_reporter_user_id_fkey'
      and confdeltype = 'n'
  )
  and exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid =
      'public.report_exchange_entry_snapshots'::pg_catalog.regclass
      and conname =
        'my_diary_report_exchange_entry_snapshots_source_entry_id_fkey'
      and confdeltype = 'n'
  )
  and exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.report_snapshot_images'::pg_catalog.regclass
      and conname =
        'my_diary_report_snapshot_images_source_image_id_fkey'
      and confdeltype = 'n'
  ),
  'reporter and source references use ON DELETE SET NULL evidence semantics'
);

select ok(
  (
    select prosecdef and provolatile = 's'
      and proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(proowner) = 'postgres'
    from pg_catalog.pg_proc
    where oid =
      'my_diary_private.my_diary_is_active_admin()'::pg_catalog.regprocedure
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_is_active_admin()', 'EXECUTE'
  ),
  'active-admin helper is hardened and not directly application executable'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname in (
        'my_diary_create_exchange_entry_report',
        'my_diary_create_user_report',
        'my_diary_update_report_status'
      )
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
  ),
  3::bigint,
  'the three exact public report RPCs are hardened without defaults'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_exchange_entry_report(uuid,text,text)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_report_status(uuid,text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_exchange_entry_report(uuid,text,text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'only authenticated receives exact report RPC EXECUTE'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
  ) like '%exchange_entry_image_cleanup_candidates%'
  and pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
  ) not like '%report_snapshot_images%',
  'exchange user cleanup is candidate-based and evidence-agnostic'
);

select ok(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ) = 11
  and pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_post_image_path_is_referenced(text)'
  ) is not null
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ) = 2,
  'exchange Storage policies, post images, and notifications have expected boundaries'
);

-- Users, moderation roles, diaries, entries, tags, and Storage fixtures.
insert into auth.users (id, email)
values
  ('a2700000-0000-4000-8000-000000000001', 'e2d-a@example.test'),
  ('b2700000-0000-4000-8000-000000000002', 'e2d-b@example.test'),
  ('c2700000-0000-4000-8000-000000000003', 'e2d-c@example.test'),
  ('d2700000-0000-4000-8000-000000000004', 'e2d-admin@example.test'),
  ('e2700000-0000-4000-8000-000000000005', 'e2d-sadmin@example.test'),
  ('f2700000-0000-4000-8000-000000000006', 'e2d-dadmin@example.test'),
  ('a2710000-0000-4000-8000-000000000007', 'e2d-target-a@example.test'),
  ('b2710000-0000-4000-8000-000000000008', 'e2d-target-b@example.test'),
  ('c2710000-0000-4000-8000-000000000009', 'e2d-target-c@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'd2700000-0000-4000-8000-000000000004',
  'e2700000-0000-4000-8000-000000000005',
  'f2700000-0000-4000-8000-000000000006'
);
update public.accounts set status = 'suspended'
where user_id in (
  'e2700000-0000-4000-8000-000000000005',
  'b2710000-0000-4000-8000-000000000008'
);
update public.accounts set status = 'deactivated'
where user_id in (
  'f2700000-0000-4000-8000-000000000006',
  'c2710000-0000-4000-8000-000000000009'
);

insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values
  ('d2700000-0000-4000-8000-000000000001', 'active', 1, null, null),
  ('d2700000-0000-4000-8000-000000000002', 'archived', 1,
   now(), 'user_archived'),
  ('d2700000-0000-4000-8000-000000000003', 'active', 1, null, null),
  ('d2700000-0000-4000-8000-000000000004', 'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('12700000-0000-4000-8000-000000000001',
   'd2700000-0000-4000-8000-000000000001', 1,
   'a2700000-0000-4000-8000-000000000001'),
  ('12700000-0000-4000-8000-000000000002',
   'd2700000-0000-4000-8000-000000000001', 2,
   'b2700000-0000-4000-8000-000000000002'),
  ('22700000-0000-4000-8000-000000000001',
   'd2700000-0000-4000-8000-000000000002', 1,
   'a2700000-0000-4000-8000-000000000001'),
  ('22700000-0000-4000-8000-000000000002',
   'd2700000-0000-4000-8000-000000000002', 2,
   'b2700000-0000-4000-8000-000000000002'),
  ('32700000-0000-4000-8000-000000000001',
   'd2700000-0000-4000-8000-000000000003', 1,
   'b2700000-0000-4000-8000-000000000002'),
  ('32700000-0000-4000-8000-000000000002',
   'd2700000-0000-4000-8000-000000000003', 2,
   'c2700000-0000-4000-8000-000000000003'),
  ('42700000-0000-4000-8000-000000000001',
   'd2700000-0000-4000-8000-000000000004', 1,
   'a2700000-0000-4000-8000-000000000001'),
  ('42700000-0000-4000-8000-000000000002',
   'd2700000-0000-4000-8000-000000000004', 2,
   'b2700000-0000-4000-8000-000000000002');

insert into public.exchange_entries (
  id, diary_id, author_participant_id,
  title, body, mood, location_name, created_at, updated_at
)
values
  ('e2700000-0000-4000-8000-000000000001',
   'd2700000-0000-4000-8000-000000000001',
   '12700000-0000-4000-8000-000000000002',
   'old title', 'old body', 'calm', 'Tokyo',
   '2026-08-01 01:00:00+00', '2026-08-01 02:00:00+00'),
  ('e2700000-0000-4000-8000-000000000002',
   'd2700000-0000-4000-8000-000000000001',
   '12700000-0000-4000-8000-000000000001',
   null, 'reporter body', null, null, now(), now()),
  ('e2700000-0000-4000-8000-000000000003',
   'd2700000-0000-4000-8000-000000000002',
   '22700000-0000-4000-8000-000000000002',
   null, 'archived body', null, null, now(), now()),
  ('e2700000-0000-4000-8000-000000000004',
   'd2700000-0000-4000-8000-000000000003',
   '32700000-0000-4000-8000-000000000001',
   null, 'invisible body', null, null, now(), now()),
  ('e2700000-0000-4000-8000-000000000005',
   'd2700000-0000-4000-8000-000000000004',
   '42700000-0000-4000-8000-000000000002',
   null, 'to delete', null, null, now(), now());

update public.exchange_entries
set body = null, deleted_at = now(), redaction_reason = 'user_deleted'
where id = 'e2700000-0000-4000-8000-000000000005';

insert into public.tags (id, name, normalized_name)
values
  ('72700000-0000-4000-8000-000000000001', 'alpha', 'alpha'),
  ('72700000-0000-4000-8000-000000000002', 'beta', 'beta');
insert into public.exchange_entry_tags (entry_id, tag_id)
values
  ('e2700000-0000-4000-8000-000000000001',
   '72700000-0000-4000-8000-000000000002'),
  ('e2700000-0000-4000-8000-000000000001',
   '72700000-0000-4000-8000-000000000001');

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2710000-0000-4000-8000-000000000001',
  'exchange-entry-images',
  'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000001/f2700000-0000-4000-8000-000000000001',
  'b2700000-0000-4000-8000-000000000002',
  '{"mimetype":"image/png","size":68}'::jsonb
);
insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f2700000-0000-4000-8000-000000000001',
  'e2700000-0000-4000-8000-000000000001',
  'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000001/f2700000-0000-4000-8000-000000000001',
  0
);

insert into public.exchange_entries (
  id, diary_id, author_participant_id, body
)
values (
  'e2700000-0000-4000-8000-000000000020',
  'd2700000-0000-4000-8000-000000000001',
  '12700000-0000-4000-8000-000000000002',
  'ten image body'
);
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
select
  ('f2730000-0000-4000-8000-' ||
   pg_catalog.lpad(g::text, 12, '0'))::uuid,
  'exchange-entry-images',
  'b2700000-0000-4000-8000-000000000002/' ||
  'd2700000-0000-4000-8000-000000000001/' ||
  'e2700000-0000-4000-8000-000000000020/' ||
  ('f2720000-0000-4000-8000-' ||
   pg_catalog.lpad(g::text, 12, '0')),
  'b2700000-0000-4000-8000-000000000002',
  '{"mimetype":"image/webp","size":6291456}'::jsonb
from pg_catalog.generate_series(1, 10) as fixture(g);
insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
select
  ('f2720000-0000-4000-8000-' ||
   pg_catalog.lpad(g::text, 12, '0'))::uuid,
  'e2700000-0000-4000-8000-000000000020',
  'b2700000-0000-4000-8000-000000000002/' ||
  'd2700000-0000-4000-8000-000000000001/' ||
  'e2700000-0000-4000-8000-000000000020/' ||
  ('f2720000-0000-4000-8000-' ||
   pg_catalog.lpad(g::text, 12, '0')),
  (g - 1)::smallint
from pg_catalog.generate_series(1, 10) as fixture(g);

-- Entry report validation, authorization, atomic snapshot, and duplicate-open control.
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config(
  'my_diary.e2d_main_report',
  public.my_diary_create_exchange_entry_report(
    'e2700000-0000-4000-8000-000000000001',
    'harassment', repeat('界', 2000)
  )::text,
  true
);

select ok(
  current_setting('my_diary.e2d_main_report')::uuid is not null,
  'a participant reports the other participant entry'
);

select set_config(
  'my_diary.e2d_ten_image_report',
  public.my_diary_create_exchange_entry_report(
    'e2700000-0000-4000-8000-000000000020', 'spam', null
  )::text,
  true
);
select results_eq(
  $$select pg_catalog.count(*), pg_catalog.min(sort_order),
           pg_catalog.max(sort_order)
    from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2d_ten_image_report')::uuid$$,
  $$values (0::bigint, null::smallint, null::smallint)$$,
  'the reporter cannot read the ten-image snapshot directly'
);

select is(
  (
    select pg_catalog.char_length(details)
    from public.reports
    where id = current_setting('my_diary.e2d_main_report')::uuid
  ),
  null::integer,
  'the reporter cannot SELECT even the report it just created'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001',
      'harassment', repeat('界', 2001)
    )$$,
  '22023', 'Invalid report input.',
  'details rejects 2001 Unicode codepoints'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001',
      'invalid', null
    )$$,
  '22023', 'Invalid report input.',
  'an invalid report reason is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'other', null
    )$$,
  '22023', 'Invalid report input.',
  'other requires details'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'other', '   '
    )$$,
  '22023', 'Invalid report input.',
  'other rejects whitespace-only details'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'spam', null
    )$$,
  '23505', 'Report could not be created.',
  'a second pending report for the same entry is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000002', 'spam', null
    )$$,
  '42501', 'Report could not be created.',
  'a reporter cannot report their own entry'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000005', 'spam', null
    )$$,
  '42501', 'Report could not be created.',
  'a deleted entry is rejected generically'
);

select set_config(
  'my_diary.e2d_archived_report',
  public.my_diary_create_exchange_entry_report(
    'e2700000-0000-4000-8000-000000000003', 'spam', null
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2d_archived_report')::uuid is not null,
  'a currently visible archived entry can be reported'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'b2700000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'spam', null
    )$$,
  '42501', 'Report could not be created.',
  'a suspended participant boundary fails closed'
);
reset role;
update public.accounts set status = 'active'
where user_id = 'b2700000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'c2700000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'spam', null
    )$$,
  '42501', 'Report could not be created.',
  'a third party receives the generic error for an existing entry'
);
select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000099', 'spam', null
    )$$,
  '42501', 'Report could not be created.',
  'a third party receives the same generic error for a missing entry'
);

-- User reports, all six reasons, target lifecycle, and optional related entry.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;

select set_config(
  'my_diary.e2d_user_related_report',
  public.my_diary_create_user_report(
    'b2700000-0000-4000-8000-000000000002',
    'spam', '   trimmed details   ',
    'e2700000-0000-4000-8000-000000000001'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2d_user_related_report')::uuid is not null,
  'a user report can attach one visible target-authored entry'
);

select set_config(
  'my_diary.e2d_user_null_report',
  public.my_diary_create_user_report(
    'c2700000-0000-4000-8000-000000000003',
    'personal_information', '   ', null
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2d_user_null_report')::uuid is not null,
  'a user report without a related entry succeeds and normalizes whitespace'
);

reset role;
select throws_ok(
  $$insert into public.report_exchange_entry_snapshots (
      report_id, source_diary_id, entry_created_at, entry_updated_at,
      body, tag_names
    ) values (
      current_setting('my_diary.e2d_user_null_report')::uuid,
      'd2700000-0000-4000-8000-000000000001', now(), now(),
      'invalid direct snapshot', array[['alpha','beta']]::text[][]
    )$$,
  '23514', null,
  'snapshot tag names reject multidimensional arrays at the DB boundary'
);
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_user_report(
      'd2700000-0000-4000-8000-000000000004',
      'sexual_or_inappropriate', null, null
    )$$,
  'sexual_or_inappropriate is accepted'
);
select lives_ok(
  $$select public.my_diary_create_user_report(
      'e2700000-0000-4000-8000-000000000005',
      'threat_or_danger', null, null
    )$$,
  'a suspended target and threat_or_danger are accepted'
);
select lives_ok(
  $$select public.my_diary_create_user_report(
      'f2700000-0000-4000-8000-000000000006',
      'other', '  explanation  ', null
    )$$,
  'a deactivated target and other with details are accepted'
);
select lives_ok(
  $$select public.my_diary_create_user_report(
      'a2710000-0000-4000-8000-000000000007',
      'harassment', null, null
    )$$,
  'an active target and harassment are accepted for user reports'
);

select throws_ok(
  $$select public.my_diary_create_user_report(
      'a2700000-0000-4000-8000-000000000001', 'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'self user report is rejected generically'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'a2710000-0000-4000-8000-000000000007', null, null, null
    )$$,
  '22023', 'Invalid report input.',
  'NULL user report reason is rejected explicitly'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'a2799999-0000-4000-8000-000000000099', 'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'missing user report target is rejected generically'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'c2700000-0000-4000-8000-000000000003', 'spam', null,
      'e2700000-0000-4000-8000-000000000001'
    )$$,
  '42501', 'Report could not be created.',
  'a related entry authored by another user is rejected generically'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'b2700000-0000-4000-8000-000000000002', 'spam', null,
      'e2700000-0000-4000-8000-000000000004'
    )$$,
  '42501', 'Report could not be created.',
  'an invisible related entry is rejected generically'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'b2700000-0000-4000-8000-000000000002', 'spam', null,
      'e2700000-0000-4000-8000-000000000005'
    )$$,
  '42501', 'Report could not be created.',
  'a deleted related entry is rejected generically'
);
select throws_ok(
  $$select public.my_diary_create_user_report(
      'b2700000-0000-4000-8000-000000000002', 'spam', null, null
    )$$,
  '23505', 'Report could not be created.',
  'user reports have the same open-duplicate protection'
);

-- Active-admin visibility only; no base exchange-data bypass.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2700000-0000-4000-8000-000000000004', true
);
set local role authenticated;

select results_eq(
  $$select title, body, mood, location_name, tag_names
    from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  $$values (
      'old title'::text, 'old body'::text, 'calm'::text, 'Tokyo'::text,
      array['alpha','beta']::text[]
    )$$,
  'entry report stores the exact text and canonical tag snapshot'
);

select results_eq(
  $$select source_entry_id, source_diary_id,
           source_author_participant_id,
           entry_created_at, entry_updated_at
    from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  $$values (
      'e2700000-0000-4000-8000-000000000001'::uuid,
      'd2700000-0000-4000-8000-000000000001'::uuid,
      '12700000-0000-4000-8000-000000000002'::uuid,
      '2026-08-01 01:00:00+00'::timestamptz,
      '2026-08-01 02:00:00+00'::timestamptz
    )$$,
  'snapshot stores source identity and original timestamps'
);

select results_eq(
  $$select storage_path, sort_order, mime_type, size_bytes
    from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2d_main_report')::uuid
    order by sort_order$$,
  $$values (
      'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000001/f2700000-0000-4000-8000-000000000001'::text,
      0::smallint, 'image/png'::text, 68::bigint
    )$$,
  'image evidence stores path order MIME and size'
);

select results_eq(
  $$select pg_catalog.count(*), pg_catalog.min(sort_order),
           pg_catalog.max(sort_order)
    from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2d_ten_image_report')::uuid$$,
  $$values (10::bigint, 0::smallint, 9::smallint)$$,
  'ten image evidence rows preserve the complete zero-based range'
);

select is(
  (
    select details
    from public.reports
    where id = current_setting('my_diary.e2d_user_related_report')::uuid
  ),
  'trimmed details'::text,
  'details are trimmed before storage'
);
select is(
  (
    select details
    from public.reports
    where id = current_setting('my_diary.e2d_user_null_report')::uuid
  ),
  null::text,
  'whitespace-only optional details are stored as NULL'
);
select is(
  (
    select pg_catalog.count(*)
    from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2d_user_null_report')::uuid
  ),
  0::bigint,
  'a user report without related entry creates no snapshot'
);
select is(
  (
    select pg_catalog.count(*)
    from public.report_exchange_entry_snapshots
    where report_id =
      current_setting('my_diary.e2d_user_related_report')::uuid
  ),
  1::bigint,
  'a user report with related entry creates exactly one snapshot'
);

select is(
  (select pg_catalog.count(*) from public.reports),
  9::bigint,
  'active admin can read reports'
);
select is(
  (select pg_catalog.count(*)
   from public.report_exchange_entry_snapshots),
  4::bigint,
  'active admin can read only captured entry snapshots'
);
select is(
  (select pg_catalog.count(*) from public.report_snapshot_images),
  12::bigint,
  'active admin can read captured image references'
);
select is(
  (
    select pg_catalog.count(*)
    from public.exchange_diaries
    where id in (
      'd2700000-0000-4000-8000-000000000001',
      'd2700000-0000-4000-8000-000000000002'
    )
  ),
  0::bigint,
  'nonparticipant admin cannot read exchange diaries'
);
select is(
  (select pg_catalog.count(*) from public.exchange_entries),
  0::bigint,
  'nonparticipant admin cannot read exchange entries'
);
select is(
  (select pg_catalog.count(*) from public.exchange_entry_tags),
  0::bigint,
  'nonparticipant admin cannot read exchange entry tags'
);
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images),
  0::bigint,
  'nonparticipant admin cannot read exchange entry images'
);

select throws_ok(
  $$update public.report_exchange_entry_snapshots
    set body = 'tampered'
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  '42501', null,
  'even active admin cannot mutate snapshot text directly'
);
select throws_ok(
  $$delete from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  '42501', null,
  'even active admin cannot delete snapshot images directly'
);

-- Status RPC and transition trigger.
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_main_report')::uuid, 'reviewing'
  ),
  true,
  'active admin changes pending to reviewing'
);
select results_eq(
  $$select status, resolved_at, resolved_by
    from public.reports
    where id = current_setting('my_diary.e2d_main_report')::uuid$$,
  $$values ('reviewing'::text, null::timestamptz, null::uuid)$$,
  'reviewing keeps resolution metadata NULL'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'spam', null
    )$$,
  '23505', 'Report could not be created.',
  'a second reviewing report for the same entry is rejected'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2700000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_main_report')::uuid, 'resolved'
  ),
  true,
  'active admin changes reviewing to resolved'
);
select ok(
  (
    select status = 'resolved'
      and resolved_at is not null
      and resolved_by = 'd2700000-0000-4000-8000-000000000004'::uuid
    from public.reports
    where id = current_setting('my_diary.e2d_main_report')::uuid
  ),
  'terminal status records DB time and admin identity'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_main_report')::uuid, 'dismissed'
    )$$,
  '42501', 'Report status could not be updated.',
  'a terminal report cannot change to another terminal status'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_archived_report')::uuid, 'pending'
    )$$,
  '42501', 'Report status could not be updated.',
  'status RPC never accepts pending as a destination'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      'd2799999-0000-4000-8000-000000000099', 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'status RPC rejects a nonexistent report generically'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_archived_report')::uuid, null
    )$$,
  '42501', 'Report status could not be updated.',
  'status RPC rejects NULL status explicitly'
);
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_archived_report')::uuid, 'resolved'
  ),
  true,
  'pending can transition directly to resolved'
);
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_user_related_report')::uuid, 'reviewing'
  ),
  true,
  'a user report can transition from pending to reviewing'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_user_report(
      'b2700000-0000-4000-8000-000000000002',
      'spam', null, null
    )$$,
  '23505', 'Report could not be created.',
  'reviewing user report still blocks an open duplicate'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2700000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_user_related_report')::uuid, 'dismissed'
  ),
  true,
  'a user report can transition from reviewing to dismissed'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_user_report(
      'b2700000-0000-4000-8000-000000000002',
      'spam', null, null
    )$$,
  'a user report can be created again after terminal status'
);

reset role;
select throws_ok(
  $$update public.reports set status = 'pending',
      resolved_at = null, resolved_by = null
    where id = current_setting('my_diary.e2d_main_report')::uuid$$,
  '23514', 'Invalid report status transition.',
  'the DB trigger rejects terminal rollback even for direct SQL'
);

select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e2d_second_entry_report',
  public.my_diary_create_exchange_entry_report(
    'e2700000-0000-4000-8000-000000000001', 'spam', null
  )::text,
  true
);
select ok(
  current_setting('my_diary.e2d_second_entry_report')::uuid is not null,
  'a new report is allowed after the prior report resolves'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2700000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2d_second_entry_report')::uuid, 'dismissed'
  ),
  true,
  'pending can transition directly to dismissed'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_second_entry_report')::uuid, 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a dismissed report is terminal'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000001', 'spam', null
    )$$,
  'a new report is allowed after the prior report is dismissed'
);

select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_archived_report')::uuid, 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a normal user cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e2700000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_archived_report')::uuid, 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a suspended admin cannot update report status'
);
select is(
  (select pg_catalog.count(*) from public.reports),
  0::bigint,
  'a suspended admin cannot read reports'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f2700000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e2d_archived_report')::uuid, 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a deactivated admin cannot update report status'
);
select is(
  (select pg_catalog.count(*) from public.report_snapshot_images),
  0::bigint,
  'a deactivated admin cannot read snapshot images'
);

-- Later edit/tag/image removal does not change evidence; held object cleanup fails.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2700000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2700000-0000-4000-8000-000000000001',
      'new title', 'new body', 'happy', 'Kyoto',
      array['gamma'], '[]'::jsonb
    )$$,
  'entry author edits text tags and removes image metadata after report'
);

select set_config('storage.operation', 'storage.object.delete_many', true);
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000001/f2700000-0000-4000-8000-000000000001',
    'b2700000-0000-4000-8000-000000000002'
  ),
  false,
  'reported image evidence hold blocks orphan cleanup'
);
reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2710000-0000-4000-8000-000000000099',
  'exchange-entry-images',
  'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000099/f2700000-0000-4000-8000-000000000099',
  'b2700000-0000-4000-8000-000000000002',
  '{"mimetype":"image/png","size":68}'::jsonb
);
set local role authenticated;
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000099/f2700000-0000-4000-8000-000000000099',
    'b2700000-0000-4000-8000-000000000002'
  ),
  true,
  'an unreported unreferenced image remains cleanup-eligible'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd2700000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select results_eq(
  $$select body, tag_names from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  $$values ('old body'::text, array['alpha','beta']::text[])$$,
  'snapshot text and tags remain immutable after entry edit'
);
select results_eq(
  $$select source_image_id, storage_path, mime_type, size_bytes
    from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2d_main_report')::uuid$$,
  $$values (
      null::uuid,
      'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000001/f2700000-0000-4000-8000-000000000001'::text,
      'image/png'::text, 68::bigint
    )$$,
  'source metadata deletion nulls only source_image_id and preserves evidence'
);

-- Report creation is atomic when a late snapshot-image insert fails.
reset role;
insert into public.exchange_entries (
  id, diary_id, author_participant_id, body
)
values (
  'e2700000-0000-4000-8000-000000000010',
  'd2700000-0000-4000-8000-000000000001',
  '12700000-0000-4000-8000-000000000002',
  'atomic body'
);
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2710000-0000-4000-8000-000000000010',
  'exchange-entry-images',
  'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000010/f2700000-0000-4000-8000-000000000010',
  'b2700000-0000-4000-8000-000000000002',
  '{"mimetype":"image/png","size":68}'::jsonb
);
insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f2700000-0000-4000-8000-000000000010',
  'e2700000-0000-4000-8000-000000000010',
  'b2700000-0000-4000-8000-000000000002/d2700000-0000-4000-8000-000000000001/e2700000-0000-4000-8000-000000000010/f2700000-0000-4000-8000-000000000010',
  0
);

create function pg_temp.my_diary_force_report_image_failure()
returns trigger
language plpgsql
as $function$
begin
  raise exception 'Forced report snapshot image failure.';
end;
$function$;
create trigger my_diary_test_force_report_image_failure
before insert on public.report_snapshot_images
for each row execute function pg_temp.my_diary_force_report_image_failure();

select set_config(
  'request.jwt.claim.sub',
  'a2700000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_report(
      'e2700000-0000-4000-8000-000000000010', 'spam', null
    )$$,
  'P0001', 'Forced report snapshot image failure.',
  'a late snapshot image failure aborts report creation'
);

reset role;
drop trigger my_diary_test_force_report_image_failure
  on public.report_snapshot_images;
select is(
  (select pg_catalog.count(*) from public.reports
   where target_type = 'exchange_entry'
     and target_id = 'e2700000-0000-4000-8000-000000000010'),
  0::bigint,
  'atomic rollback leaves no report row'
);
select is(
  (select pg_catalog.count(*)
   from public.report_exchange_entry_snapshots as snapshot
   where snapshot.source_entry_id =
     'e2700000-0000-4000-8000-000000000010'),
  0::bigint,
  'atomic rollback leaves no text snapshot'
);
select is(
  (select pg_catalog.count(*)
   from public.report_snapshot_images as snapshot_image
   where snapshot_image.source_image_id =
     'f2700000-0000-4000-8000-000000000010'),
  0::bigint,
  'atomic rollback leaves no image snapshot'
);

-- Account/source lifecycle keeps moderation evidence rather than cascading it.
delete from public.exchange_entries
where id = 'e2700000-0000-4000-8000-000000000003';
select ok(
  exists (
    select 1
    from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2d_archived_report')::uuid
      and source_entry_id is null
      and body = 'archived body'
  ),
  'physical source entry deletion preserves snapshot and nulls source ID'
);

delete from auth.users
where id = 'a2700000-0000-4000-8000-000000000001';
select ok(
  exists (
    select 1 from public.reports
    where id = current_setting('my_diary.e2d_main_report')::uuid
      and reporter_user_id is null
  ),
  'reporter account deletion preserves report and nulls reporter reference'
);

delete from auth.users
where id = 'b2700000-0000-4000-8000-000000000002';
select ok(
  exists (
    select 1 from public.reports
    where id = current_setting('my_diary.e2d_main_report')::uuid
      and reported_user_id =
        'b2700000-0000-4000-8000-000000000002'::uuid
  ),
  'reported user deletion preserves the snapshotted target UUID'
);

select * from finish();
rollback;
