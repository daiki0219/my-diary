begin;

create extension if not exists pgtap with schema extensions;

select plan(57);

-- Catalog, privacy, hardened functions, and operation-specific Storage RLS.
select columns_are(
  'my_diary_private', 'exchange_entry_image_cleanup_candidates',
  array[
    'storage_object_id', 'storage_path', 'image_id', 'entry_id', 'diary_id',
    'owner_user_id', 'removed_at', 'delete_after'
  ],
  'cleanup candidates have the exact evidence-agnostic retention columns'
);

select ok(
  (
    select relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
    from pg_catalog.pg_class as relation
    where relation.oid =
      'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass
  ),
  'the private candidate table is postgres-owned with RLS enabled'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.exchange_entry_image_cleanup_candidates',
    'SELECT, INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'service_role',
    'my_diary_private.exchange_entry_image_cleanup_candidates',
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  'candidate state has no application-role table ACL'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.reports'::pg_catalog.regclass
      and attribute.attname = 'evidence_delete_after'
      and attribute.atttypid = 'timestamptz'::pg_catalog.regtype
      and not attribute.attnotnull
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reports'::pg_catalog.regclass
      and conname = 'my_diary_reports_evidence_retention_shape_check'
      and contype = 'c'
  ),
  'reports have the nullable evidence deadline and retention shape check'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_report_snapshot_images_storage_path_idx'
  ),
  'snapshot evidence paths have a lookup index'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid in (
      'public.my_diary_update_report_status(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_purge_expired_report_evidence(uuid)'::pg_catalog.regprocedure,
      'public.my_diary_complete_exchange_image_cleanup(text)'::pg_catalog.regprocedure,
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure
    )
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  5::bigint,
  'all volatile retention and maintenance functions are hardened'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_list_due_exchange_image_cleanup_candidates(integer)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_purge_expired_report_evidence(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_purge_expired_report_evidence(uuid)',
    'EXECUTE'
  ),
  'authenticated callers use narrow RPCs and service_role receives no grant'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
  ),
  11::bigint,
  'exchange images have eleven operation-specific Storage policies'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_exchange_entry_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ),
  0::bigint,
  'exchange images still have no Storage UPDATE or ALL policy'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
  ) like '%exchange_entry_image_cleanup_candidates%'
  and pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(text,text)'::pg_catalog.regprocedure
  ) not like '%report_snapshot_images%',
  'general user cleanup is candidate-based without evidence lookup'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure
  ) like '%exchange_entry_image_cleanup_candidates%'
  and pg_catalog.pg_get_functiondef(
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure
  ) not like '%removedImagePaths%',
  'the update RPC records candidates and no longer returns cleanup paths'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_evidence_select_is_allowed(text)'::pg_catalog.regprocedure
  ) like '%report_snapshot_images%'
  and pg_catalog.pg_get_functiondef(
    'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
  ) like '%storage.object.delete_many%',
  'admin evidence SELECT and maintenance DELETE use separate exact helpers'
);

-- Participants, admins, entries, images, and two reports sharing one path.
insert into auth.users (id, email)
values
  ('a3000000-0000-4000-8000-000000000001', 'e2g-a@example.test'),
  ('b3000000-0000-4000-8000-000000000002', 'e2g-b@example.test'),
  ('c3000000-0000-4000-8000-000000000003', 'e2g-admin@example.test'),
  ('d3000000-0000-4000-8000-000000000004', 'e2g-sadmin@example.test'),
  ('e3000000-0000-4000-8000-000000000005', 'e2g-dadmin@example.test'),
  ('f3000000-0000-4000-8000-000000000006', 'e2g-third@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'c3000000-0000-4000-8000-000000000003',
  'd3000000-0000-4000-8000-000000000004',
  'e3000000-0000-4000-8000-000000000005'
);
update public.accounts set status = 'suspended'
where user_id = 'd3000000-0000-4000-8000-000000000004';
update public.accounts set status = 'deactivated'
where user_id = 'e3000000-0000-4000-8000-000000000005';

insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values ('d3000000-0000-4000-8000-000000000001', 'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('13000000-0000-4000-8000-000000000001',
   'd3000000-0000-4000-8000-000000000001', 1,
   'a3000000-0000-4000-8000-000000000001'),
  ('23000000-0000-4000-8000-000000000002',
   'd3000000-0000-4000-8000-000000000001', 2,
   'b3000000-0000-4000-8000-000000000002');

