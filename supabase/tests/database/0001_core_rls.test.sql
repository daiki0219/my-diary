begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'c@example.test');

select is(
  (
    select count(*)
    from public.accounts
    where user_id in (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    )
  ),
  3::bigint,
  'Creating Auth users creates one account for each user'
);

select is(
  (
    select count(*)
    from public.profiles
    where user_id in (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    )
  ),
  3::bigint,
  'Creating Auth users creates one profile for each user'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation
      on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'auth'
      and relation.relname = 'users'
      and trigger.tgname = 'my_diary_on_auth_user_created'
      and not trigger.tgisinternal
  ),
  'The Auth trigger uses the project-specific name'
);

create function public.test_unrelated_auth_trigger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  return new;
end;
$$;

revoke all on function public.test_unrelated_auth_trigger()
  from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.test_unrelated_auth_trigger();

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation
      on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'auth'
      and relation.relname = 'users'
      and trigger.tgname = 'on_auth_user_created'
      and not trigger.tgisinternal
  )
  and exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation
      on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'auth'
      and relation.relname = 'users'
      and trigger.tgname = 'my_diary_on_auth_user_created'
      and not trigger.tgisinternal
  ),
  'An unrelated general Auth trigger can coexist with the project trigger'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where (
      (namespace.nspname = 'public'
        and function.proname in (
          'my_diary_handle_new_auth_user',
          'my_diary_soft_delete_post'
        ))
      or (
        namespace.nspname = 'my_diary_private'
        and function.proname = 'my_diary_is_account_active'
      )
    )
      and function.prosecdef
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
  ),
  3::bigint,
  'All SECURITY DEFINER functions are owned by postgres'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where (
      (namespace.nspname = 'public'
        and function.proname in (
          'my_diary_handle_new_auth_user',
          'my_diary_soft_delete_post'
        ))
      or (
        namespace.nspname = 'my_diary_private'
        and function.proname = 'my_diary_is_account_active'
      )
    )
      and function.proconfig @> array['search_path=""']::text[]
  ),
  3::bigint,
  'All SECURITY DEFINER functions use an empty search_path'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where (
      (namespace.nspname = 'public'
        and function.proname in (
          'my_diary_set_updated_at',
          'my_diary_handle_new_auth_user',
          'my_diary_soft_delete_post'
        ))
      or (
        namespace.nspname = 'my_diary_private'
        and function.proname = 'my_diary_is_account_active'
      )
    )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no EXECUTE privilege on project functions'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_set_updated_at()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_handle_new_auth_user()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_is_account_active(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_soft_delete_post(uuid)',
    'EXECUTE'
  ),
  'anon has no EXECUTE privilege on project functions'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_set_updated_at()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_handle_new_auth_user()',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_is_account_active(uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_soft_delete_post(uuid)',
    'EXECUTE'
  ),
  'authenticated can execute only the two required project functions'
);

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    '10000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'private',
    'A private post',
    'private',
    null
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'public',
    'A public post',
    'public',
    null
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'followers',
    'A followers post',
    'followers',
    null
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'deleted',
    'A deleted post',
    'public',
    now()
  ),
  (
    '10000000-0000-4000-8000-000000000005',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'delete target',
    'A delete target',
    'private',
    null
  ),
  (
    '10000000-0000-4000-8000-000000000006',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'suspended delete target',
    'A suspended delete target',
    'private',
    null
  );

insert into public.follows (follower_id, following_id)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000001'$$,
  $$select null::uuid where false$$,
  'B cannot read A private post'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'Anonymous user cannot read A private post'
);

select throws_ok(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000002'$$,
  '42501',
  null,
  'Anonymous user cannot read A public post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('10000000-0000-4000-8000-000000000002'::uuid)$$,
  'Authenticated B can read A public post'
);

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000003'$$,
  $$values ('10000000-0000-4000-8000-000000000003'::uuid)$$,
  'Follower B can read A followers post'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '23505',
  null,
  'B cannot follow A twice'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000003'$$,
  $$select null::uuid where false$$,
  'Non-follower C cannot read A followers post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

delete from public.follows
where follower_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  and following_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000003'$$,
  $$select null::uuid where false$$,
  'B loses access after unfollowing A'
);

update public.posts
set title = 'changed by B'
where id = '10000000-0000-4000-8000-000000000002';

