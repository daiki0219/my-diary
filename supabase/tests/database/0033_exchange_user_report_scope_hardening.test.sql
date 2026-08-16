begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- Successor catalog, ACL, and retained generic boundary.
select has_function(
  'public',
  'my_diary_create_exchange_user_report',
  array['uuid', 'text', 'text', 'uuid'],
  'the exact Exchange user-report successor exists'
);

select is(
  (
    select proargnames
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  array[
    'p_diary_id', 'p_reason', 'p_details',
    'p_related_exchange_entry_id'
  ]::text[],
  'the successor accepts diary scope and no target user identifier'
);

select is(
  (
    select prorettype::regtype::text
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  'uuid'::text,
  'the successor returns uuid'
);

select is(
  (
    select pg_catalog.pg_get_userbyid(proowner)
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  'postgres',
  'the successor owner is postgres'
);

select ok(
  (
    select prosecdef
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  'the successor is SECURITY DEFINER'
);

select is(
  (
    select provolatile::text
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  'v',
  'the successor is VOLATILE'
);

select is(
  (
    select proconfig
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  array['search_path=""']::text[],
  'the successor fixes an empty search_path'
);

select is(
  (
    select pronargdefaults
    from pg_catalog.pg_proc
    where oid =
      'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)'::regprocedure
  ),
  0::smallint,
  'the successor has no default arguments'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname =
        'my_diary_create_exchange_user_report'
  ),
  1::bigint,
  'the successor has exactly one overload'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated can execute the successor'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'anon cannot execute the successor'
);

select ok(
  not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_create_exchange_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'unnecessary application roles cannot execute the successor'
);

select has_function(
  'public',
  'my_diary_create_user_report',
  array['uuid', 'text', 'text', 'uuid'],
  'the old generic RPC remains for migration compatibility'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated cannot execute the old generic RPC'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_create_user_report(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'the old generic RPC has no unnecessary application-role EXECUTE'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.reports', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.report_exchange_entry_snapshots',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.report_snapshot_images',
    'INSERT, UPDATE, DELETE'
  ),
  'report and snapshot table mutation remains RPC-only'
);

-- Active, archived, suspended, deactivated, admin, and third-party users.
insert into auth.users (id, email)
values
  ('a3300000-0000-4000-8000-000000000001', 'e3f3-a@example.test'),
  ('b3300000-0000-4000-8000-000000000002', 'e3f3-b@example.test'),
  ('c3300000-0000-4000-8000-000000000003', 'e3f3-c@example.test'),
  ('d3300000-0000-4000-8000-000000000004', 'e3f3-d@example.test'),
  ('e3300000-0000-4000-8000-000000000005', 'e3f3-e@example.test'),
  ('f3300000-0000-4000-8000-000000000006', 'e3f3-f@example.test'),
  ('a3310000-0000-4000-8000-000000000007', 'e3f3-g@example.test'),
  ('b3310000-0000-4000-8000-000000000008', 'e3f3-h@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'b3300000-0000-4000-8000-000000000002',
  'c3300000-0000-4000-8000-000000000003'
);

insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values
  ('d3300000-0000-4000-8000-000000000001', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000002', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000003', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000004', 'archived', 1,
   now(), 'user_archived'),
  ('d3300000-0000-4000-8000-000000000005', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000006', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000007', 'active', 1, null, null),
  ('d3300000-0000-4000-8000-000000000008', 'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('13300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000001', 1,
   'a3300000-0000-4000-8000-000000000001'),
  ('13300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000001', 2,
   'b3300000-0000-4000-8000-000000000002'),
  ('23300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000002', 1,
   'a3300000-0000-4000-8000-000000000001'),
  ('23300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000002', 2,
   'b3300000-0000-4000-8000-000000000002'),
  ('33300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000003', 1,
   'c3300000-0000-4000-8000-000000000003'),
  ('33300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000003', 2,
   'd3300000-0000-4000-8000-000000000004'),
  ('43300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000004', 1,
   'a3300000-0000-4000-8000-000000000001'),
  ('43300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000004', 2,
   'b3300000-0000-4000-8000-000000000002'),
  ('53300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000005', 1,
   'a3300000-0000-4000-8000-000000000001'),
  ('53300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000005', 2,
   'f3300000-0000-4000-8000-000000000006'),
  ('63300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000006', 1,
   'a3300000-0000-4000-8000-000000000001'),
  ('63300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000006', 2,
   'e3300000-0000-4000-8000-000000000005'),
  ('73300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000007', 1,
   'a3310000-0000-4000-8000-000000000007'),
  ('73300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000007', 2,
   'd3300000-0000-4000-8000-000000000004'),
  ('83300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000008', 1,
   'b3310000-0000-4000-8000-000000000008'),
  ('83300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000008', 2,
   'd3300000-0000-4000-8000-000000000004');

insert into public.exchange_entries (
  id, diary_id, author_participant_id, title, body, location_name
)
values
  ('e3300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-000000000001',
   '13300000-0000-4000-8000-000000000002',
   'counterpart title', 'counterpart body', 'Tokyo'),
  ('e3300000-0000-4000-8000-000000000002',
   'd3300000-0000-4000-8000-000000000001',
   '13300000-0000-4000-8000-000000000001',
   null, 'reporter body', null),
  ('e3300000-0000-4000-8000-000000000003',
   'd3300000-0000-4000-8000-000000000002',
   '23300000-0000-4000-8000-000000000002',
   null, 'same counterpart other diary', null),
  ('e3300000-0000-4000-8000-000000000004',
   'd3300000-0000-4000-8000-000000000003',
   '33300000-0000-4000-8000-000000000002',
   null, 'third party body', null),
  ('e3300000-0000-4000-8000-000000000005',
   'd3300000-0000-4000-8000-000000000001',
   '13300000-0000-4000-8000-000000000002',
   null, 'soft delete body', null),
  ('e3300000-0000-4000-8000-000000000006',
   'd3300000-0000-4000-8000-000000000004',
   '43300000-0000-4000-8000-000000000002',
   null, 'archived counterpart body', null),
  ('e3300000-0000-4000-8000-000000000007',
   'd3300000-0000-4000-8000-000000000005',
   '53300000-0000-4000-8000-000000000002',
   null, 'deactivated counterpart body', null);

update public.exchange_entries
set body = null, deleted_at = now(), redaction_reason = 'user_deleted'
where id = 'e3300000-0000-4000-8000-000000000005';

insert into public.tags (id, name, normalized_name)
values ('a3300000-0000-4000-8000-000000000099', 'scope', 'scope');
insert into public.exchange_entry_tags (entry_id, tag_id)
values (
  'e3300000-0000-4000-8000-000000000001',
  'a3300000-0000-4000-8000-000000000099'
);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  '93300000-0000-4000-8000-000000000001',
  'exchange-entry-images',
  'b3300000-0000-4000-8000-000000000002/d3300000-0000-4000-8000-000000000001/e3300000-0000-4000-8000-000000000001/f3300000-0000-4000-8000-000000000001',
  'b3300000-0000-4000-8000-000000000002',
  '{"mimetype":"image/png","size":68}'::jsonb
);
insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f3300000-0000-4000-8000-000000000001',
  'e3300000-0000-4000-8000-000000000001',
  'b3300000-0000-4000-8000-000000000002/d3300000-0000-4000-8000-000000000001/e3300000-0000-4000-8000-000000000001/f3300000-0000-4000-8000-000000000001',
  0
);

-- Deactivation archives existing Exchange diaries; suspension leaves state intact.
update public.accounts set status = 'suspended'
where user_id in (
  'e3300000-0000-4000-8000-000000000005',
  'a3310000-0000-4000-8000-000000000007'
);
update public.accounts set status = 'deactivated'
where user_id in (
  'f3300000-0000-4000-8000-000000000006',
  'b3310000-0000-4000-8000-000000000008'
);

select set_config(
  'my_diary.e3f3_notification_baseline',
  (select pg_catalog.count(*)::text from public.notifications),
  true
);

select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$select public.my_diary_create_user_report(
      'd3300000-0000-4000-8000-000000000004',
      'spam', null, null
    )$$,
  '42501', 'permission denied for function my_diary_create_user_report',
  'authenticated direct execution of the old generic RPC is denied'
);

select is(
  (
    select pg_catalog.count(*)
    from public.follows
    where (follower_id, following_id) in (
      ('a3300000-0000-4000-8000-000000000001'::uuid,
       'b3300000-0000-4000-8000-000000000002'::uuid),
      ('b3300000-0000-4000-8000-000000000002'::uuid,
       'a3300000-0000-4000-8000-000000000001'::uuid)
    )
  ),
  0::bigint,
  'the active-diary report does not depend on current follows'
);

select set_config(
  'my_diary.e3f3_no_related_report',
  public.my_diary_create_exchange_user_report(
    'd3300000-0000-4000-8000-000000000001',
    'harassment', '  normalized detail  ', null
  )::text,
  true
);
select ok(
  current_setting('my_diary.e3f3_no_related_report')::uuid is not null,
  'an active participant creates a user report without supplying a target'
);

reset role;
select results_eq(
  $$select reporter_user_id, target_type, target_id, reported_user_id,
           reason, details
    from public.reports
    where id = current_setting('my_diary.e3f3_no_related_report')::uuid$$,
  $$values (
      'a3300000-0000-4000-8000-000000000001'::uuid,
      'user'::text,
      'b3300000-0000-4000-8000-000000000002'::uuid,
      'b3300000-0000-4000-8000-000000000002'::uuid,
      'harassment'::text,
      'normalized detail'::text
    )$$,
  'the report target is the DB-derived counterpart'
);
select is(
  (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
   where report_id =
     current_setting('my_diary.e3f3_no_related_report')::uuid),
  0::bigint,
  'a report without a related entry has no text snapshot'
);
select is(
  (select pg_catalog.count(*) from public.report_snapshot_images
   where report_id =
     current_setting('my_diary.e3f3_no_related_report')::uuid),
  0::bigint,
  'a report without a related entry has no image snapshot'
);
select is(
  (select pg_catalog.count(*) from public.notifications),
  current_setting('my_diary.e3f3_notification_baseline')::bigint,
  'user report creation emits no notification'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, 'e3300000-0000-4000-8000-000000000001'
    )$$,
  '23505', 'Report could not be created.',
  'a different related entry cannot bypass open-user-report uniqueness'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id =
       'a3300000-0000-4000-8000-000000000001'
     and target_type = 'user'
     and target_id = 'b3300000-0000-4000-8000-000000000002'
     and status in ('pending', 'reviewing')),
  1::bigint,
  'the duplicate attempt leaves one open user report'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, 'e3300000-0000-4000-8000-000000000003'
    )$$,
  '42501', 'Report could not be created.',
  'the same counterpart entry from another diary is rejected'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, 'e3300000-0000-4000-8000-000000000002'
    )$$,
  '42501', 'Report could not be created.',
  'the reporter own entry is rejected as related evidence'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, 'e3300000-0000-4000-8000-000000000004'
    )$$,
  '42501', 'Report could not be created.',
  'a third-party diary entry is rejected as related evidence'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, 'e3300000-0000-4000-8000-000000000005'
    )$$,
  '42501', 'Report could not be created.',
  'a soft-deleted related entry is rejected'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'invalid', null, null
    )$$,
  '22023', 'Invalid report input.',
  'invalid reason validation remains explicit'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'other', '   ', null
    )$$,
  '22023', 'Invalid report input.',
  'other still requires nonblank details'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', repeat('界', 2001), null
    )$$,
  '22023', 'Invalid report input.',
  'details still rejects more than 2000 Unicode codepoints'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id =
       'a3300000-0000-4000-8000-000000000001'
     and target_type = 'user'
     and target_id = 'b3300000-0000-4000-8000-000000000002'),
  1::bigint,
  'related-scope and input failures leave no partial report'
);

