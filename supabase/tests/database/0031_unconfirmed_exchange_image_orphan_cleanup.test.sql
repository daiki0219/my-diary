begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- Catalog, ACL, policy composition, and unchanged retention contracts.
select ok(
  pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'
  ) is not null
  and pg_catalog.to_regprocedure(
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'
  ) is not null
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.pronamespace =
      'public'::pg_catalog.regnamespace
      and function_definition.proname =
        'my_diary_list_due_unconfirmed_exchange_image_orphans'
  ) = 1,
  'unconfirmed orphan maintenance has the exact helper and listing signatures'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid in (
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'::pg_catalog.regprocedure
    )
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  2::bigint,
  'both maintenance functions are postgres-owned hardened SECURITY DEFINER functions'
);

select ok(
  (
    select function_definition.provolatile = 'v'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
  )
  and (
    select function_definition.provolatile = 's'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'::pg_catalog.regprocedure
  ),
  'delete authorization is volatile and advisory listing is stable'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)',
    'EXECUTE'
  ),
  'only authenticated sessions receive the policy/RPC EXECUTE grants'
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
    where function_definition.oid in (
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure,
      'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'::pg_catalog.regprocedure
    )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'PUBLIC cannot execute either maintenance function'
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
  'Exchange images retain the eleven existing operation-specific Storage policies'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and coalesce(qual, '') like
        '%my_diary_exchange_entry_image_maintenance_delete_is_allowed%'
  ),
  4::bigint,
  'the existing maintenance allow policies and restrictive guards use locked final authorization'
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
  'the new path does not add Storage UPDATE or ALL permission'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid =
      'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass
      and conname = 'my_diary_exchange_image_cleanup_candidates_retention_check'
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
  'confirmed seven-day and evidence thirty-day retention remain unchanged'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
    ),
    'FOR UPDATE'
  ) < pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure
    ),
    'public.exchange_entry_images'
  ),
  'final authorization locks the Storage row before reference rechecks'
);

-- Active owner/participant, other participant, admins, and third party.
insert into auth.users (id, email)
values
  ('a3100000-0000-4000-8000-000000000001', 'e3e0b-owner@example.test'),
  ('b3100000-0000-4000-8000-000000000002', 'e3e0b-peer@example.test'),
  ('c3100000-0000-4000-8000-000000000003', 'e3e0b-admin@example.test'),
  ('d3100000-0000-4000-8000-000000000004', 'e3e0b-suspended-admin@example.test'),
  ('e3100000-0000-4000-8000-000000000005', 'e3e0b-deactivated-admin@example.test'),
  ('f3100000-0000-4000-8000-000000000006', 'e3e0b-third@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'c3100000-0000-4000-8000-000000000003',
  'd3100000-0000-4000-8000-000000000004',
  'e3100000-0000-4000-8000-000000000005'
);
update public.accounts set status = 'suspended'
where user_id = 'd3100000-0000-4000-8000-000000000004';
update public.accounts set status = 'deactivated'
where user_id = 'e3100000-0000-4000-8000-000000000005';

insert into public.exchange_diaries
  (id, state, created_by_position, archived_at, archive_cause)
values ('d3100000-0000-4000-8000-000000000001', 'active', 1, null, null);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('13100000-0000-4000-8000-000000000001',
   'd3100000-0000-4000-8000-000000000001', 1,
   'a3100000-0000-4000-8000-000000000001'),
  ('23100000-0000-4000-8000-000000000002',
   'd3100000-0000-4000-8000-000000000001', 2,
   'b3100000-0000-4000-8000-000000000002');

insert into public.exchange_entries
  (id, diary_id, author_participant_id, title, body)
values
  ('e3100000-0000-4000-8000-000000000001',
   'd3100000-0000-4000-8000-000000000001',
   '13100000-0000-4000-8000-000000000001', 'confirmed', 'confirmed body'),
  ('e3100000-0000-4000-8000-000000000002',
   'd3100000-0000-4000-8000-000000000001',
   '13100000-0000-4000-8000-000000000001', 'candidate', 'candidate body');

-- The first three objects exercise the exact age boundary. The rest cover
-- every protected reference, malformed namespace, and bucket/owner spoof.
insert into storage.objects
  (id, bucket_id, name, owner_id, metadata, created_at)
