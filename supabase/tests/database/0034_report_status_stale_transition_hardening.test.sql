begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- The CAS successor is the only public overload and has the narrow catalog/ACL.
select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_update_report_status(uuid,text,text)'
  ) is not null
  and pg_catalog.to_regprocedure(
    'public.my_diary_update_report_status(uuid,text)'
  ) is null,
  'the three-argument CAS successor replaces the old two-argument RPC'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname = 'my_diary_update_report_status'
  ),
  1::bigint,
  'the status RPC has exactly one overload'
);

select ok(
  (
    select function_definition.proargnames = array[
             'p_report_id', 'p_expected_status', 'p_status'
           ]::text[]
      and function_definition.proargtypes =
        '2950 25 25'::pg_catalog.oidvector
      and function_definition.prorettype = 'boolean'::pg_catalog.regtype
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) =
        'postgres'
    from pg_catalog.pg_proc as function_definition
    where function_definition.oid =
      'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  ),
  'the successor has exact arguments, return type, owner, and security metadata'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_report_status(uuid,text,text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_report_status(uuid,text,text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_update_report_status(uuid,text,text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_update_report_status(uuid,text,text)', 'EXECUTE'
  )
  and not exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as privilege
    where function_definition.oid =
      'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'only authenticated has explicit application execution of the successor'
);

select ok(
  pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%for update%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%current_status <> p_expected_status%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%report.reported_user_id <> viewer_user_id%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%report.reporter_user_id is null%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.my_diary_update_report_status(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%interval ''30 days''%',
  'the successor locks before CAS and retains COI and retention semantics'
);

insert into auth.users (id, email)
values
  ('a3400000-0000-4000-8000-000000000001', 'e3g1-admin-a@example.test'),
  ('b3400000-0000-4000-8000-000000000002', 'e3g1-admin-b@example.test'),
  ('c3400000-0000-4000-8000-000000000003', 'e3g1-target@example.test'),
  ('d3400000-0000-4000-8000-000000000004', 'e3g1-reporter@example.test'),
  ('e3400000-0000-4000-8000-000000000005', 'e3g1-ordinary@example.test'),
  ('f3400000-0000-4000-8000-000000000006', 'e3g1-suspended@example.test'),
  ('13400000-0000-4000-8000-000000000007', 'e3g1-deactivated@example.test');

update public.accounts
set role = 'admin'
where user_id in (
  'a3400000-0000-4000-8000-000000000001',
  'b3400000-0000-4000-8000-000000000002',
  'f3400000-0000-4000-8000-000000000006',
  '13400000-0000-4000-8000-000000000007'
);
update public.accounts
set status = 'suspended'
where user_id = 'f3400000-0000-4000-8000-000000000006';
update public.accounts
set status = 'deactivated'
where user_id = '13400000-0000-4000-8000-000000000007';

insert into public.reports (
  id, reporter_user_id, target_type, target_id, reported_user_id,
  reason, status
)
values
  ('73400000-0000-4000-8000-000000000001',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000002',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000003',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000004',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000005',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000006',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000008',
   'd3400000-0000-4000-8000-000000000004', 'user',
   'a3400000-0000-4000-8000-000000000001',
   'a3400000-0000-4000-8000-000000000001', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000009',
   'a3400000-0000-4000-8000-000000000001', 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000010',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending'),
  ('73400000-0000-4000-8000-000000000011',
   null, 'user',
   'c3400000-0000-4000-8000-000000000003',
   'c3400000-0000-4000-8000-000000000003', 'spam', 'pending');

select set_config(
  'request.jwt.claim.sub',
  'a3400000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000001',
    'pending', 'reviewing'
  ),
  true,
  'Admin A changes pending to reviewing with matching expected status'
);
select results_eq(
  $$select status, resolved_at, resolved_by, evidence_delete_after
    from public.reports
    where id = '73400000-0000-4000-8000-000000000001'$$,
  $$values (
      'reviewing'::text, null::timestamptz, null::uuid,
      null::timestamptz
    )$$,
  'reviewing keeps all terminal metadata empty'
);

reset role;
alter table public.reports
  disable trigger my_diary_reports_set_updated_at;
update public.reports
set updated_at = '2026-01-02 03:04:05+00'::timestamptz
where id = '73400000-0000-4000-8000-000000000001';
alter table public.reports
  enable trigger my_diary_reports_set_updated_at;

select set_config(
  'request.jwt.claim.sub',
  'b3400000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000001',
    'pending', 'dismissed'
  ),
  false,
  'Admin B stale pending to dismissed intent is rejected'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000001',
    'pending', 'resolved'
  ),
  false,
  'Admin B stale pending to resolved intent is rejected'
);
reset role;
select results_eq(
  $$select status, updated_at, resolved_at, resolved_by,
           evidence_delete_after
    from public.reports
    where id = '73400000-0000-4000-8000-000000000001'$$,
  $$values (
      'reviewing'::text,
      '2026-01-02 03:04:05+00'::timestamptz,
      null::timestamptz, null::uuid, null::timestamptz
    )$$,
  'stale rejection changes no status, timestamp, resolver, or retention field'
);

