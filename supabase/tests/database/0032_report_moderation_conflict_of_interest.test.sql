begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- Successor catalog, policy shape, and unchanged narrow ACLs.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'reports', 'report_exchange_entry_snapshots',
        'report_snapshot_images'
      )
      and permissive = 'PERMISSIVE'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
      and pg_catalog.lower(qual) like '%reported_user_id <>%auth.uid()%'
      and pg_catalog.lower(qual) like '%reporter_user_id is null%'
      and pg_catalog.lower(qual) like '%reporter_user_id <>%auth.uid()%'
  ),
  3::bigint,
  'all three report SELECT policies enforce the target and reporter exclusions'
);

select ok(
  pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'::pg_catalog.regprocedure
  )) like '%join public.reports as report%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure
  )) like '%report.reported_user_id <> viewer_user_id%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure
  )) like '%report.reporter_user_id is null%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure
  )) like '%report.reported_user_id <> viewer_user_id%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure
  )) like '%report.reporter_user_id is null%',
  'exact evidence, status, and purge functions enforce report-specific conflict checks'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid in (
      'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'::pg_catalog.regprocedure,
      'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure
    )
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  3::bigint,
  'the three replaced functions retain hardened SECURITY DEFINER metadata'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_report_status(uuid,text)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_purge_expired_report_evidence(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'public.my_diary_update_report_status(uuid,text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_purge_expired_report_evidence(uuid)', 'EXECUTE'
  ),
  'authenticated retains only the narrow function entry points without ACL widening'
);

-- A is both an active admin and a conflict actor across two reports. C is the
-- unrelated active moderator. B and D are ordinary participants/users.
insert into auth.users (id, email)
values
  ('a3200000-0000-4000-8000-000000000001', 'e3f1-admin-a@example.test'),
  ('b3200000-0000-4000-8000-000000000002', 'e3f1-user-b@example.test'),
  ('c3200000-0000-4000-8000-000000000003', 'e3f1-admin-c@example.test'),
  ('d3200000-0000-4000-8000-000000000004', 'e3f1-user-d@example.test'),
  ('e3200000-0000-4000-8000-000000000005', 'e3f1-sadmin@example.test'),
  ('f3200000-0000-4000-8000-000000000006', 'e3f1-dadmin@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'a3200000-0000-4000-8000-000000000001',
  'c3200000-0000-4000-8000-000000000003',
  'e3200000-0000-4000-8000-000000000005',
  'f3200000-0000-4000-8000-000000000006'
);
update public.accounts
set status = 'suspended'
where user_id = 'e3200000-0000-4000-8000-000000000005';
update public.accounts
set status = 'deactivated'
where user_id = 'f3200000-0000-4000-8000-000000000006';

insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values
  ('d3200000-0000-4000-8000-000000000001',
   'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('13200000-0000-4000-8000-000000000001',
   'd3200000-0000-4000-8000-000000000001', 1,
   'b3200000-0000-4000-8000-000000000002'),
  ('23200000-0000-4000-8000-000000000002',
   'd3200000-0000-4000-8000-000000000001', 2,
   'd3200000-0000-4000-8000-000000000004');

insert into public.exchange_entries (
  id, diary_id, author_participant_id, title, body
)
values (
  'e3200000-0000-4000-8000-000000000010',
  'd3200000-0000-4000-8000-000000000001',
  '13200000-0000-4000-8000-000000000001',
  'private live entry', 'private live body'
);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  ('93200000-0000-4000-8000-000000000001',
   'exchange-entry-images',
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000001/f3200000-0000-4000-8000-000000000001',
   'b3200000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93200000-0000-4000-8000-000000000002',
   'exchange-entry-images',
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000002/f3200000-0000-4000-8000-000000000002',
   'b3200000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93200000-0000-4000-8000-000000000003',
   'exchange-entry-images',
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000003/f3200000-0000-4000-8000-000000000003',
   'b3200000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93200000-0000-4000-8000-000000000010',
   'exchange-entry-images',
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000010/f3200000-0000-4000-8000-000000000010',
   'b3200000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93200000-0000-4000-8000-000000000011',
   'exchange-entry-images',
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000001/f3200000-0000-4000-8000-000000000011',
   'b3200000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb);

insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f3200000-0000-4000-8000-000000000010',
  'e3200000-0000-4000-8000-000000000010',
  'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000010/f3200000-0000-4000-8000-000000000010',
  0
);