values
  ('93100000-0000-4000-8000-000000000001', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000010/f3100000-0000-4000-8000-000000000010',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '23 hours'),
  ('93100000-0000-4000-8000-000000000002', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000011/f3100000-0000-4000-8000-000000000011',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '24 hours'),
  ('93100000-0000-4000-8000-000000000003', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '25 hours'),
  ('93100000-0000-4000-8000-000000000004', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000001/f3100000-0000-4000-8000-000000000001',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000005', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000002/f3100000-0000-4000-8000-000000000002',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000006', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000020/f3100000-0000-4000-8000-000000000020',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000007', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000021/f3100000-0000-4000-8000-000000000021',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000008', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000022/f3100000-0000-4000-8000-000000000022',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000009', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000023/f3100000-0000-4000-8000-000000000023',
   'a3100000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000010', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000030',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000011', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000031/f3100000-0000-4000-8000-000000000031/a3100000-0000-4000-8000-000000000099',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000012', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/not-a-uuid/e3100000-0000-4000-8000-000000000032/f3100000-0000-4000-8000-000000000032',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000013', 'exchange-entry-images',
   'f3100000-0000-4000-8000-000000000006/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000033/f3100000-0000-4000-8000-000000000033',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000014', 'post-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000034/f3100000-0000-4000-8000-000000000034',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days'),
  ('93100000-0000-4000-8000-000000000015', 'exchange-entry-images',
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000040/f3100000-0000-4000-8000-000000000040',
   'a3100000-0000-4000-8000-000000000001', '{}'::jsonb,
   pg_catalog.statement_timestamp() - interval '2 days');

insert into public.exchange_entry_images
  (id, entry_id, storage_path, sort_order)
values (
  'f3100000-0000-4000-8000-000000000001',
  'e3100000-0000-4000-8000-000000000001',
  'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000001/f3100000-0000-4000-8000-000000000001',
  0
);

insert into my_diary_private.exchange_entry_image_cleanup_candidates (
  storage_object_id, storage_path, image_id, entry_id, diary_id,
  owner_user_id, removed_at, delete_after
)
values (
  '93100000-0000-4000-8000-000000000005',
  'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000002/f3100000-0000-4000-8000-000000000002',
  'f3100000-0000-4000-8000-000000000002',
  'e3100000-0000-4000-8000-000000000002',
  'd3100000-0000-4000-8000-000000000001',
  'a3100000-0000-4000-8000-000000000001',
  pg_catalog.statement_timestamp() - interval '2 days',
  pg_catalog.statement_timestamp() + interval '5 days'
);

insert into public.reports (
  id, reporter_user_id, target_type, target_id, reported_user_id,
  reason, status, resolved_at, resolved_by, evidence_delete_after
)
values
  ('73100000-0000-4000-8000-000000000001',
   'b3100000-0000-4000-8000-000000000002', 'exchange_entry',
   'e3100000-0000-4000-8000-000000000020',
   'a3100000-0000-4000-8000-000000000001', 'harassment',
   'pending', null, null, null),
  ('73100000-0000-4000-8000-000000000002',
   'b3100000-0000-4000-8000-000000000002', 'exchange_entry',
   'e3100000-0000-4000-8000-000000000021',
   'a3100000-0000-4000-8000-000000000001', 'harassment',
   'reviewing', null, null, null),
  ('73100000-0000-4000-8000-000000000003',
   'b3100000-0000-4000-8000-000000000002', 'exchange_entry',
   'e3100000-0000-4000-8000-000000000022',
   'a3100000-0000-4000-8000-000000000001', 'harassment',
   'resolved', pg_catalog.statement_timestamp(),
   'c3100000-0000-4000-8000-000000000003',
   pg_catalog.statement_timestamp() + interval '30 days'),
  ('73100000-0000-4000-8000-000000000004',
   'b3100000-0000-4000-8000-000000000002', 'exchange_entry',
   'e3100000-0000-4000-8000-000000000023',
   'a3100000-0000-4000-8000-000000000001', 'harassment',
   'dismissed', pg_catalog.statement_timestamp() - interval '29 days',
   'c3100000-0000-4000-8000-000000000003',
   pg_catalog.statement_timestamp() + interval '1 day');

insert into public.report_snapshot_images (
  report_id, source_image_id, storage_path, sort_order, mime_type, size_bytes
)
values
  ('73100000-0000-4000-8000-000000000001', null,
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000020/f3100000-0000-4000-8000-000000000020',
   0, 'image/png', 68),
  ('73100000-0000-4000-8000-000000000002', null,
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000021/f3100000-0000-4000-8000-000000000021',
   0, 'image/png', 68),
  ('73100000-0000-4000-8000-000000000003', null,
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000022/f3100000-0000-4000-8000-000000000022',
   0, 'image/png', 68),
  ('73100000-0000-4000-8000-000000000004', null,
   'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000023/f3100000-0000-4000-8000-000000000023',
   0, 'image/png', 68);

select set_config(
  'request.jwt.claim.sub',
  'c3100000-0000-4000-8000-000000000003', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('storage.operation', 'storage.object.delete_many', true);

-- Nested statements in this temporary test helper share the outer SELECT's
-- statement timestamp, making equality an actual 24:00:00 boundary.
create function pg_temp.my_diary_set_orphan_age_and_check(
  p_storage_object_id uuid,
  p_age interval
)
returns boolean
language plpgsql
volatile
as $function$
declare
  target_path text;
begin
  update storage.objects
  set created_at = pg_catalog.statement_timestamp() - p_age
  where id = p_storage_object_id
  returning name into target_path;

  return my_diary_private
    .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
      p_storage_object_id, target_path
    );
end;
$function$;

select is(
  pg_temp.my_diary_set_orphan_age_and_check(
    '93100000-0000-4000-8000-000000000001',
    interval '23 hours 59 minutes 59 seconds'
  ),
  false,
  'an object younger than 24 hours is ineligible'
);

select is(
  pg_temp.my_diary_set_orphan_age_and_check(
    '93100000-0000-4000-8000-000000000002', interval '24 hours'
  ),
  true,
  'an object at the exact 24-hour boundary is eligible'
);

select is(
  pg_temp.my_diary_set_orphan_age_and_check(
    '93100000-0000-4000-8000-000000000003',
    interval '24 hours 1 second'
  ),
  true,
  'an object older than 24 hours is eligible'
);

select ok(
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(100) @>
    array[
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000011/f3100000-0000-4000-8000-000000000011',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000040/f3100000-0000-4000-8000-000000000040'
    ]::text[],
  'active-admin discovery includes every valid old unconfirmed orphan'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000004',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000001/f3100000-0000-4000-8000-000000000001'
  ),
  false,
  'live exchange_entry_images metadata always blocks unconfirmed cleanup'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000005',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000002/f3100000-0000-4000-8000-000000000002'
  ),
  false,
  'an existing seven-day confirmed cleanup candidate never enters the 24-hour path'
);

