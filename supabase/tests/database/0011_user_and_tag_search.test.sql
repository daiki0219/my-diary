begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- 01
select has_function(
  'public',
  'my_diary_search_profiles',
  array['text'],
  'The profile search RPC keeps its exact signature'
);

-- 02
select ok(
  (
    select function.proallargtypes = array[
        'text'::pg_catalog.regtype,
        'uuid'::pg_catalog.regtype,
        'text'::pg_catalog.regtype,
        'text'::pg_catalog.regtype
      ]::oid[]
      and function.proargmodes = array['i', 't', 't', 't']::"char"[]
      and function.proargnames = array[
        'search_query', 'user_id', 'username', 'bio'
      ]::text[]
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.prosecdef
      and function.provolatile = 's'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
      and function.proargtypes = '25'::pg_catalog.oidvector
  ),
  'The profile search return shape and hardened attributes are unchanged'
);

-- 03
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
  ),
  1::bigint,
  'The profile search RPC has no overload'
);

-- 04
select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.my_diary_search_profiles(text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'public.my_diary_search_profiles(text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role', 'public.my_diary_search_profiles(text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator', 'public.my_diary_search_profiles(text)', 'EXECUTE'
  )
  and not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(function.proacl, pg_catalog.acldefault('f', function.proowner))
    ) as privilege
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_profiles'
      and function.proargtypes = '25'::pg_catalog.oidvector
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'Only authenticated can execute the profile search RPC'
);

-- 05
select has_function(
  'my_diary_private',
  'my_diary_normalize_tag_search_query',
  array['text'],
  'The private tag search normalizer exists'
);

-- 06
select ok(
  (
    select function.prorettype = 'text'::pg_catalog.regtype
      and language.lanname = 'sql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and not function.prosecdef
      and function.provolatile = 'i'
      and function.proisstrict
      and function.proparallel = 's'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_search_query'
      and function.proargtypes = '25'::pg_catalog.oidvector
  ),
  'The tag search normalizer has hardened deterministic attributes'
);

-- 07
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_search_query'
  ),
  1::bigint,
  'The tag search normalizer has no overload'
);

-- 08
select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_normalize_tag_search_query(text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_normalize_tag_search_query(text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_normalize_tag_search_query(text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_normalize_tag_search_query(text)',
    'EXECUTE'
  ),
  'Application roles cannot execute the private tag search normalizer'
);

-- 09
select results_eq(
  $$
    select
      my_diary_private.my_diary_normalize_tag_search_query(raw_value)
    from unnest(array[
      '  ＃＃ＧＡＭＥ　ＤＥＶ  ',
      '#Café ﬃ ①',
      ' space   tag '
    ]) as input(raw_value)
  $$,
  $$
    select my_diary_private.my_diary_normalize_tag_name(raw_value)
    from unnest(array[
      '  ＃＃ＧＡＭＥ　ＤＥＶ  ',
      '#Café ﬃ ①',
      ' space   tag '
    ]) as input(raw_value)
  $$,
  'Search and storage tag normalizers agree for known inputs'
);

-- 10
select has_function(
  'public',
  'my_diary_search_tags',
  array['text', 'text'],
  'The tag search RPC exists with its exact signature'
);

-- 11
select ok(
  (
    select function.proallargtypes = array[
        'text'::pg_catalog.regtype,
        'text'::pg_catalog.regtype,
        'uuid'::pg_catalog.regtype,
        'text'::pg_catalog.regtype,
        'text'::pg_catalog.regtype
      ]::oid[]
      and function.proargmodes = array['i', 'i', 't', 't', 't']::"char"[]
      and function.proargnames = array[
        'search_query', 'after_normalized_name',
        'id', 'name', 'normalized_name'
      ]::text[]
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and not function.prosecdef
      and function.provolatile = 's'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_tags'
      and function.proargtypes = '25 25'::pg_catalog.oidvector
  ),
  'The tag search RPC has the exact return shape and hardened attributes'
);

-- 12
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_tags'
  ),
  1::bigint,
  'The tag search RPC has no overload'
);

-- 13
select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.my_diary_search_tags(text, text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'public.my_diary_search_tags(text, text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role', 'public.my_diary_search_tags(text, text)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator', 'public.my_diary_search_tags(text, text)', 'EXECUTE'
  )
  and not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(function.proacl, pg_catalog.acldefault('f', function.proowner))
    ) as privilege
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_tags'
      and function.proargtypes = '25 25'::pg_catalog.oidvector
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'Only authenticated can execute the tag search RPC'
);