insert into public.reports (
  id, reporter_user_id, target_type, target_id, reported_user_id,
  reason, status
)
values
  ('73200000-0000-4000-8000-000000000001',
   'b3200000-0000-4000-8000-000000000002', 'user',
   'a3200000-0000-4000-8000-000000000001',
   'a3200000-0000-4000-8000-000000000001', 'harassment', 'pending'),
  ('73200000-0000-4000-8000-000000000002',
   'a3200000-0000-4000-8000-000000000001', 'user',
   'b3200000-0000-4000-8000-000000000002',
   'b3200000-0000-4000-8000-000000000002', 'spam', 'pending'),
  ('73200000-0000-4000-8000-000000000003',
   null, 'user',
   'b3200000-0000-4000-8000-000000000002',
   'b3200000-0000-4000-8000-000000000002',
   'personal_information', 'pending');

insert into public.report_exchange_entry_snapshots (
  report_id, source_entry_id, source_diary_id,
  source_author_participant_id, entry_created_at, entry_updated_at,
  title, body, tag_names
)
values
  ('73200000-0000-4000-8000-000000000001', null,
   'd3200000-0000-4000-8000-000000000001',
   '13200000-0000-4000-8000-000000000001', now(), now(),
   'target-admin evidence', 'target-admin body', array['target']::text[]),
  ('73200000-0000-4000-8000-000000000002', null,
   'd3200000-0000-4000-8000-000000000001',
   '13200000-0000-4000-8000-000000000001', now(), now(),
   'reporter-admin evidence', 'reporter-admin body', array['reporter']::text[]),
  ('73200000-0000-4000-8000-000000000003', null,
   'd3200000-0000-4000-8000-000000000001',
   '13200000-0000-4000-8000-000000000001', now(), now(),
   'null-reporter evidence', 'null-reporter body', array['orphan']::text[]);

insert into public.report_snapshot_images (
  id, report_id, source_image_id, storage_path, sort_order,
  mime_type, size_bytes
)
values
  ('83200000-0000-4000-8000-000000000001',
   '73200000-0000-4000-8000-000000000001', null,
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000001/f3200000-0000-4000-8000-000000000001',
   0, 'image/png', 68),
  ('83200000-0000-4000-8000-000000000002',
   '73200000-0000-4000-8000-000000000002', null,
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000002/f3200000-0000-4000-8000-000000000002',
   0, 'image/png', 68),
  ('83200000-0000-4000-8000-000000000003',
   '73200000-0000-4000-8000-000000000003', null,
   'b3200000-0000-4000-8000-000000000002/d3200000-0000-4000-8000-000000000001/e3200000-0000-4000-8000-000000000003/f3200000-0000-4000-8000-000000000003',
   0, 'image/png', 68);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('storage.operation', '', true);

-- A cannot moderate the report targeting A or the report submitted by A.
select set_config(
  'request.jwt.claim.sub',
  'a3200000-0000-4000-8000-000000000001', true
);
set local role authenticated;

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000001')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'the reported-user admin cannot read its report, snapshots, or exact evidence'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000001', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reported-user admin cannot update its report status'
);
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000002')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'the reporter admin cannot read its report, snapshots, or exact evidence'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000002', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reporter admin cannot update its report status'
);