select is(
  (
    select pg_catalog.count(*)
    from (values
      ('93100000-0000-4000-8000-000000000006'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000020/f3100000-0000-4000-8000-000000000020'::text),
      ('93100000-0000-4000-8000-000000000007'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000021/f3100000-0000-4000-8000-000000000021'::text),
      ('93100000-0000-4000-8000-000000000008'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000022/f3100000-0000-4000-8000-000000000022'::text),
      ('93100000-0000-4000-8000-000000000009'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000023/f3100000-0000-4000-8000-000000000023'::text)
    ) as evidence_object(object_id, storage_path)
    where not my_diary_private
      .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
        evidence_object.object_id, evidence_object.storage_path
      )
  ),
  4::bigint,
  'pending, reviewing, resolved, and dismissed snapshot references all block deletion'
);

select ok(
  not public.my_diary_list_due_unconfirmed_exchange_image_orphans(100) &&
    array[
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000001/f3100000-0000-4000-8000-000000000001',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000002/f3100000-0000-4000-8000-000000000002',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000020/f3100000-0000-4000-8000-000000000020',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000021/f3100000-0000-4000-8000-000000000021',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000022/f3100000-0000-4000-8000-000000000022',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000023/f3100000-0000-4000-8000-000000000023'
    ]::text[],
  'discovery excludes live metadata, candidates, and every evidence state'
);

select is(
  (
    select pg_catalog.count(*)
    from (values
      ('93100000-0000-4000-8000-000000000010'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000030'::text),
      ('93100000-0000-4000-8000-000000000011'::uuid,
       'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000031/f3100000-0000-4000-8000-000000000031/a3100000-0000-4000-8000-000000000099'::text),
      ('93100000-0000-4000-8000-000000000012'::uuid,
       'a3100000-0000-4000-8000-000000000001/not-a-uuid/e3100000-0000-4000-8000-000000000032/f3100000-0000-4000-8000-000000000032'::text)
    ) as malformed(object_id, storage_path)
    where not my_diary_private
      .my_diary_exchange_entry_image_maintenance_delete_is_allowed(
        malformed.object_id, malformed.storage_path
      )
  ),
  3::bigint,
  'three UUID, five UUID, and invalid UUID paths are denied'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000013',
    'f3100000-0000-4000-8000-000000000006/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000033/f3100000-0000-4000-8000-000000000033'
  ),
  false,
  'Storage owner_id must equal the first path UUID'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000014',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000034/f3100000-0000-4000-8000-000000000034'
  ),
  false,
  'a strict path in another bucket is denied'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000011/f3100000-0000-4000-8000-000000000011'
  ),
  false,
  'object id and Storage path must identify the same locked row'
);

select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000099',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000099/f3100000-0000-4000-8000-000000000099'
  ),
  false,
  'a missing Storage object fails closed'
);