insert into auth.users (id, email)
values
  ('a1111111-1111-4111-8111-111111111111', 'search2-a@example.test'),
  ('b1111111-1111-4111-8111-111111111111', 'search2-b@example.test'),
  ('c1111111-1111-4111-8111-111111111111', 'search2-c@example.test'),
  ('d1111111-1111-4111-8111-111111111111', 'search2-d@example.test'),
  ('e1111111-1111-4111-8111-111111111111', 'search2-e@example.test'),
  ('f1111111-1111-4111-8111-111111111111', 'search2-f@example.test'),
  ('01111111-1111-4111-8111-111111111111', 'search2-zero@example.test');

update public.profiles
set username = case user_id
  when 'a1111111-1111-4111-8111-111111111111' then 'Search Alice'
  when 'b1111111-1111-4111-8111-111111111111' then 'Diary Friend'
  when 'c1111111-1111-4111-8111-111111111111' then 'diary friend'
  when 'd1111111-1111-4111-8111-111111111111' then 'ABC123'
  when 'e1111111-1111-4111-8111-111111111111' then 'ＣＡＦＥ①'
  when 'f1111111-1111-4111-8111-111111111111' then E'100%_literal\\path'
  when '01111111-1111-4111-8111-111111111111' then 'Suspended Search'
end
where user_id in (
  'a1111111-1111-4111-8111-111111111111',
  'b1111111-1111-4111-8111-111111111111',
  'c1111111-1111-4111-8111-111111111111',
  'd1111111-1111-4111-8111-111111111111',
  'e1111111-1111-4111-8111-111111111111',
  'f1111111-1111-4111-8111-111111111111',
  '01111111-1111-4111-8111-111111111111'
);

update public.accounts
set status = 'suspended'
where user_id = '01111111-1111-4111-8111-111111111111';

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

-- 14
select throws_ok(
  $$select * from public.my_diary_search_profiles('Diary')$$,
  '42501',
  null,
  'Anonymous cannot execute profile search'
);