-- Ordinary users and non-active admins remain denied at every read boundary.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'b3200000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000001')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'the ordinary reporter cannot read report evidence'
);
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000002')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'the ordinary reported user cannot read report evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd3200000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots),
      (select pg_catalog.count(*) from public.report_snapshot_images),
      (select pg_catalog.count(*) from storage.objects
       where id in (
         '93200000-0000-4000-8000-000000000001',
         '93200000-0000-4000-8000-000000000002',
         '93200000-0000-4000-8000-000000000003'
       ))$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'another ordinary participant cannot read any report evidence'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000003', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'an unrelated ordinary user cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e3200000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots),
      (select pg_catalog.count(*) from public.report_snapshot_images),
      (select pg_catalog.count(*) from storage.objects
       where id in (
         '93200000-0000-4000-8000-000000000001',
         '93200000-0000-4000-8000-000000000002',
         '93200000-0000-4000-8000-000000000003'
       ))$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'a suspended admin cannot read report evidence'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000003', 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a suspended admin cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3200000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots),
      (select pg_catalog.count(*) from public.report_snapshot_images),
      (select pg_catalog.count(*) from storage.objects
       where id in (
         '93200000-0000-4000-8000-000000000001',
         '93200000-0000-4000-8000-000000000002',
         '93200000-0000-4000-8000-000000000003'
       ))$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'a deactivated admin cannot read report evidence'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000003', 'resolved'
    )$$,
  '42501', 'Report status could not be updated.',
  'a deactivated admin cannot update report status'
);

-- C is unrelated to all three reports, including the NULL-reporter report.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3200000-0000-4000-8000-000000000003', true
);
set local role authenticated;

select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000001')$$,
  $$values (1::bigint, 1::bigint, 1::bigint, 1::bigint)$$,
  'the unrelated active admin can read target-admin report evidence'
);
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000002'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000002')$$,
  $$values (1::bigint, 1::bigint, 1::bigint, 1::bigint)$$,
  'the unrelated active admin can read reporter-admin report evidence'
);
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = '73200000-0000-4000-8000-000000000003'),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id = '73200000-0000-4000-8000-000000000003'),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id = '73200000-0000-4000-8000-000000000003'),
      (select pg_catalog.count(*) from storage.objects
       where id = '93200000-0000-4000-8000-000000000003')$$,
  $$values (1::bigint, 1::bigint, 1::bigint, 1::bigint)$$,
  'a NULL reporter does not hide evidence from an unrelated active admin'
);
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.exchange_diaries
       where id = 'd3200000-0000-4000-8000-000000000001'),
      (select pg_catalog.count(*) from public.exchange_entries
       where id = 'e3200000-0000-4000-8000-000000000010'),
      (select pg_catalog.count(*) from public.exchange_entry_images
       where id = 'f3200000-0000-4000-8000-000000000010'),
      (select pg_catalog.count(*) from storage.objects
       where id in (
         '93200000-0000-4000-8000-000000000010',
         '93200000-0000-4000-8000-000000000011'
       ))$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'moderation grants neither whole-diary nor live or same-entry sibling image access'
);

select is(
  public.my_diary_update_report_status(
    '73200000-0000-4000-8000-000000000001', 'reviewing'
  ),
  true,
  'the unrelated active admin moves pending to reviewing'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000001', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'same-status moderation remains rejected'
);
select is(
  public.my_diary_update_report_status(
    '73200000-0000-4000-8000-000000000001', 'resolved'
  ),
  true,
  'the unrelated active admin moves reviewing to resolved'
);
select ok(
  (
    select status = 'resolved'
      and resolved_by = 'c3200000-0000-4000-8000-000000000003'::uuid
      and resolved_at is not null
      and evidence_delete_after = resolved_at + interval '30 days'
    from public.reports
    where id = '73200000-0000-4000-8000-000000000001'
  ),
  'terminal moderation preserves resolver, timestamp, and thirty-day deadline'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73200000-0000-4000-8000-000000000001', 'dismissed'
    )$$,
  '42501', 'Report status could not be updated.',
  'terminal-to-terminal moderation remains rejected'
);
select is(
  public.my_diary_update_report_status(
    '73200000-0000-4000-8000-000000000002', 'dismissed'
  ),
  true,
  'the unrelated active admin can dismiss the reporter-admin report'
);
select is(
  public.my_diary_update_report_status(
    '73200000-0000-4000-8000-000000000003', 'resolved'
  ),
  true,
  'the unrelated active admin can resolve the NULL-reporter report'
);