insert into public.exchange_entries (
  id, diary_id, author_participant_id, title, body
)
values
  ('e3000000-0000-4000-8000-000000000001',
   'd3000000-0000-4000-8000-000000000001',
   '23000000-0000-4000-8000-000000000002',
   'held', 'held body'),
  ('e3000000-0000-4000-8000-000000000002',
   'd3000000-0000-4000-8000-000000000001',
   '23000000-0000-4000-8000-000000000002',
   'unheld', 'unheld body'),
  ('e3000000-0000-4000-8000-000000000003',
   'd3000000-0000-4000-8000-000000000001',
   '23000000-0000-4000-8000-000000000002',
   'soft', 'soft body'),
  ('e3000000-0000-4000-8000-000000000004',
   'd3000000-0000-4000-8000-000000000001',
   '23000000-0000-4000-8000-000000000002',
   'rollback', 'rollback body');

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  ('93000000-0000-4000-8000-000000000001',
   'exchange-entry-images',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001',
   'b3000000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93000000-0000-4000-8000-000000000002',
   'exchange-entry-images',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002',
   'b3000000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93000000-0000-4000-8000-000000000003',
   'exchange-entry-images',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000003/f3000000-0000-4000-8000-000000000003',
   'b3000000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb),
  ('93000000-0000-4000-8000-000000000004',
   'exchange-entry-images',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000004/f3000000-0000-4000-8000-000000000004',
   'b3000000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}'::jsonb);

insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values
  ('f3000000-0000-4000-8000-000000000001',
   'e3000000-0000-4000-8000-000000000001',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001', 0),
  ('f3000000-0000-4000-8000-000000000002',
   'e3000000-0000-4000-8000-000000000002',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002', 0),
  ('f3000000-0000-4000-8000-000000000003',
   'e3000000-0000-4000-8000-000000000003',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000003/f3000000-0000-4000-8000-000000000003', 0),
  ('f3000000-0000-4000-8000-000000000004',
   'e3000000-0000-4000-8000-000000000004',
   'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000004/f3000000-0000-4000-8000-000000000004', 0);

select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select set_config(
  'my_diary.e2g_entry_report',
  public.my_diary_create_exchange_entry_report(
    'e3000000-0000-4000-8000-000000000001', 'harassment', null
  )::text,
  true
);
select set_config(
  'my_diary.e2g_user_report',
  public.my_diary_create_user_report(
    'b3000000-0000-4000-8000-000000000002',
    'threat_or_danger', null,
    'e3000000-0000-4000-8000-000000000001'
  )::text,
  true
);

reset role;
select is(
  (
    select pg_catalog.count(distinct report_id)
    from public.report_snapshot_images
    where storage_path =
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'entry and user reports independently retain the same exact evidence path'
);

select is(
  (
    select pg_catalog.count(*)
    from public.reports
    where id in (
      current_setting('my_diary.e2g_entry_report')::uuid,
      current_setting('my_diary.e2g_user_report')::uuid
    )
      and status = 'pending'
      and evidence_delete_after is null
  ),
  2::bigint,
  'pending reports have no evidence deadline'
);

select set_config(
  'request.jwt.claim.sub',
  'b3000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  public.my_diary_update_exchange_entry_with_images(
    'e3000000-0000-4000-8000-000000000001',
    'held edited', 'held edited body', null, null, null, '[]'::jsonb
  ),
  pg_catalog.jsonb_build_object(
    'entryId', 'e3000000-0000-4000-8000-000000000001'::uuid
  ),
  'reported image removal returns only entryId'
);
select is(
  public.my_diary_update_exchange_entry_with_images(
    'e3000000-0000-4000-8000-000000000002',
    'unheld edited', 'unheld edited body', null, null, null, '[]'::jsonb
  ),
  pg_catalog.jsonb_build_object(
    'entryId', 'e3000000-0000-4000-8000-000000000002'::uuid
  ),
  'unreported image removal has the identical opaque return shape'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where image_id in (
      'f3000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000002'
    )
  ),
  2::bigint,
  'both reported and unreported confirmed removals create candidates'
);

select ok(
  not exists (
    select 1
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where image_id in (
      'f3000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000002'
    )
      and delete_after <> removed_at + interval '7 days'
  ),
  'every confirmed removal stores an exact seven-day deadline'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entry_images
    where id in (
      'f3000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000002'
    )
  ),
  0::bigint,
  'relation metadata is removed immediately for both candidates'
);

select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000002'
    )
  ),
  2::bigint,
  'both physical objects remain during retention'
);