select ok(
  not public.my_diary_list_due_unconfirmed_exchange_image_orphans(100) &&
    array[
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000030',
      'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000031/f3100000-0000-4000-8000-000000000031/a3100000-0000-4000-8000-000000000099',
      'a3100000-0000-4000-8000-000000000001/not-a-uuid/e3100000-0000-4000-8000-000000000032/f3100000-0000-4000-8000-000000000032',
      'f3100000-0000-4000-8000-000000000006/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000033/f3100000-0000-4000-8000-000000000033'
    ]::text[],
  'discovery excludes every malformed and owner-spoofed path'
);

select set_config('storage.operation', '', true);
select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012'
  ),
  false,
  'even an active admin needs the exact delete-many operation context'
);

-- Runtime caller matrix. Authenticated receives EXECUTE only so policy/RPC
-- internals can revalidate active-admin state; ordinary callers fail closed.
select set_config(
  'request.jwt.claim.sub',
  'a3100000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(10)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'the participant owner cannot use trusted discovery'
);
select set_config('storage.operation', 'storage.object.delete_many', true);
select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012'
  ),
  false,
  'the participant owner does not gain trusted delete authorization'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_cleanup_is_allowed(
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000010/f3100000-0000-4000-8000-000000000010',
    'a3100000-0000-4000-8000-000000000001'
  ),
  true,
  'the existing participant cleanup path for a recent own orphan remains intact'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3100000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(10)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'a third party cannot use trusted discovery'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012'
  ),
  false,
  'a third party cannot receive trusted delete authorization'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd3100000-0000-4000-8000-000000000004', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(10)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'a suspended admin cannot use trusted discovery'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012'
  ),
  false,
  'a suspended admin cannot receive trusted delete authorization'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e3100000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(10)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'a deactivated admin cannot use trusted discovery'
);
select is(
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    '93100000-0000-4000-8000-000000000003',
    'a3100000-0000-4000-8000-000000000001/d3100000-0000-4000-8000-000000000001/e3100000-0000-4000-8000-000000000012/f3100000-0000-4000-8000-000000000012'
  ),
  false,
  'a deactivated admin cannot receive trusted delete authorization'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3100000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(null)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'trusted discovery rejects a null limit'
);
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(0)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'trusted discovery rejects a zero limit'
);
select throws_ok(
  $$select public.my_diary_list_due_unconfirmed_exchange_image_orphans(101)$$,
  '42501', 'Exchange image maintenance is unavailable.',
  'trusted discovery rejects a limit above 100'
);
select ok(
  pg_catalog.cardinality(
    public.my_diary_list_due_unconfirmed_exchange_image_orphans(100)
  ) >= 3,
  'an active admin can use bounded trusted discovery'
);

select set_config('storage.operation', 'storage.object.delete_many', true);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93100000-0000-4000-8000-000000000015'
  ),
  1::bigint,
  'active-admin delete-many SELECT can see an exact eligible orphan'
);
select set_config('storage.allow_delete_query', 'true', true);
select lives_ok(
  $$delete from storage.objects
    where id = '93100000-0000-4000-8000-000000000015'$$,
  'active-admin Storage DELETE removes the exact eligible orphan'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id = '93100000-0000-4000-8000-000000000015'
  ),
  0::bigint,
  'successful unconfirmed maintenance leaves no physical object'
);
select is(
  (
    select pg_catalog.count(*)
    from storage.objects
    where id in (
      '93100000-0000-4000-8000-000000000004',
      '93100000-0000-4000-8000-000000000005',
      '93100000-0000-4000-8000-000000000006',
      '93100000-0000-4000-8000-000000000007',
      '93100000-0000-4000-8000-000000000008',
      '93100000-0000-4000-8000-000000000009'
    )
  ),
  6::bigint,
  'confirmed, candidate, and all evidence-held bytes remain present'
);
select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entry_images
    where id = 'f3100000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'confirmed live metadata remains present after maintenance'
);
select is(
  (
    select pg_catalog.count(*)
    from my_diary_private.exchange_entry_image_cleanup_candidates
    where storage_object_id = '93100000-0000-4000-8000-000000000005'
  ),
  1::bigint,
  'the existing seven-day cleanup candidate remains present'
);
select is(
  (
    select pg_catalog.count(*)
    from public.report_snapshot_images
    where report_id in (
      '73100000-0000-4000-8000-000000000001',
      '73100000-0000-4000-8000-000000000002',
      '73100000-0000-4000-8000-000000000003',
      '73100000-0000-4000-8000-000000000004'
    )
  ),
  4::bigint,
  'pending, reviewing, and thirty-day terminal evidence rows remain present'
);

select * from finish();

rollback;