-- Move only the terminal deadlines into the past; fixtures are transactional.
reset role;
alter table public.reports
  disable trigger my_diary_reports_reject_status_transition;
update public.reports
set resolved_at = pg_catalog.statement_timestamp() - interval '31 days',
    evidence_delete_after = pg_catalog.statement_timestamp() - interval '1 day'
where id in (
  '73200000-0000-4000-8000-000000000001',
  '73200000-0000-4000-8000-000000000002',
  '73200000-0000-4000-8000-000000000003'
);
alter table public.reports
  enable trigger my_diary_reports_reject_status_transition;

select set_config(
  'request.jwt.claim.sub',
  'd3200000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      '73200000-0000-4000-8000-000000000003'
    )$$,
  '42501', 'Report evidence could not be purged.',
  'an unrelated ordinary user cannot purge expired evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3200000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      '73200000-0000-4000-8000-000000000001'
    )$$,
  '42501', 'Report evidence could not be purged.',
  'the reported-user admin cannot purge its expired evidence'
);
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      '73200000-0000-4000-8000-000000000002'
    )$$,
  '42501', 'Report evidence could not be purged.',
  'the reporter admin cannot purge its expired evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e3200000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      '73200000-0000-4000-8000-000000000003'
    )$$,
  '42501', 'Report evidence could not be purged.',
  'a suspended admin cannot purge expired evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3200000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      '73200000-0000-4000-8000-000000000003'
    )$$,
  '42501', 'Report evidence could not be purged.',
  'a deactivated admin cannot purge expired evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3200000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  public.my_diary_purge_expired_report_evidence(
    '73200000-0000-4000-8000-000000000001'
  ),
  true,
  'the unrelated active admin purges target-admin report evidence'
);
select is(
  public.my_diary_purge_expired_report_evidence(
    '73200000-0000-4000-8000-000000000002'
  ),
  true,
  'the unrelated active admin purges reporter-admin report evidence'
);
select is(
  public.my_diary_purge_expired_report_evidence(
    '73200000-0000-4000-8000-000000000003'
  ),
  true,
  'the unrelated active admin purges NULL-reporter report evidence'
);

reset role;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id in (
         '73200000-0000-4000-8000-000000000001',
         '73200000-0000-4000-8000-000000000002',
         '73200000-0000-4000-8000-000000000003'
       )),
      (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
       where report_id in (
         '73200000-0000-4000-8000-000000000001',
         '73200000-0000-4000-8000-000000000002',
         '73200000-0000-4000-8000-000000000003'
       )),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id in (
         '73200000-0000-4000-8000-000000000001',
         '73200000-0000-4000-8000-000000000002',
         '73200000-0000-4000-8000-000000000003'
       )),
      (select pg_catalog.count(*) from storage.objects
       where id in (
         '93200000-0000-4000-8000-000000000001',
         '93200000-0000-4000-8000-000000000002',
         '93200000-0000-4000-8000-000000000003'
       ))$$,
  $$values (3::bigint, 0::bigint, 0::bigint, 3::bigint)$$,
  'purge retains report rows and physical bytes while removing both snapshot relations'
);

select set_config(
  'request.jwt.claim.sub',
  'c3200000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93200000-0000-4000-8000-000000000001',
      '93200000-0000-4000-8000-000000000002',
      '93200000-0000-4000-8000-000000000003'
    )
  ),
  0::bigint,
  'purging the exact snapshot references revokes moderator Storage reads'
);

select * from finish();

rollback;