select set_config(
  'request.jwt.claim.sub',
  'b3000000-0000-4000-8000-000000000002', true
);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000002'
  ),
  false,
  'the owner cannot delete a reported candidate during retention'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002',
    'b3000000-0000-4000-8000-000000000002'
  ),
  false,
  'the owner receives the same denial for an unreported candidate'
);

reset role;
update my_diary_private.exchange_entry_image_cleanup_candidates
set removed_at = pg_catalog.statement_timestamp() - interval '8 days',
    delete_after = pg_catalog.statement_timestamp() - interval '1 day'
where image_id in (
  'f3000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000002'
);
set local role authenticated;
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000002'
  ),
  false,
  'the owner still cannot delete a due reported candidate'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002',
    'b3000000-0000-4000-8000-000000000002'
  ),
  false,
  'seven days never reopens owner DELETE for an unreported candidate'
);

reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  '93000000-0000-4000-8000-000000000099',
  'exchange-entry-images',
  'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000099/f3000000-0000-4000-8000-000000000099',
  'b3000000-0000-4000-8000-000000000002',
  '{"mimetype":"image/png","size":68}'::jsonb
);
set local role authenticated;
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000099/f3000000-0000-4000-8000-000000000099',
    'b3000000-0000-4000-8000-000000000002'
  ),
  true,
  'a never-confirmed owner orphan remains cleanup eligible'
);

select set_config('storage.operation', '', true);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000002'
    )
  ),
  0::bigint,
  'the author cannot SELECT either removed retained candidate'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000002'
    )
  ),
  0::bigint,
  'the other participant cannot SELECT retained candidates'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000002'
    )
  ),
  0::bigint,
  'a third party cannot SELECT retained candidates'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'an active admin can SELECT the exact retained evidence object'
);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'an active admin cannot normally SELECT an unreported candidate'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd3000000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'a suspended admin cannot SELECT exact evidence bytes'
);

-- Open/terminal deadline semantics and active-admin-only trusted maintenance.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2g_entry_report')::uuid, 'reviewing'
  ),
  true,
  'active admin moves a pending report to reviewing'
);
select ok(
  (
    select status = 'reviewing' and evidence_delete_after is null
    from public.reports
    where id = current_setting('my_diary.e2g_entry_report')::uuid
  ),
  'reviewing retains evidence without a deadline'
);
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2g_entry_report')::uuid, 'resolved'
  ),
  true,
  'active admin resolves a reviewing report'
);
select ok(
  (
    select evidence_delete_after = resolved_at + interval '30 days'
    from public.reports
    where id = current_setting('my_diary.e2g_entry_report')::uuid
  ),
  'resolved evidence deadline is the actual terminal transition plus 30 days'
);
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e2g_user_report')::uuid, 'dismissed'
  ),
  true,
  'active admin dismisses a pending report'
);
select ok(
  (
    select evidence_delete_after = resolved_at + interval '30 days'
    from public.reports
    where id = current_setting('my_diary.e2g_user_report')::uuid
  ),
  'dismissed evidence deadline is the actual terminal transition plus 30 days'
);
select throws_ok(
  $$select public.my_diary_purge_expired_report_evidence(
      current_setting('my_diary.e2g_entry_report')::uuid
    )$$,
  '42501', 'Report evidence could not be purged.',
  'terminal evidence cannot be purged before its deadline'
);

reset role;
alter table public.reports
  disable trigger my_diary_reports_reject_status_transition;
update public.reports
set resolved_at = pg_catalog.statement_timestamp() - interval '31 days',
    evidence_delete_after =
      pg_catalog.statement_timestamp() - interval '1 day'
where id in (
  current_setting('my_diary.e2g_entry_report')::uuid,
  current_setting('my_diary.e2g_user_report')::uuid
);
alter table public.reports
  enable trigger my_diary_reports_reject_status_transition;

select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;
select results_eq(
  $$select pg_catalog.unnest(
      public.my_diary_list_due_exchange_image_cleanup_candidates(10)
    )$$,
  $$values (
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002'::text
  )$$,
  'due listing exposes only the unheld candidate to active-admin maintenance'
);
select is(
  my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      '93000000-0000-4000-8000-000000000002',
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002'
    ),
  true,
  'active-admin maintenance can delete a due unheld candidate'
);
select is(
  my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      '93000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001'
    ),
  false,
  'active-admin maintenance cannot delete a due evidence-held candidate'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd3000000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select is(
  my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      '93000000-0000-4000-8000-000000000002',
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002'
    ),
  false,
  'a suspended admin cannot run trusted image maintenance'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  public.my_diary_purge_expired_report_evidence(
    current_setting('my_diary.e2g_entry_report')::uuid
  ),
  true,
  'active admin purges the first expired report evidence atomically'
);