select set_config(
  'request.jwt.claim.sub',
  'c3300000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'a third party cannot report a known diary counterpart'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000003',
      'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'a caller cannot derive a target from a foreign diary'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where target_id in (
     'c3300000-0000-4000-8000-000000000003',
     'd3300000-0000-4000-8000-000000000004'
   )),
  0::bigint,
  'third-party and foreign-diary attempts create no user report'
);

-- Successor-created reports retain E3f-1 target/reporter admin COI.
select set_config(
  'request.jwt.claim.sub',
  'b3300000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.reports
   where id = current_setting('my_diary.e3f3_no_related_report')::uuid),
  0::bigint,
  'the reported-user admin cannot read the successor-created report'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e3f3_no_related_report')::uuid,
      'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reported-user admin cannot moderate the successor-created report'
);

reset role;
update public.accounts set role = 'admin'
where user_id = 'a3300000-0000-4000-8000-000000000001';
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.reports
   where id = current_setting('my_diary.e3f3_no_related_report')::uuid),
  0::bigint,
  'the reporter admin cannot read their own successor-created report'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      current_setting('my_diary.e3f3_no_related_report')::uuid,
      'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reporter admin cannot moderate their own successor-created report'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3300000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e3f3_no_related_report')::uuid,
    'dismissed'
  ),
  true,
  'an unrelated active admin can dismiss the successor-created report'
);
reset role;
select is(
  (select status from public.reports
   where id = current_setting('my_diary.e3f3_no_related_report')::uuid),
  'dismissed',
  'the first successor-created user report reaches terminal status'
);

