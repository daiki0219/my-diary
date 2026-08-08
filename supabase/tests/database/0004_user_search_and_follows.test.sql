begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

select has_function(
  'public',
  'my_diary_search_profiles',
  array['text'],
  'The authenticated profile search RPC exists'
);

select ok(
  (
    select function.prosecdef
      and function.provolatile = 's'
      and function.proconfig @> array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
      and function.proargtypes = '25'::oidvector
  ),
  'The search RPC is a hardened stable postgres-owned SECURITY DEFINER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.my_diary_search_profiles(text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.my_diary_search_profiles(text)',
    'EXECUTE'
  ),
  'Only authenticated users can execute the search RPC'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'follows'
      and policyname = 'my_diary_follows_insert_own'
      and cmd = 'INSERT'
  ),
  1::bigint,
  'The expected follows INSERT policy exists once'
);

select ok(
  (
    select with_check like '%my_diary_is_account_active(following_id)%'
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'follows'
      and policyname = 'my_diary_follows_insert_own'
  ),
  'The follows INSERT policy requires the target account to be active'
);

insert into auth.users (id, email)
values
  ('a1000000-0000-4000-8000-000000000001', 'search-a@example.test'),
  ('b1000000-0000-4000-8000-000000000002', 'search-b@example.test'),
  ('c1000000-0000-4000-8000-000000000003', 'search-c@example.test'),
  ('d1000000-0000-4000-8000-000000000004', 'search-d@example.test'),
  ('e1000000-0000-4000-8000-000000000005', 'search-e@example.test');

update public.profiles
set username = case user_id
  when 'a1000000-0000-4000-8000-000000000001' then 'Search Alice'
  when 'b1000000-0000-4000-8000-000000000002' then 'Diary Friend'
  when 'c1000000-0000-4000-8000-000000000003' then 'diary friend'
  when 'd1000000-0000-4000-8000-000000000004' then 'Diary Suspended'
  when 'e1000000-0000-4000-8000-000000000005' then '100%_literal'
end
where user_id in (
  'a1000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000003',
  'd1000000-0000-4000-8000-000000000004',
  'e1000000-0000-4000-8000-000000000005'
);

update public.accounts
set status = 'suspended'
where user_id = 'd1000000-0000-4000-8000-000000000004';

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select * from public.my_diary_search_profiles('Diary')$$,
  '42501',
  null,
  'Anonymous users cannot execute the search RPC'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$select * from public.my_diary_search_profiles('Diary')$$,
  '42501',
  null,
  'The search RPC rejects an authenticated role without a user identity'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select username from public.my_diary_search_profiles('DIARY')$$,
  $$values ('diary friend'::text), ('Diary Friend'::text)$$,
  'Search is a case-insensitive partial match with stable username ordering'
);

select results_eq(
  $$select username from public.my_diary_search_profiles('  friend  ')$$,
  $$values ('diary friend'::text), ('Diary Friend'::text)$$,
  'Search trims surrounding whitespace'
);

select results_eq(
  $$select username from public.my_diary_search_profiles('%')$$,
  $$values ('100%_literal'::text)$$,
  'A percent sign is searched as a literal character'
);

select results_eq(
  $$select username from public.my_diary_search_profiles('_')$$,
  $$values ('100%_literal'::text)$$,
  'An underscore is searched as a literal character'
);

select results_eq(
  $$select username from public.my_diary_search_profiles('Suspended')$$,
  $$select null::text where false$$,
  'A suspended other user is excluded from search'
);

select results_eq(
  $$select user_id from public.my_diary_search_profiles('Search Alice')$$,
  $$values ('a1000000-0000-4000-8000-000000000001'::uuid)$$,
  'The current user can appear in their own search results'
);

select throws_ok(
  $$select * from public.my_diary_search_profiles('   ')$$,
  '22023',
  null,
  'Whitespace-only search is rejected by the RPC'
);

select throws_ok(
  $$select * from public.my_diary_search_profiles(repeat('a', 51))$$,
  '22023',
  null,
  'A 51-character search is rejected by the RPC'
);

select lives_ok(
  $$select * from public.my_diary_search_profiles(repeat('a', 50))$$,
  'A 50-character search is accepted by the RPC'
);

select lives_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002'
    )
  $$,
  'An active user can follow an active target'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000004'
    )
  $$,
  '42501',
  null,
  'An active user cannot follow a suspended target'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'c1000000-0000-4000-8000-000000000003',
      'b1000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  null,
  'A user cannot create a follow in another user name'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'The self-follow RLS check rejects an authenticated self-follow'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002'
    )
  $$,
  '23505',
  null,
  'The duplicate follow primary key remains effective'
);

select lives_ok(
  $$
    delete from public.follows
    where follower_id = 'a1000000-0000-4000-8000-000000000001'
      and following_id = 'b1000000-0000-4000-8000-000000000002'
  $$,
  'A user can delete their own follow'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'c1000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000002'
);

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

delete from public.follows
where follower_id = 'c1000000-0000-4000-8000-000000000003'
  and following_id = 'b1000000-0000-4000-8000-000000000002';

reset role;
select ok(
  exists (
    select 1
    from public.follows
    where follower_id = 'c1000000-0000-4000-8000-000000000003'
      and following_id = 'b1000000-0000-4000-8000-000000000002'
  ),
  'A user cannot delete another user follow'
);

update public.accounts
set status = 'suspended'
where user_id = 'a1000000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$select user_id from public.my_diary_search_profiles('Search Alice')$$,
  '42501',
  null,
  'A suspended current user cannot search their own existing profile'
);

select throws_ok(
  $$select username from public.my_diary_search_profiles('Diary')$$,
  '42501',
  null,
  'A suspended current user cannot search active profiles'
);

select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  null,
  'A suspended user cannot create a follow'
);

select lives_ok(
  $$
    delete from public.follows
    where follower_id = 'a1000000-0000-4000-8000-000000000001'
  $$,
  'A suspended user delete statement is safely rejected without an error'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$select * from public.my_diary_search_profiles('Diary')$$,
  'An active authenticated user can still search after suspended-user checks'
);

reset role;
insert into auth.users (id, email)
select
  gen_random_uuid(),
  format('search-limit-%s@example.test', number)
from generate_series(1, 25) as number;

update public.profiles
set username = format(
  'Search Limit %s',
  row_number
)
from (
  select
    users.id as user_id,
    row_number() over (order by users.email)
  from auth.users as users
  where users.email like 'search-limit-%@example.test'
) as generated
where profiles.user_id = generated.user_id;

select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (
    select count(*)
    from public.my_diary_search_profiles('Search Limit')
  ),
  20::bigint,
  'Search results are limited to 20 profiles'
);

select results_eq(
  $$
    select username
    from public.my_diary_search_profiles('Search Limit')
  $$,
  $$
    select format('Search Limit %s', number)::text
    from generate_series(1, 25) as number
    order by lower(format('Search Limit %s', number)),
      format('Search Limit %s', number)
    limit 20
  $$,
  'The first 20 search results use the documented stable order'
);

select * from finish();

rollback;