select set_config(
  'request.jwt.claim.sub',
  'a3400000-0000-4000-8000-000000000001', true
);
set local role authenticated;

select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000002',
    'pending', 'resolved'
  ),
  true,
  'pending transitions directly to resolved'
);
select ok(
  (
    select status = 'resolved'
      and resolved_at is not null
      and resolved_by = 'a3400000-0000-4000-8000-000000000001'::uuid
      and evidence_delete_after = resolved_at + interval '30 days'
    from public.reports
    where id = '73400000-0000-4000-8000-000000000002'
  ),
  'resolved records the admin, terminal timestamp, and 30-day deadline'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000003',
    'pending', 'dismissed'
  ),
  true,
  'pending transitions directly to dismissed'
);
select ok(
  (
    select status = 'dismissed'
      and resolved_at is not null
      and resolved_by = 'a3400000-0000-4000-8000-000000000001'::uuid
      and evidence_delete_after = resolved_at + interval '30 days'
    from public.reports
    where id = '73400000-0000-4000-8000-000000000003'
  ),
  'dismissed preserves the terminal metadata and retention foundation'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000004',
    'pending', 'reviewing'
  ),
  true,
  'a second report transitions pending to reviewing'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000004',
    'reviewing', 'resolved'
  ),
  true,
  'reviewing transitions to resolved'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000005',
    'pending', 'reviewing'
  ),
  true,
  'a third report transitions pending to reviewing'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000005',
    'reviewing', 'dismissed'
  ),
  true,
  'reviewing transitions to dismissed'
);

select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000006',
    'pending', 'reviewing'
  ),
  true,
  'the invalid-transition fixture reaches reviewing'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000006',
      'reviewing', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'same-status transition remains rejected'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000006',
      'reviewing', 'pending'
    )$$,
  '42501', 'Report status could not be updated.',
  'reviewing to pending remains rejected'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000006',
    'reviewing', 'resolved'
  ),
  true,
  'the invalid-transition fixture can still resolve normally'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000006',
      'resolved', 'dismissed'
    )$$,
  '42501', 'Report status could not be updated.',
  'terminal to terminal remains rejected'
);

select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      null, 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'NULL expected status fails closed'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      '', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'blank expected status fails closed'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'unknown', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'unknown expected status fails closed'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73499999-0000-4000-8000-000000000099',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'a nonexistent report remains a generic failure'
);

select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000008',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reported-user admin cannot moderate their report'
);
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000009',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'the reporter admin cannot moderate their report'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b3400000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000008',
    'pending', 'reviewing'
  ),
  true,
  'an unrelated active admin can moderate a target-admin report'
);
select is(
  public.my_diary_update_report_status(
    '73400000-0000-4000-8000-000000000010',
    'pending', 'dismissed'
  ),
  true,
  'an unrelated active admin can moderate a NULL-reporter report'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e3400000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'an ordinary active user cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f3400000-0000-4000-8000-000000000006', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'a suspended admin cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '13400000-0000-4000-8000-000000000007', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'a deactivated admin cannot update report status'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  '23400000-0000-4000-8000-000000000008', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'a caller without an account row cannot update report status'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_report_status(
      '73400000-0000-4000-8000-000000000011',
      'pending', 'reviewing'
    )$$,
  '42501', 'Report status could not be updated.',
  'an unauthenticated caller cannot update report status'
);

reset role;
select is(
  (
    select status
    from public.reports
    where id = '73400000-0000-4000-8000-000000000011'
  ),
  'pending',
  'all invalid-input and account-state failures leave the report unchanged'
);

select * from finish();

rollback;