-- Terminal status permits a new report with exact related evidence.
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e3f3_related_report',
  public.my_diary_create_exchange_user_report(
    'd3300000-0000-4000-8000-000000000001',
    'personal_information', null,
    'e3300000-0000-4000-8000-000000000001'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e3f3_related_report')::uuid is not null,
  'a new user report is allowed after terminal status'
);
reset role;
select results_eq(
  $$select target_id, reported_user_id, reporter_user_id
    from public.reports
    where id = current_setting('my_diary.e3f3_related_report')::uuid$$,
  $$values (
      'b3300000-0000-4000-8000-000000000002'::uuid,
      'b3300000-0000-4000-8000-000000000002'::uuid,
      'a3300000-0000-4000-8000-000000000001'::uuid
    )$$,
  'the related report still targets only the derived counterpart'
);
select results_eq(
  $$select body, location_name, tag_names
    from public.report_exchange_entry_snapshots
    where report_id = current_setting('my_diary.e3f3_related_report')::uuid$$,
  $$values (
      'counterpart body'::text,
      'Tokyo'::text,
      array['scope']::text[]
    )$$,
  'the related report captures exact text and tag evidence'
);
select is(
  (select pg_catalog.count(*) from public.report_snapshot_images
   where report_id = current_setting('my_diary.e3f3_related_report')::uuid),
  1::bigint,
  'the related report captures the source image count'
);
select results_eq(
  $$select source_image_id, mime_type, size_bytes, sort_order
    from public.report_snapshot_images
    where report_id = current_setting('my_diary.e3f3_related_report')::uuid$$,
  $$values (
      'f3300000-0000-4000-8000-000000000001'::uuid,
      'image/png'::text, 68::bigint, 0::smallint
    )$$,
  'the related report preserves exact image evidence metadata'
);
select is(
  (select pg_catalog.count(*) from public.notifications),
  current_setting('my_diary.e3f3_notification_baseline')::bigint,
  'related user report creation also emits no notification'
);

