begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'follows'
      and policyname = 'my_diary_follows_select_authenticated'
      and cmd = 'SELECT'
  ),
  1::bigint,
  'The expected follows SELECT policy exists once'
);

select ok(
  (
    select qual like '%my_diary_is_account_active%auth.uid%'
      and qual like '%my_diary_is_account_active(follower_id)%'
      and qual like '%my_diary_is_account_active(following_id)%'
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'follows'
      and policyname = 'my_diary_follows_select_authenticated'
  ),
  'The follows SELECT policy checks the viewer and both relationship users'
);

select has_index(
  'public',
  'follows',
  'my_diary_follows_follower_created_following_idx',
  'The following-list ordering index exists'
);

select has_index(
  'public',
  'follows',
  'my_diary_follows_following_created_follower_idx',
  'The follower-list ordering index exists'
);

insert into auth.users (id, email)
values
  ('a8000000-0000-4000-8000-000000000001', 'follow-list-a@example.test'),
  ('b8000000-0000-4000-8000-000000000002', 'follow-list-b@example.test'),
  ('c8000000-0000-4000-8000-000000000003', 'follow-list-c@example.test'),
  ('d8000000-0000-4000-8000-000000000004', 'follow-list-d@example.test'),
  ('e8000000-0000-4000-8000-000000000005', 'follow-list-e@example.test'),
  ('f8000000-0000-4000-8000-000000000006', 'follow-list-f@example.test'),
  ('f8000000-0000-4000-8000-000000000007', 'follow-list-g@example.test');

insert into public.follows (follower_id, following_id, created_at)
values
  (
    'a8000000-0000-4000-8000-000000000001',
    'b8000000-0000-4000-8000-000000000002',
    '2026-08-01 00:03:00+00'
  ),
  (
    'a8000000-0000-4000-8000-000000000001',
    'c8000000-0000-4000-8000-000000000003',
    '2026-08-01 00:02:00+00'
  ),
  (
    'a8000000-0000-4000-8000-000000000001',
    'd8000000-0000-4000-8000-000000000004',
    '2026-08-01 00:02:00+00'
  ),
  (
    'f8000000-0000-4000-8000-000000000007',
    'b8000000-0000-4000-8000-000000000002',
    '2026-08-01 00:03:00+00'
  ),
  (
    'b8000000-0000-4000-8000-000000000002',
    'a8000000-0000-4000-8000-000000000001',
    '2026-08-01 00:04:00+00'
  ),
  (
    'e8000000-0000-4000-8000-000000000005',
    'a8000000-0000-4000-8000-000000000001',
    '2026-08-01 00:05:00+00'
  ),
  (
    'a8000000-0000-4000-8000-000000000001',
    'e8000000-0000-4000-8000-000000000005',
    '2026-08-01 00:06:00+00'
  ),
  (
    'f8000000-0000-4000-8000-000000000006',
    'b8000000-0000-4000-8000-000000000002',
    '2026-08-01 00:07:00+00'
  );

update public.accounts
set status = 'suspended'
where user_id in (
  'e8000000-0000-4000-8000-000000000005',
  'f8000000-0000-4000-8000-000000000006'
);

select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select follower_id, following_id
    from public.follows
    where follower_id in (
        'a8000000-0000-4000-8000-000000000001',
        'b8000000-0000-4000-8000-000000000002',
        'c8000000-0000-4000-8000-000000000003',
        'd8000000-0000-4000-8000-000000000004',
        'e8000000-0000-4000-8000-000000000005',
        'f8000000-0000-4000-8000-000000000006',
        'f8000000-0000-4000-8000-000000000007'
      )
      and following_id in (
        'a8000000-0000-4000-8000-000000000001',
        'b8000000-0000-4000-8000-000000000002',
        'c8000000-0000-4000-8000-000000000003',
        'd8000000-0000-4000-8000-000000000004',
        'e8000000-0000-4000-8000-000000000005',
        'f8000000-0000-4000-8000-000000000006',
        'f8000000-0000-4000-8000-000000000007'
      )
    order by follower_id, following_id
  $$,
  $$
    values
      (
        'a8000000-0000-4000-8000-000000000001'::uuid,
        'b8000000-0000-4000-8000-000000000002'::uuid
      ),
      (
        'a8000000-0000-4000-8000-000000000001'::uuid,
        'c8000000-0000-4000-8000-000000000003'::uuid
      ),
      (
        'a8000000-0000-4000-8000-000000000001'::uuid,
        'd8000000-0000-4000-8000-000000000004'::uuid
      ),
      (
        'b8000000-0000-4000-8000-000000000002'::uuid,
        'a8000000-0000-4000-8000-000000000001'::uuid
      ),
      (
        'f8000000-0000-4000-8000-000000000007'::uuid,
        'b8000000-0000-4000-8000-000000000002'::uuid
      )
  $$,
  'An active viewer sees active-to-active follow relationships'
);