reset role;
select ok(
  exists (
    select 1 from public.reports
    where id = current_setting('my_diary.e2g_entry_report')::uuid
      and status = 'resolved'
  )
  and not exists (
    select 1 from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e2g_entry_report')::uuid
  )
  and not exists (
    select 1 from public.report_snapshot_images
    where report_id = current_setting('my_diary.e2g_entry_report')::uuid
  ),
  'purge keeps the report row and removes its text and image evidence together'
);

select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;
select is(
  my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      '93000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001'
    ),
  false,
  'the other report reference still blocks physical delete'
);
select set_config('storage.operation', '', true);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'admin evidence SELECT remains while the second report reference exists'
);
select is(
  public.my_diary_purge_expired_report_evidence(
    current_setting('my_diary.e2g_user_report')::uuid
  ),
  true,
  'active admin purges the last expired report evidence'
);

reset role;
select ok(
  (
    select pg_catalog.count(*)
    from public.reports
    where id in (
      current_setting('my_diary.e2g_entry_report')::uuid,
      current_setting('my_diary.e2g_user_report')::uuid
    )
  ) = 2
  and not exists (
    select 1
    from public.report_snapshot_images
    where storage_path =
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001'
  ),
  'both report records remain after the final image evidence reference is purged'
);

select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000003', true
);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;
select is(
  my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      '93000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000001/f3000000-0000-4000-8000-000000000001'
    ),
  true,
  'the last purge releases the due candidate to trusted maintenance'
);
select set_config('storage.operation', '', true);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'purging the last snapshot reference revokes admin evidence SELECT'
);

select set_config('storage.operation', 'storage.object.delete_many', true);
select set_config('storage.allow_delete_query', 'true', true);
select lives_ok(
  $$delete from storage.objects
    where id = '93000000-0000-4000-8000-000000000002'$$,
  'active-admin Storage DELETE removes only the due unheld candidate object'
);
select is(
  public.my_diary_complete_exchange_image_cleanup(
    'b3000000-0000-4000-8000-000000000002/d3000000-0000-4000-8000-000000000001/e3000000-0000-4000-8000-000000000002/f3000000-0000-4000-8000-000000000002'
  ),
  true,
  'completion removes a candidate only after the object is absent'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where image_id = 'f3000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'successful maintenance leaves no unconfigured candidate tombstone'
);

-- Existing soft-delete lifecycle remains out of scope.
select set_config(
  'request.jwt.claim.sub',
  'b3000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      'e3000000-0000-4000-8000-000000000003'
    )$$,
  'existing entry soft delete remains available to the author'
);

reset role;
select ok(
  exists (
    select 1
    from public.exchange_entry_images
    where id = 'f3000000-0000-4000-8000-000000000003'
  )
  and not exists (
    select 1
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where image_id = 'f3000000-0000-4000-8000-000000000003'
  ),
  'soft delete retains image metadata and does not create a seven-day candidate'
);

-- A candidate-write failure rolls back the entire edit and metadata removal.
create function pg_temp.my_diary_fail_candidate_insert()
returns trigger
language plpgsql
as $function$
begin
  raise exception 'forced candidate failure';
end;
$function$;

create trigger my_diary_e2g_fail_candidate_insert
before insert on my_diary_private.exchange_entry_image_cleanup_candidates
for each row execute function pg_temp.my_diary_fail_candidate_insert();

select set_config(
  'request.jwt.claim.sub',
  'b3000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e3000000-0000-4000-8000-000000000004',
      'changed', 'changed body', null, null, null, '[]'::jsonb
    )$$,
  'P0001', 'forced candidate failure',
  'candidate insert failure aborts the update RPC'
);

reset role;
drop trigger my_diary_e2g_fail_candidate_insert
  on my_diary_private.exchange_entry_image_cleanup_candidates;
drop function pg_temp.my_diary_fail_candidate_insert();

select ok(
  exists (
    select 1
    from public.exchange_entry_images
    where id = 'f3000000-0000-4000-8000-000000000004'
  )
  and exists (
    select 1
    from public.exchange_entries
    where id = 'e3000000-0000-4000-8000-000000000004'
      and title = 'rollback'
      and body = 'rollback body'
  )
  and not exists (
    select 1
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where image_id = 'f3000000-0000-4000-8000-000000000004'
  ),
  'candidate failure rolls back text, metadata, and ledger atomically'
);

select * from finish();
rollback;