select set_config(
  'request.jwt.claim.sub',
  'b3300000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = current_setting('my_diary.e3f3_related_report')::uuid),
      (select pg_catalog.count(*)
       from public.report_exchange_entry_snapshots
       where report_id =
         current_setting('my_diary.e3f3_related_report')::uuid),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id =
         current_setting('my_diary.e3f3_related_report')::uuid)$$,
  $$values (0::bigint, 0::bigint, 0::bigint)$$,
  'the reported-user admin cannot read related snapshot evidence'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select results_eq(
  $$select
      (select pg_catalog.count(*) from public.reports
       where id = current_setting('my_diary.e3f3_related_report')::uuid),
      (select pg_catalog.count(*)
       from public.report_exchange_entry_snapshots
       where report_id =
         current_setting('my_diary.e3f3_related_report')::uuid),
      (select pg_catalog.count(*) from public.report_snapshot_images
       where report_id =
         current_setting('my_diary.e3f3_related_report')::uuid)$$,
  $$values (0::bigint, 0::bigint, 0::bigint)$$,
  'the reporter admin cannot read their related snapshot evidence'
);
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000001',
      'spam', null, null
    )$$,
  '23505', 'Report could not be created.',
  'an open related report also blocks a NULL-related duplicate'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id =
       'a3300000-0000-4000-8000-000000000001'
     and target_id = 'b3300000-0000-4000-8000-000000000002'
     and status in ('pending', 'reviewing')),
  1::bigint,
  'the NULL-related duplicate leaves one open report'
);