-- 15
select throws_ok(
  $$select * from public.my_diary_search_tags('tag', null)$$,
  '42501',
  null,
  'Anonymous cannot execute tag search'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 16
select throws_ok(
  $$select * from public.my_diary_search_profiles('Diary')$$,
  '42501',
  null,
  'Profile search requires an authenticated identity'
);

-- 17
select throws_ok(
  $$select * from public.my_diary_search_tags('tag', null)$$,
  '42501',
  null,
  'Tag search requires an authenticated identity'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 18
select results_eq(
  $$select username from public.my_diary_search_profiles('DIARY')$$,
  $$values ('diary friend'::text), ('Diary Friend'::text)$$,
  'Profile search stays case-insensitive with stable ordering'
);

-- 19
select results_eq(
  $$select username from public.my_diary_search_profiles('  friend  ')$$,
  $$values ('diary friend'::text), ('Diary Friend'::text)$$,
  'Profile search trims surrounding whitespace'
);

-- 20
select results_eq(
  $$select username from public.my_diary_search_profiles('%')$$,
  $$values (E'100%_literal\\path'::text)$$,
  'Percent remains literal in profile search'
);

-- 21
select results_eq(
  $$select username from public.my_diary_search_profiles('_')$$,
  $$values (E'100%_literal\\path'::text)$$,
  'Underscore remains literal in profile search'
);

-- 22
select results_eq(
  $$select username from public.my_diary_search_profiles(E'\\')$$,
  $$values (E'100%_literal\\path'::text)$$,
  'Backslash remains literal in profile search'
);

-- 23
select results_eq(
  $$select username from public.my_diary_search_profiles('Suspended')$$,
  $$select null::text where false$$,
  'Profile search still hides another suspended account'
);

-- 24
select results_eq(
  $$select user_id from public.my_diary_search_profiles('Search Alice')$$,
  $$values ('a1111111-1111-4111-8111-111111111111'::uuid)$$,
  'Profile search still includes the current profile'
);

-- 25
select throws_ok(
  $$select * from public.my_diary_search_profiles('   ')$$,
  '22023',
  null,
  'Profile search rejects an empty canonical query'
);

-- 26
select throws_ok(
  $$select * from public.my_diary_search_profiles(repeat('a', 51))$$,
  '22023',
  null,
  'Profile search rejects 51 Unicode code points'
);

-- 27
select lives_ok(
  $$select * from public.my_diary_search_profiles(repeat('a', 50))$$,
  'Profile search accepts 50 Unicode code points'
);

-- 28
select results_eq(
  $$select username from public.my_diary_search_profiles('ＡＢＣ１２３')$$,
  $$values ('ABC123'::text)$$,
  'Profile search NFKC-normalizes the query'
);

-- 29
select results_eq(
  $$select username from public.my_diary_search_profiles('cafe1')$$,
  $$values ('ＣＡＦＥ①'::text)$$,
  'Profile search NFKC-normalizes the username column'
);

-- 30
select results_eq(
  $$select username from public.my_diary_search_profiles('Ｃａｆｅ①')$$,
  $$values ('ＣＡＦＥ①'::text)$$,
  'NFKC compatibility matching coexists with case-insensitive search'
);

reset role;
insert into auth.users (id, email)
select
  (
    '21111111-1111-4111-8111-'
    || pg_catalog.lpad(series::text, 12, '0')
  )::uuid,
  pg_catalog.format('search2-limit-%s@example.test', series)
from generate_series(1, 25) as series;

update public.profiles
set username = pg_catalog.format(
  'Search Limit %s',
  pg_catalog.replace(
    pg_catalog.split_part(users.email, '@', 1),
    'search2-limit-',
    ''
  )::integer
)
from auth.users as users
where profiles.user_id = users.id
  and users.email like 'search2-limit-%@example.test';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 31
select is(
  (
    select count(*)
    from public.my_diary_search_profiles('Search Limit')
  ),
  20::bigint,
  'Profile search remains limited to 20 rows'
);

-- 32
select results_eq(
  $$select username from public.my_diary_search_profiles('Search Limit')$$,
  $$
    select pg_catalog.format('Search Limit %s', series)::text
    from generate_series(1, 25) as series
    order by
      pg_catalog.lower(pg_catalog.format('Search Limit %s', series)),
      pg_catalog.format('Search Limit %s', series)
    limit 20
  $$,
  'Profile search keeps the documented first-20 ordering'
);

reset role;

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    '31111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'A private', 'A private body', 'private', null
  ),
  (
    '31111111-1111-4111-8111-222222222222',
    'b1111111-1111-4111-8111-111111111111',
    'B public', 'B public body', 'public', null
  ),
  (
    '31111111-1111-4111-8111-333333333333',
    'b1111111-1111-4111-8111-111111111111',
    'B followers', 'B followers body', 'followers', null
  ),
  (
    '31111111-1111-4111-8111-444444444444',
    'b1111111-1111-4111-8111-111111111111',
    'B private', 'B private body', 'private', null
  ),
  (
    '31111111-1111-4111-8111-555555555555',
    'b1111111-1111-4111-8111-111111111111',
    'B deleted', 'B deleted body', 'public', pg_catalog.now()
  ),
  (
    '31111111-1111-4111-8111-666666666666',
    'b1111111-1111-4111-8111-111111111111',
    'B visibility', 'B visibility body', 'public', null
  );

insert into public.tags (id, name, normalized_name)
values
  ('41111111-1111-4111-8111-000000000001', 'abc123', 'abc123'),
  ('41111111-1111-4111-8111-000000000002', 'leading', 'leading'),
  ('41111111-1111-4111-8111-000000000003', '日本語', '日本語'),
  ('41111111-1111-4111-8111-000000000004', '絵文字😀', '絵文字😀'),
  ('41111111-1111-4111-8111-000000000005', 'space tag', 'space tag'),
  ('41111111-1111-4111-8111-000000000006', 'literal-%', 'literal-%'),
  ('41111111-1111-4111-8111-000000000007', 'literal-_', 'literal-_'),
  ('41111111-1111-4111-8111-000000000008', E'literal-\\', E'literal-\\'),
  ('41111111-1111-4111-8111-000000000009', 'literal-*', 'literal-*'),
  ('41111111-1111-4111-8111-000000000010', 'literal-(paren)', 'literal-(paren)'),
  ('41111111-1111-4111-8111-000000000011', 'literal-.dot', 'literal-.dot'),
  ('41111111-1111-4111-8111-000000000012', 'literal-:colon', 'literal-:colon'),
  ('41111111-1111-4111-8111-000000000013', 'literal-?', 'literal-?'),
  ('41111111-1111-4111-8111-000000000014', 'literal-/', 'literal-/'),
  ('41111111-1111-4111-8111-000000000015', 'match', 'match'),
  ('41111111-1111-4111-8111-000000000016', 'match-long', 'match-long'),
  ('41111111-1111-4111-8111-000000000017', 'own-tag', 'own-tag'),
  ('41111111-1111-4111-8111-000000000018', 'public-tag', 'public-tag'),
  ('41111111-1111-4111-8111-000000000019', 'followers-tag', 'followers-tag'),
  ('41111111-1111-4111-8111-000000000020', 'private-tag', 'private-tag'),
  ('41111111-1111-4111-8111-000000000021', 'deleted-tag', 'deleted-tag'),
  ('41111111-1111-4111-8111-000000000022', 'visibility-tag', 'visibility-tag'),
  ('41111111-1111-4111-8111-000000000023', 'relationless', 'relationless');

insert into public.tags (id, name, normalized_name)
select
  (
    '51111111-1111-4111-8111-'
    || pg_catalog.lpad(series::text, 12, '0')
  )::uuid,
  pg_catalog.format('page-%s', pg_catalog.lpad(series::text, 2, '0')),
  pg_catalog.format('page-%s', pg_catalog.lpad(series::text, 2, '0'))
from generate_series(1, 22) as series;

insert into public.post_tags (post_id, tag_id)
select
  '31111111-1111-4111-8111-111111111111'::uuid,
  tags.id
from public.tags
where tags.id between
  '41111111-1111-4111-8111-000000000001'::uuid
  and '41111111-1111-4111-8111-000000000017'::uuid
   or tags.id::text like '51111111-1111-4111-8111-%';

insert into public.post_tags (post_id, tag_id)
values
  (
    '31111111-1111-4111-8111-111111111111',
    '41111111-1111-4111-8111-000000000017'
  ) on conflict do nothing;

insert into public.post_tags (post_id, tag_id)
values
  (
    '31111111-1111-4111-8111-222222222222',
    '41111111-1111-4111-8111-000000000018'
  ),
  (
    '31111111-1111-4111-8111-333333333333',
    '41111111-1111-4111-8111-000000000019'
  ),
  (
    '31111111-1111-4111-8111-444444444444',
    '41111111-1111-4111-8111-000000000020'
  ),
  (
    '31111111-1111-4111-8111-555555555555',
    '41111111-1111-4111-8111-000000000021'
  ),
  (
    '31111111-1111-4111-8111-666666666666',
    '41111111-1111-4111-8111-000000000022'
  );

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 33
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('ＡＢＣ１２３', null)$$,
  $$values ('abc123'::text)$$,
  'Tag search normalizes NFKC, width, and ASCII case'
);