reset role;
select is(
  (
    select title
    from public.posts
    where id = '10000000-0000-4000-8000-000000000002'
  ),
  'public',
  'B cannot update A post'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    delete from public.posts
    where id = '10000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  null,
  'B cannot physically delete A post'
);

select results_eq(
  $$
    select public.my_diary_soft_delete_post(
      '10000000-0000-4000-8000-000000000002'
    )
  $$,
  $$values (false)$$,
  'B cannot soft-delete A post'
);

reset role;
select ok(
  exists (
    select 1
    from public.posts
    where id = '10000000-0000-4000-8000-000000000002'
  ),
  'B cannot delete A post'
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

update public.posts
set title = 'changed by A'
where id = '10000000-0000-4000-8000-000000000002';

reset role;
select is(
  (
    select title
    from public.posts
    where id = '10000000-0000-4000-8000-000000000002'
  ),
  'changed by A',
  'A can update own post'
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    delete from public.posts
    where id = '10000000-0000-4000-8000-000000000005'
  $$,
  '42501',
  null,
  'A cannot physically delete own post'
);

select results_eq(
  $$
    select public.my_diary_soft_delete_post(
      '10000000-0000-4000-8000-000000000005'
    )
  $$,
  $$values (true)$$,
  'A can soft-delete own post'
);

reset role;
select ok(
  exists (
    select 1
    from public.posts
    where id = '10000000-0000-4000-8000-000000000005'
      and deleted_at is not null
  ),
  'A soft-deleted post remains stored with deleted_at'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.posts (user_id, body, visibility)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'spoofed post',
      'public'
    )
  $$,
  '42501',
  null,
  'B cannot create a post as A'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    )
  $$,
  '42501',
  null,
  'RLS rejects an authenticated self-follow'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '42501',
  null,
  'B cannot create a follows row for C'
);

reset role;
select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '23514',
  null,
  'The database constraint rejects a self-follow'
);

insert into public.follows (follower_id, following_id)
values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

delete from public.follows
where follower_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  and following_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

reset role;
select ok(
  exists (
    select 1
    from public.follows
    where follower_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      and following_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  'B cannot delete C follows row'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    update public.accounts
    set role = 'admin'
    where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  $$,
  '42501',
  null,
  'A general user cannot change role'
);

select throws_ok(
  $$
    update public.accounts
    set status = 'suspended'
    where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  $$,
  '42501',
  null,
  'A general user cannot change status'
);

select results_eq(
  $$
    select user_id
    from public.accounts
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  $$,
  $$select null::uuid where false$$,
  'B cannot read A account fields'
);

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000004'$$,
  $$select null::uuid where false$$,
  'A deleted post is hidden from B'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000004'$$,
  $$select null::uuid where false$$,
  'A deleted post is also hidden from its author'
);

update public.profiles
set username = 'User A'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

reset role;
select is(
  (
    select username
    from public.profiles
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  'User A',
  'A can update own profile'
);

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select user_id
    from public.profiles
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  $$,
  $$values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid)$$,
  'Logged-in B can read A profile'
);

update public.profiles
set username = 'Changed by B'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

reset role;
select is(
  (
    select username
    from public.profiles
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  'User A',
  'B cannot update A profile'
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    update public.accounts
    set timezone = 'UTC'
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  $$,
  'A can update own timezone'
);

reset role;
select is(
  (
    select timezone
    from public.accounts
    where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  'UTC',
  'A timezone update is persisted'
);

update public.accounts
set status = 'suspended'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000002'$$,
  $$select null::uuid where false$$,
  'B cannot read a suspended author public post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('10000000-0000-4000-8000-000000000002'::uuid)$$,
  'Suspended A can still read own non-deleted post'
);

select throws_ok(
  $$
    insert into public.posts (user_id, body, visibility)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'suspended user post',
      'private'
    )
  $$,
  '42501',
  null,
  'Suspended A cannot create a post'
);

select results_eq(
  $$
    update public.posts
    set title = 'changed while suspended'
    where id = '10000000-0000-4000-8000-000000000002'
    returning id
  $$,
  $$select null::uuid where false$$,
  'Suspended A cannot update a post'
);

select results_eq(
  $$
    select public.my_diary_soft_delete_post(
      '10000000-0000-4000-8000-000000000006'
    )
  $$,
  $$values (false)$$,
  'Suspended A cannot soft-delete a post'
);

reset role;

select * from finish();

rollback;