select results_eq(
  $$
    select following_id
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
    order by created_at desc, following_id desc
  $$,
  $$
    values
      ('b8000000-0000-4000-8000-000000000002'::uuid),
      ('d8000000-0000-4000-8000-000000000004'::uuid),
      ('c8000000-0000-4000-8000-000000000003'::uuid)
  $$,
  'A following list uses created_at and following_id descending order'
);

select results_eq(
  $$
    select follower_id
    from public.follows
    where following_id = 'b8000000-0000-4000-8000-000000000002'
    order by created_at desc, follower_id desc
  $$,
  $$
    values
      ('f8000000-0000-4000-8000-000000000007'::uuid),
      ('a8000000-0000-4000-8000-000000000001'::uuid)
  $$,
  'A follower list uses created_at and follower_id descending order'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000006',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select count(*) from public.follows),
  0::bigint,
  'A suspended viewer cannot read follow relationships'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select follower_id
    from public.follows
    where follower_id = 'e8000000-0000-4000-8000-000000000005'
  $$,
  $$select null::uuid where false$$,
  'A relationship with a suspended follower is hidden'
);

select results_eq(
  $$
    select following_id
    from public.follows
    where following_id = 'e8000000-0000-4000-8000-000000000005'
  $$,
  $$select null::uuid where false$$,
  'A relationship with a suspended following user is hidden'
);

select is(
  (
    select count(*)
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
  ),
  3::bigint,
  'Suspended relationships do not hide the target active relationships'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'e8000000-0000-4000-8000-000000000005';

select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (
    select count(*)
    from public.follows
    where follower_id = 'e8000000-0000-4000-8000-000000000005'
      or following_id = 'e8000000-0000-4000-8000-000000000005'
  ),
  2::bigint,
  'Existing relationships reappear when a suspended user becomes active'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'a8000000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (
    select count(*)
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'A suspended list target has an empty following list'
);

select is(
  (
    select count(*)
    from public.follows
    where following_id = 'a8000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'A suspended list target has an empty follower list'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a8000000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (
    select count(*)
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
  ),
  4::bigint,
  'The target following list returns when the target becomes active'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a8000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a8000000-0000-4000-8000-000000000001',
      'a8000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'The existing self-follow prohibition remains effective'
);

select lives_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a8000000-0000-4000-8000-000000000001',
      'f8000000-0000-4000-8000-000000000007'
    )
  $$,
  'An active user can still insert their own follow'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'b8000000-0000-4000-8000-000000000002',
      'd8000000-0000-4000-8000-000000000004'
    )
  $$,
  '42501',
  null,
  'A user still cannot insert a follow for another follower'
);

select lives_ok(
  $$
    delete from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
      and following_id in (
        'c8000000-0000-4000-8000-000000000003',
        'f8000000-0000-4000-8000-000000000007'
      )
  $$,
  'An active user can still delete their own follows'
);

select results_eq(
  $$
    select following_id
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
      and following_id in (
        'c8000000-0000-4000-8000-000000000003',
        'f8000000-0000-4000-8000-000000000007'
      )
  $$,
  $$select null::uuid where false$$,
  'Deleted own relationships no longer appear'
);

delete from public.follows
where follower_id = 'f8000000-0000-4000-8000-000000000007'
  and following_id = 'b8000000-0000-4000-8000-000000000002';

reset role;

select ok(
  exists (
    select 1
    from public.follows
    where follower_id = 'f8000000-0000-4000-8000-000000000007'
      and following_id = 'b8000000-0000-4000-8000-000000000002'
  ),
  'A user still cannot delete another user follow'
);

select set_config(
  'request.jwt.claim.sub',
  'f8000000-0000-4000-8000-000000000007',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select following_id
    from public.follows
    where follower_id = 'a8000000-0000-4000-8000-000000000001'
    order by created_at desc, following_id desc
  $$,
  $$
    values
      ('e8000000-0000-4000-8000-000000000005'::uuid),
      ('b8000000-0000-4000-8000-000000000002'::uuid),
      ('d8000000-0000-4000-8000-000000000004'::uuid)
  $$,
  'A filtered following list excludes removed and unrelated relationships'
);

reset role;

select * from finish();

rollback;