-- 34
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('  ##LEADING  ', null)$$,
  $$values ('leading'::text)$$,
  'Tag search removes leading hashes and surrounding spaces'
);

-- 35
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('日本', null)$$,
  $$values ('日本語'::text)$$,
  'Tag search supports Japanese partial matching'
);

-- 36
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('😀', null)$$,
  $$values ('絵文字😀'::text)$$,
  'Tag search supports emoji'
);

-- 37
select results_eq(
  $$select normalized_name from public.my_diary_search_tags(' space   tag ', null)$$,
  $$values ('space tag'::text)$$,
  'Tag search collapses consecutive ASCII spaces'
);

-- 38
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('%', null)$$,
  $$values ('literal-%'::text)$$,
  'Percent is a literal tag search character rather than all rows'
);

-- 39
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('_', null)$$,
  $$values ('literal-_'::text)$$,
  'Underscore is a literal tag search character'
);

-- 40
select results_eq(
  $$select normalized_name from public.my_diary_search_tags(E'\\', null)$$,
  $$values (E'literal-\\'::text)$$,
  'Backslash is a literal tag search character'
);

-- 41
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('*', null)$$,
  $$values ('literal-*'::text)$$,
  'Asterisk is a literal tag search character'
);

-- 42
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('(', null)$$,
  $$values ('literal-(paren)'::text)$$,
  'Parentheses are literal tag search characters'
);

-- 43
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('.dot', null)$$,
  $$values ('literal-.dot'::text)$$,
  'Dot is a literal tag search character'
);

-- 44
select results_eq(
  $$select normalized_name from public.my_diary_search_tags(':colon', null)$$,
  $$values ('literal-:colon'::text)$$,
  'Colon is a literal tag search character'
);

-- 45
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('?', null)$$,
  $$values ('literal-?'::text)$$,
  'Question mark is a literal tag search character'
);

-- 46
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('/', null)$$,
  $$values ('literal-/'::text)$$,
  'Slash is a literal tag search character'
);

-- 47
select throws_ok(
  $$select * from public.my_diary_search_tags(',', null)$$,
  '22023',
  null,
  'Tag search rejects a comma'
);

-- 48
select throws_ok(
  $$select * from public.my_diary_search_tags('middle#hash', null)$$,
  '22023',
  null,
  'Tag search rejects an internal hash'
);

-- 49
select throws_ok(
  $$select * from public.my_diary_search_tags('bad' || chr(1), null)$$,
  '22023',
  null,
  'Tag search rejects control characters'
);