select set_config(
  'request.jwt.claim.sub',
  'c3300000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    current_setting('my_diary.e3f3_related_report')::uuid,
    'dismissed'
  ),
  true,
  'the unrelated admin terminates the related report for archive coverage'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e3f3_archived_report',
  public.my_diary_create_exchange_user_report(
    'd3300000-0000-4000-8000-000000000004',
    'spam', null, null
  )::text,
  true
);
select ok(
  current_setting('my_diary.e3f3_archived_report')::uuid is not null,
  'a currently visible archived diary can be reported'
);
reset role;
select is(
  (select target_id from public.reports
   where id = current_setting('my_diary.e3f3_archived_report')::uuid),
  'b3300000-0000-4000-8000-000000000002'::uuid,
  'the archived diary derives the same exact counterpart'
);
select is(
  (select pg_catalog.count(*) from public.report_exchange_entry_snapshots
   where report_id = current_setting('my_diary.e3f3_archived_report')::uuid),
  0::bigint,
  'the archived no-related report has no snapshot'
);

select is(
  (select state from public.exchange_diaries
   where id = 'd3300000-0000-4000-8000-000000000005'),
  'archived',
  'counterpart deactivation archives the diary before reporting'
);
select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e3f3_deactivated_target_report',
  public.my_diary_create_exchange_user_report(
    'd3300000-0000-4000-8000-000000000005',
    'threat_or_danger', null,
    'e3300000-0000-4000-8000-000000000007'
  )::text,
  true
);
select ok(
  current_setting('my_diary.e3f3_deactivated_target_report')::uuid
    is not null,
  'an active viewer can report a deactivated archived counterpart'
);
reset role;
select results_eq(
  $$select target_id, reported_user_id
    from public.reports
    where id =
      current_setting('my_diary.e3f3_deactivated_target_report')::uuid$$,
  $$values (
      'f3300000-0000-4000-8000-000000000006'::uuid,
      'f3300000-0000-4000-8000-000000000006'::uuid
    )$$,
  'the deactivated counterpart identity is still DB-derived'
);
select is(
  (select body from public.report_exchange_entry_snapshots
   where report_id =
     current_setting('my_diary.e3f3_deactivated_target_report')::uuid),
  'deactivated counterpart body',
  'a visible archived related entry remains valid evidence'
);

select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000006',
      'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'a suspended counterpart makes the diary unavailable'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where target_id = 'e3300000-0000-4000-8000-000000000005'),
  0::bigint,
  'suspended-counterpart denial leaves no report'
);

select set_config(
  'request.jwt.claim.sub',
  'a3310000-0000-4000-8000-000000000007', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000007',
      'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'a suspended reporter cannot create a user report'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id = 'a3310000-0000-4000-8000-000000000007'),
  0::bigint,
  'suspended-reporter denial leaves no report'
);

select set_config(
  'request.jwt.claim.sub',
  'b3310000-0000-4000-8000-000000000008', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      'd3300000-0000-4000-8000-000000000008',
      'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'a deactivated reporter cannot create a user report'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id = 'b3310000-0000-4000-8000-000000000008'),
  0::bigint,
  'deactivated-reporter denial leaves no report'
);

select set_config(
  'request.jwt.claim.sub',
  'a3300000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_user_report(
      null, 'spam', null, null
    )$$,
  '42501', 'Report could not be created.',
  'NULL diary scope fails closed'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.notifications),
  current_setting('my_diary.e3f3_notification_baseline')::bigint,
  'all user-report scenarios leave notifications unchanged'
);
select is(
  (select pg_catalog.count(*) from public.reports
   where reporter_user_id =
     'a3300000-0000-4000-8000-000000000001'),
  4::bigint,
  'only the four intended A reports exist after all denial cases'
);
select results_eq(
  $$select
      (select pg_catalog.count(*)
       from public.report_exchange_entry_snapshots),
      (select pg_catalog.count(*) from public.report_snapshot_images)$$,
  $$values (2::bigint, 1::bigint)$$,
  'scope failures leave no partial text or image snapshot'
);

select * from finish();

rollback;
