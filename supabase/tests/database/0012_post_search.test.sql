begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

-- 01
select has_function(
  'public',
  'my_diary_search_posts',
  array['text', 'timestamp with time zone', 'uuid'],
  'The post search RPC exists with its exact signature'
);

-- 02
select ok(
  (
    select function.prorettype = 'record'::pg_catalog.regtype
      and function.proallargtypes = array[
        'text'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype,
        'uuid'::pg_catalog.regtype,
        'uuid'::pg_catalog.regtype,
        'timestamptz'::pg_catalog.regtype
      ]::oid[]
      and function.proargmodes = array['i', 'i', 'i', 't', 't']::"char"[]
      and function.proargnames = array[
        'search_query', 'before_created_at', 'before_id', 'id', 'created_at'
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
      and function.proname = 'my_diary_search_posts'
      and function.proargtypes = '25 1184 2950'::pg_catalog.oidvector
  ),
  'The post search RPC has the exact arguments, return shape, and attributes'
);

-- 03
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_search_posts'
  ),
  1::bigint,
  'The post search RPC has no overload'
);

-- 04
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_search_posts(text, timestamptz, uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_search_posts(text, timestamptz, uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_search_posts(text, timestamptz, uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_search_posts(text, timestamptz, uuid)',
    'EXECUTE'
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
      and function.proname = 'my_diary_search_posts'
      and function.proargtypes = '25 1184 2950'::pg_catalog.oidvector
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'Only authenticated can execute the post search RPC'
);

-- 05
select ok(
  (
    select relation.relrowsecurity and not relation.relforcerowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.posts'::pg_catalog.regclass
  )
  and (
    select count(*) = 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.posts', 'SELECT'
  )
  and not pg_catalog.has_table_privilege('anon', 'public.posts', 'SELECT'),
  'Post search keeps the existing posts RLS policy and SELECT ACL'
);

insert into auth.users (id, email)
values
  ('a2222222-2222-4222-8222-222222222222', 'post-search-a@example.test'),
  ('b2222222-2222-4222-8222-222222222222', 'post-search-b@example.test'),
  ('c2222222-2222-4222-8222-222222222222', 'post-search-c@example.test'),
  ('d2222222-2222-4222-8222-222222222222', 'post-search-d@example.test');

update public.accounts
set status = 'suspended'
where user_id = 'd2222222-2222-4222-8222-222222222222';

insert into public.posts (
  id, user_id, title, body, visibility, created_at, deleted_at
)
values
  (
    '62222222-2222-4222-8222-000000000001',
    'a2222222-2222-4222-8222-222222222222',
    'Title only title-key', 'body without the title token', 'private',
    '2026-06-01 00:00:01+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000002',
    'a2222222-2222-4222-8222-222222222222',
    null, 'Body only body-key', 'private',
    '2026-06-01 00:00:02+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000003',
    'a2222222-2222-4222-8222-222222222222',
    'or-key in title', 'unrelated', 'private',
    '2026-06-01 00:00:03+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000004',
    'a2222222-2222-4222-8222-222222222222',
    'unrelated', 'or-key in body', 'private',
    '2026-06-01 00:00:04+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000005',
    'a2222222-2222-4222-8222-222222222222',
    'both-key in title', 'both-key in body', 'private',
    '2026-06-01 00:00:05+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000006',
    'a2222222-2222-4222-8222-222222222222',
    'ＣＡＦＥ① and CaseMix', 'width and case fixture', 'private',
    '2026-06-01 00:00:06+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000007',
    'a2222222-2222-4222-8222-222222222222',
    'literal fixture', E'literal % _ \\ , (paren) .dot :colon', 'private',
    '2026-06-01 00:00:07+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000011',
    'a2222222-2222-4222-8222-222222222222',
    'rls-key own public', 'rls-key', 'public',
    '2026-06-02 00:00:01+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000012',
    'a2222222-2222-4222-8222-222222222222',
    'rls-key own followers', 'rls-key', 'followers',
    '2026-06-02 00:00:02+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000013',
    'a2222222-2222-4222-8222-222222222222',
    'rls-key own private', 'rls-key', 'private',
    '2026-06-02 00:00:03+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000021',
    'b2222222-2222-4222-8222-222222222222',
    'rls-key B public', 'rls-key', 'public',
    '2026-06-03 00:00:01+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000022',
    'b2222222-2222-4222-8222-222222222222',
    'rls-key B followers', 'rls-key', 'followers',
    '2026-06-03 00:00:02+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000023',
    'b2222222-2222-4222-8222-222222222222',
    'rls-key B private', 'rls-key', 'private',
    '2026-06-03 00:00:03+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000024',
    'b2222222-2222-4222-8222-222222222222',
    'rls-key B deleted', 'rls-key', 'public',
    '2026-06-03 00:00:04+00', pg_catalog.now()
  ),
  (
    '62222222-2222-4222-8222-000000000025',
    'b2222222-2222-4222-8222-222222222222',
    'rls-key B visibility', 'rls-key', 'public',
    '2026-06-03 00:00:05+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000031',
    'c2222222-2222-4222-8222-222222222222',
    'rls-key C public', 'rls-key', 'public',
    '2026-06-04 00:00:01+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000041',
    'd2222222-2222-4222-8222-222222222222',
    'rls-key D suspended', 'rls-key', 'public',
    '2026-06-05 00:00:01+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000051',
    'a2222222-2222-4222-8222-222222222222',
    'tie-key first', 'tie-key', 'private',
    '2026-06-06 00:00:00.123456+00', null
  ),
  (
    '62222222-2222-4222-8222-000000000052',
    'a2222222-2222-4222-8222-222222222222',
    'tie-key second', 'tie-key', 'private',
    '2026-06-06 00:00:00.123456+00', null
  );

insert into public.posts (
  id, user_id, title, body, visibility, created_at
)
select
  (
    '72222222-2222-4222-8222-'
    || pg_catalog.lpad(series::text, 12, '0')
  )::uuid,
  'a2222222-2222-4222-8222-222222222222'::uuid,
  pg_catalog.format('page-key %s', series),
  'page-key body',
  'private',
  '2026-07-01 00:00:00+00'::timestamptz
    + pg_catalog.make_interval(secs => series)
from pg_catalog.generate_series(1, 23) as series;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

-- 06
select throws_ok(
  $$select * from public.my_diary_search_posts('key', null, null)$$,
  '42501',
  null,
  'Anonymous cannot execute post search'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 07
select throws_ok(
  $$select * from public.my_diary_search_posts('key', null, null)$$,
  '42501',
  null,
  'Post search requires an authenticated identity'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- 08
select throws_ok(
  $$select * from public.my_diary_search_posts(null, null, null)$$,
  '22023',
  null,
  'Post search rejects a null query'
);

-- 09
select throws_ok(
  $$select * from public.my_diary_search_posts('', null, null)$$,
  '22023',
  null,
  'Post search rejects an empty query'
);

-- 10
select throws_ok(
  $$select * from public.my_diary_search_posts('   ', null, null)$$,
  '22023',
  null,
  'Post search rejects a whitespace-only query'
);

-- 11
select lives_ok(
  $$select * from public.my_diary_search_posts(repeat('あ', 50), null, null)$$,
  'Post search accepts 50 Unicode code points'
);

-- 12
select throws_ok(
  $$select * from public.my_diary_search_posts(repeat('あ', 51), null, null)$$,
  '22023',
  null,
  'Post search rejects 51 Unicode code points'
);

-- 13
select throws_ok(
  $$select * from public.my_diary_search_posts('bad' || chr(9), null, null)$$,
  '22023',
  null,
  'Post search rejects control characters'
);

-- 14
select results_eq(
  $$select id from public.my_diary_search_posts('cafe1', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000006'::uuid)$$,
  'Post search NFKC-normalizes full-width compatibility characters'
);

-- 15
select results_eq(
  $$select id from public.my_diary_search_posts('CASEMIX', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000006'::uuid)$$,
  'Post search is ASCII case-insensitive'
);

-- 16
select results_eq(
  $$select id from public.my_diary_search_posts('%', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Percent is a literal post search character'
);

-- 17
select results_eq(
  $$select id from public.my_diary_search_posts('_', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Underscore is a literal post search character'
);

-- 18
select results_eq(
  $$select id from public.my_diary_search_posts(E'\\', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Backslash is a literal post search character'
);

-- 19
select results_eq(
  $$select id from public.my_diary_search_posts(',', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Comma is a literal post search character'
);

-- 20
select results_eq(
  $$select id from public.my_diary_search_posts('(paren)', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Parentheses are literal post search characters'
);

-- 21
select results_eq(
  $$select id from public.my_diary_search_posts('.dot', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Period is a literal post search character'
);

-- 22
select results_eq(
  $$select id from public.my_diary_search_posts(':colon', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000007'::uuid)$$,
  'Colon is a literal post search character'
);

-- 23
select results_eq(
  $$select id from public.my_diary_search_posts('title-key', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000001'::uuid)$$,
  'Post search matches a title substring'
);

-- 24
select results_eq(
  $$select id from public.my_diary_search_posts('body-key', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000002'::uuid)$$,
  'Post search matches a body substring'
);

-- 25
select results_eq(
  $$select id from public.my_diary_search_posts('or-key', null, null)$$,
  $$values
    ('62222222-2222-4222-8222-000000000004'::uuid),
    ('62222222-2222-4222-8222-000000000003'::uuid)$$,
  'Post search combines title and body matching with OR'
);

-- 26
select is(
  (
    select count(*)
    from public.my_diary_search_posts('both-key', null, null)
  ),
  1::bigint,
  'A post matching both title and body is returned once'
);

-- 27
select is_empty(
  $$select id from public.my_diary_search_posts('no-such-post', null, null)$$,
  'Post search returns no rows for no match'
);

-- 28
select throws_ok(
  $$
    select *
    from public.my_diary_search_posts(
      'page-key', '2026-07-01 00:00:10+00', null
    )
  $$,
  '22023',
  null,
  'Post search rejects a cursor timestamp without an id'
);

-- 29
select throws_ok(
  $$
    select *
    from public.my_diary_search_posts(
      'page-key', null, '72222222-2222-4222-8222-000000000010'
    )
  $$,
  '22023',
  null,
  'Post search rejects a cursor id without a timestamp'
);

-- 30
select results_eq(
  $$
    select id
    from public.my_diary_search_posts('rls-key own', null, null)
  $$,
  $$values
    ('62222222-2222-4222-8222-000000000013'::uuid),
    ('62222222-2222-4222-8222-000000000012'::uuid),
    ('62222222-2222-4222-8222-000000000011'::uuid)$$,
  'A viewer can search their own public, followers, and private posts'
);

-- 31
select results_eq(
  $$select id from public.my_diary_search_posts('B public', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000021'::uuid)$$,
  'A non-follower can search another active author public post'
);

-- 32
select is_empty(
  $$
    select id
    from public.my_diary_search_posts('rls-key B', null, null)
    where id in (
      '62222222-2222-4222-8222-000000000022',
      '62222222-2222-4222-8222-000000000023',
      '62222222-2222-4222-8222-000000000024'
    )
  $$,
  'A non-follower cannot search followers, private, or deleted posts'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'a2222222-2222-4222-8222-222222222222',
  'b2222222-2222-4222-8222-222222222222'
);
set local role authenticated;

-- 33
select results_eq(
  $$select id from public.my_diary_search_posts('B followers', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000022'::uuid)$$,
  'A follower can search a followers-only post'
);

reset role;
delete from public.follows
where follower_id = 'a2222222-2222-4222-8222-222222222222'
  and following_id = 'b2222222-2222-4222-8222-222222222222';
set local role authenticated;

-- 34
select is_empty(
  $$select id from public.my_diary_search_posts('B followers', null, null)$$,
  'Unfollowing immediately hides a followers-only post'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'a2222222-2222-4222-8222-222222222222',
  'b2222222-2222-4222-8222-222222222222'
);
set local role authenticated;

-- 35
select results_eq(
  $$select id from public.my_diary_search_posts('B followers', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000022'::uuid)$$,
  'Following again restores a followers-only post'
);

reset role;
update public.posts
set visibility = 'private'
where id = '62222222-2222-4222-8222-000000000025';
set local role authenticated;

-- 36
select is_empty(
  $$select id from public.my_diary_search_posts('B visibility', null, null)$$,
  'Changing public to private immediately hides a post'
);

reset role;
update public.posts
set visibility = 'public'
where id = '62222222-2222-4222-8222-000000000025';
set local role authenticated;

-- 37
select results_eq(
  $$select id from public.my_diary_search_posts('B visibility', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000025'::uuid)$$,
  'Changing private back to public restores a post'
);

-- 38
select is_empty(
  $$select id from public.my_diary_search_posts('B deleted', null, null)$$,
  'A soft-deleted post is not searchable'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'b2222222-2222-4222-8222-222222222222';
set local role authenticated;

-- 39
select is_empty(
  $$select id from public.my_diary_search_posts('B public', null, null)$$,
  'A suspended author public post does not leak through search'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'b2222222-2222-4222-8222-222222222222';
set local role authenticated;

-- 40
select results_eq(
  $$select id from public.my_diary_search_posts('B public', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000021'::uuid)$$,
  'Reactivating an author restores their public post'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'a2222222-2222-4222-8222-222222222222';
set local role authenticated;

-- 41
select is_empty(
  $$select id from public.my_diary_search_posts('B public', null, null)$$,
  'A suspended viewer cannot search another account public post'
);

-- 42
select results_eq(
  $$select id from public.my_diary_search_posts('own private', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000013'::uuid)$$,
  'A suspended viewer retains existing own-post visibility'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a2222222-2222-4222-8222-222222222222';
set local role authenticated;

-- 43
select results_eq(
  $$select id from public.my_diary_search_posts('B public', null, null)$$,
  $$values ('62222222-2222-4222-8222-000000000021'::uuid)$$,
  'Reactivating the viewer restores visible public search results'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-4222-8222-222222222222',
  true
);
set local role authenticated;

-- 44
select results_eq(
  $$select id from public.my_diary_search_posts('rls-key', null, null)$$,
  $$values
    ('62222222-2222-4222-8222-000000000031'::uuid),
    ('62222222-2222-4222-8222-000000000025'::uuid),
    ('62222222-2222-4222-8222-000000000021'::uuid),
    ('62222222-2222-4222-8222-000000000011'::uuid)$$,
  'Search does not leak private, followers-only, deleted, or suspended rows between viewers'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2222222-2222-4222-8222-222222222222',
  true
);
set local role authenticated;

-- 45
select results_eq(
  $$select id from public.my_diary_search_posts('tie-key', null, null)$$,
  $$values
    ('62222222-2222-4222-8222-000000000052'::uuid),
    ('62222222-2222-4222-8222-000000000051'::uuid)$$,
  'Post search orders equal timestamps by id descending'
);

-- 46
select results_eq(
  $$
    select extract(second from created_at)::integer
    from public.my_diary_search_posts('page-key', null, null)
    limit 3
  $$,
  $$values (23), (22), (21)$$,
  'Post search orders results by created_at descending'
);

-- 47
select is(
  (
    select count(*)
    from public.my_diary_search_posts('page-key', null, null)
  ),
  21::bigint,
  'Post search fetches at most 21 rows'
);

-- 48
select results_eq(
  $$
    select id
    from public.my_diary_search_posts(
      'page-key',
      '2026-07-01 00:00:04+00',
      '72222222-2222-4222-8222-000000000004'
    )
  $$,
  $$values
    ('72222222-2222-4222-8222-000000000003'::uuid),
    ('72222222-2222-4222-8222-000000000002'::uuid),
    ('72222222-2222-4222-8222-000000000001'::uuid)$$,
  'A cursor returns only rows strictly older than its boundary'
);

-- 49
select is_empty(
  $$
    with first_page as (
      select id
      from public.my_diary_search_posts('page-key', null, null)
      limit 20
    ), next_page as (
      select id
      from public.my_diary_search_posts(
        'page-key',
        '2026-07-01 00:00:04+00',
        '72222222-2222-4222-8222-000000000004'
      )
    )
    select first_page.id
    from first_page
    join next_page using (id)
  $$,
  'Adjacent post search pages have no duplicate rows'
);

-- 50
select is(
  (
    with first_page as (
      select id
      from public.my_diary_search_posts('page-key', null, null)
      limit 20
    ), next_page as (
      select id
      from public.my_diary_search_posts(
        'page-key',
        '2026-07-01 00:00:04+00',
        '72222222-2222-4222-8222-000000000004'
      )
    )
    select count(*)
    from (
      select id from first_page
      union
      select id from next_page
    ) as complete_pages
  ),
  23::bigint,
  'Adjacent post search pages have no missing rows'
);

-- 51
select is_empty(
  $$
    select id
    from public.my_diary_search_posts(
      'page-key',
      '2026-07-01 00:00:04+00',
      '72222222-2222-4222-8222-000000000004'
    )
    where id = '72222222-2222-4222-8222-000000000004'
  $$,
  'The cursor boundary row is not returned again'
);

-- 52
select results_eq(
  $$
    select id
    from public.my_diary_search_posts(
      'tie-key',
      '2026-06-06 00:00:00.123456+00',
      '62222222-2222-4222-8222-000000000052'
    )
  $$,
  $$values ('62222222-2222-4222-8222-000000000051'::uuid)$$,
  'The id cursor breaks ties without repeating the boundary row'
);

reset role;

select * from finish();

rollback;