-- 50
select throws_ok(
  $$select * from public.my_diary_search_tags('bad' || chr(10), null)$$,
  '22023',
  null,
  'Tag search rejects newlines'
);

-- 51
select throws_ok(
  $$select * from public.my_diary_search_tags(repeat('あ', 31), null)$$,
  '22023',
  null,
  'Tag search rejects 31 Unicode code points'
);

-- 52
select throws_ok(
  $$select * from public.my_diary_search_tags(null, null)$$,
  '22023',
  null,
  'Tag search rejects a null search query'
);

-- 53
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('match', null)$$,
  $$values ('match'::text), ('match-long'::text)$$,
  'Tag search returns exact and partial matches'
);

-- 54
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('literal-', null)$$,
  $$
    select normalized_name::text
    from public.tags
    where normalized_name like 'literal-%'
    order by normalized_name
  $$,
  'Tag search orders results by normalized_name ascending'
);

-- 55
select is(
  (
    select count(*)
    from public.my_diary_search_tags('page-', null)
  ),
  21::bigint,
  'Tag search fetches at most 21 rows'
);

-- 56
select results_eq(
  $$
    select normalized_name
    from public.my_diary_search_tags('page-', 'page-20')
  $$,
  $$values ('page-21'::text), ('page-22'::text)$$,
  'Tag search cursor returns rows strictly after normalized_name'
);

-- 57
select results_eq(
  $$
    select normalized_name
    from public.my_diary_search_tags('page-', 'page-21')
  $$,
  $$values ('page-22'::text)$$,
  'Tag search returns the final cursor page'
);

-- 58
select throws_ok(
  $$select * from public.my_diary_search_tags('page-', 'Page-20')$$,
  '22023',
  null,
  'Tag search rejects a non-canonical cursor'
);

-- 59
select throws_ok(
  $$select * from public.my_diary_search_tags('page-', 'page' || chr(9))$$,
  '22023',
  null,
  'Tag search rejects a control character in the cursor'
);

-- 60
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('own-tag', null)$$,
  $$values ('own-tag'::text)$$,
  'A viewer can search a tag on their own private post'
);

-- 61
select results_eq(
  $$
    select normalized_name
    from public.my_diary_search_tags('-tag', null)
    where normalized_name in (
      'public-tag', 'followers-tag', 'private-tag', 'deleted-tag'
    )
  $$,
  $$values ('public-tag'::text)$$,
  'A non-follower sees public but not followers, private, or deleted tags'
);

-- 62
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('relationless', null)$$,
  $$select null::text where false$$,
  'A tag master row without a visible relation is hidden by RLS'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'a1111111-1111-4111-8111-111111111111',
  'b1111111-1111-4111-8111-111111111111'
);

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 63
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('followers-tag', null)$$,
  $$values ('followers-tag'::text)$$,
  'A follower can search a followers-only tag'
);

reset role;
delete from public.follows
where follower_id = 'a1111111-1111-4111-8111-111111111111'
  and following_id = 'b1111111-1111-4111-8111-111111111111';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 64
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('followers-tag', null)$$,
  $$select null::text where false$$,
  'Unfollowing immediately hides a followers-only tag'
);

reset role;
update public.posts
set visibility = 'private'
where id = '31111111-1111-4111-8111-666666666666';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 65
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('visibility-tag', null)$$,
  $$select null::text where false$$,
  'Changing public to private immediately hides the tag'
);

reset role;
update public.posts
set visibility = 'public'
where id = '31111111-1111-4111-8111-666666666666';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 66
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('visibility-tag', null)$$,
  $$values ('visibility-tag'::text)$$,
  'Changing private back to public restores the tag'
);

-- 67
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('deleted-tag', null)$$,
  $$select null::text where false$$,
  'A soft-deleted post tag remains hidden'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'b1111111-1111-4111-8111-111111111111';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 68
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('public-tag', null)$$,
  $$select null::text where false$$,
  'A suspended author tag does not leak through search'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'b1111111-1111-4111-8111-111111111111';
update public.accounts
set status = 'suspended'
where user_id = 'a1111111-1111-4111-8111-111111111111';

select set_config(
  'request.jwt.claim.sub',
  'a1111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 69
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('public-tag', null)$$,
  $$select null::text where false$$,
  'A suspended viewer cannot search another account public tag'
);

-- 70
select results_eq(
  $$select normalized_name from public.my_diary_search_tags('own-tag', null)$$,
  $$values ('own-tag'::text)$$,
  'A suspended viewer retains the existing own-post tag visibility'
);

reset role;

select * from finish();

rollback;
