begin;

create extension if not exists pgtap with schema extensions;

select plan(71);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
      and function.pronargs = 1
      and function.proargtypes = '25'::oidvector
  ),
  1::bigint,
  'The tag normalizer has exactly one text overload'
);

select ok(
  (
    select function.prorettype = 'text'::pg_catalog.regtype
      and language.lanname = 'sql'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
      and function.pronargs = 1
  ),
  'The tag normalizer is a SQL function returning text'
);

select ok(
  (
    select pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and not function.prosecdef
      and function.provolatile = 'i'
      and function.proisstrict
      and function.proparallel = 's'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
      and function.pronargs = 1
  ),
  'The tag normalizer has hardened deterministic attributes'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_depend as dependency
    join pg_catalog.pg_proc as function
      on function.oid = dependency.objid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where dependency.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
      and dependency.deptype = 'e'
      and namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
  ),
  0::bigint,
  'The tag normalizer does not belong to an extension'
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
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute the tag normalizer'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_normalize_tag_name(text)',
    'EXECUTE'
  ),
  'anon cannot execute the tag normalizer'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_normalize_tag_name(text)',
    'EXECUTE'
  ),
  'authenticated cannot execute the tag normalizer directly'
);

select ok(
  not pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_normalize_tag_name(text)',
    'EXECUTE'
  ),
  'service_role cannot execute the tag normalizer directly'
);

select ok(
  pg_catalog.has_function_privilege(
    'postgres',
    'my_diary_private.my_diary_normalize_tag_name(text)',
    'EXECUTE'
  ),
  'postgres can execute the tag normalizer'
);

select is(
  my_diary_private.my_diary_normalize_tag_name(
    '  ＃＃ＧＡＭＥ　ＤＥＶ  '
  ),
  'game dev',
  'NFKC, leading hashes, spacing, and ASCII case are normalized'
);

select is(
  my_diary_private.my_diary_normalize_tag_name('  #Game   Dev  '),
  'game dev',
  'ASCII spaces and case are normalized'
);

select is(
  my_diary_private.my_diary_normalize_tag_name('#Café ﬃ ①'),
  'café ffi 1',
  'NFKC composes combining marks and compatibility characters'
);

select is(
  my_diary_private.my_diary_normalize_tag_name(null),
  null,
  'The strict tag normalizer returns null for null'
);

select has_table('public', 'tags', 'tags table exists');
select has_table('public', 'post_tags', 'post_tags table exists');

select is(
  (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.tags'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'id:uuid:t',
    'name:text:t',
    'normalized_name:text:t',
    'created_at:timestamp with time zone:t'
  ]::text[],
  'tags has exactly the expected columns'
);

select is(
  (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.post_tags'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  array[
    'post_id:uuid:t',
    'tag_id:uuid:t',
    'created_at:timestamp with time zone:t'
  ]::text[],
  'post_tags has exactly the expected columns'
);

select col_is_pk('public', 'tags', 'id', 'tags.id is the primary key');

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.tags'::pg_catalog.regclass
      and conname = 'my_diary_tags_normalized_name_key'
      and contype = 'u'
  ),
  'normalized_name is unique'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.tags'::pg_catalog.regclass
      and contype = 'c'
  ),
  4::bigint,
  'tags has exactly four validation constraints'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_pkey'
      and contype = 'p'
      and conkey = array[
        (
          select attnum
          from pg_catalog.pg_attribute
          where attrelid = 'public.post_tags'::pg_catalog.regclass
            and attname = 'post_id'
        ),
        (
          select attnum
          from pg_catalog.pg_attribute
          where attrelid = 'public.post_tags'::pg_catalog.regclass
            and attname = 'tag_id'
        )
      ]::smallint[]
  ),
  'post_tags has a composite post_id and tag_id primary key'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_post_id_fkey'
      and confrelid = 'public.posts'::pg_catalog.regclass
      and confdeltype = 'c'
  ),
  'post_tags.post_id cascades physical post deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_tag_id_fkey'
      and confrelid = 'public.tags'::pg_catalog.regclass
      and confdeltype = 'c'
  ),
  'post_tags.tag_id cascades tag deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_class as index_relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = index_relation.relnamespace
    join pg_catalog.pg_index as index_definition
      on index_definition.indexrelid = index_relation.oid
    where namespace.nspname = 'public'
      and index_relation.relname = 'my_diary_post_tags_tag_post_idx'
      and index_definition.indrelid = 'public.post_tags'::pg_catalog.regclass
      and index_definition.indisvalid
      and index_definition.indisready
      and not index_definition.indisunique
      and index_definition.indpred is null
      and index_definition.indnkeyatts = 2
      and index_definition.indkey[0] = (
        select attnum
        from pg_catalog.pg_attribute
        where attrelid = 'public.post_tags'::pg_catalog.regclass
          and attname = 'tag_id'
      )
      and index_definition.indkey[1] = (
        select attnum
        from pg_catalog.pg_attribute
        where attrelid = 'public.post_tags'::pg_catalog.regclass
          and attname = 'post_id'
      )
  ),
  'post_tags has the exact reverse tag and post lookup index'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.tags'::pg_catalog.regclass
  ),
  'RLS is enabled on tags'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.post_tags'::pg_catalog.regclass
  ),
  'RLS is enabled on post_tags'
);

select ok(
  not (
    select relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.tags'::pg_catalog.regclass
  )
  and not (
    select relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.post_tags'::pg_catalog.regclass
  ),
  'RLS is not forced on the two owner-managed tables'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'tags'
      and policyname = 'my_diary_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  'tags has the authenticated visible-post SELECT policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_tags'
      and policyname = 'my_diary_post_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  'post_tags has the authenticated visible-post SELECT policy'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('tags', 'post_tags')
  ),
  2::bigint,
  'Only the two expected SELECT policies exist'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.tags', 'SELECT'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'SELECT'
  ),
  'authenticated can select tags and post_tags'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.tags', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.tags', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.tags', 'DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'DELETE'
  ),
  'authenticated has no direct tag mutation privileges'
);

select ok(
  not pg_catalog.has_table_privilege('anon', 'public.tags', 'SELECT')
  and not pg_catalog.has_table_privilege(
    'anon', 'public.post_tags', 'SELECT'
  ),
  'anon cannot select tags or post_tags'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as relation
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation.relacl,
        pg_catalog.acldefault('r', relation.relowner)
      )
    ) as privilege
    where relation.oid in (
      'public.tags'::pg_catalog.regclass,
      'public.post_tags'::pg_catalog.regclass
    )
      and privilege.grantee = 0
  ),
  'PUBLIC has no privileges on tags or post_tags'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_trigger
    where tgrelid in (
      'public.tags'::pg_catalog.regclass,
      'public.post_tags'::pg_catalog.regclass
    )
      and not tgisinternal
  ),
  0::bigint,
  'Phase B1 adds no tag mutation or maximum-count trigger'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('GameDev', 'GameDev')
  $$,
  '23514',
  null,
  'Non-canonical ASCII case is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('#gamedev', '#gamedev')
  $$,
  '23514',
  null,
  'A leading hash in stored canonical data is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('game,dev', 'game,dev')
  $$,
  '23514',
  null,
  'A comma is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('game#dev', 'game#dev')
  $$,
  '23514',
  null,
  'An internal hash is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('game' || chr(9) || 'dev', 'game' || chr(9) || 'dev')
  $$,
  '23514',
  null,
  'A tab control character is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('game' || chr(128) || 'dev', 'game' || chr(128) || 'dev')
  $$,
  '23514',
  null,
  'A C1 control character is rejected'
);

select throws_ok(
  $$insert into public.tags (name, normalized_name) values ('', '')$$,
  '23514',
  null,
  'An empty canonical tag is rejected'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values (repeat('あ', 31), repeat('あ', 31))
  $$,
  '23514',
  null,
  'More than 30 Unicode code points are rejected'
);

select lives_ok(
  $$
    insert into public.tags (id, name, normalized_name)
    values (
      '91000000-0000-4000-8000-000000000001',
      repeat('あ', 30),
      repeat('あ', 30)
    )
  $$,
  'Exactly 30 Unicode code points are accepted'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('different', 'names')
  $$,
  '23514',
  null,
  'name and normalized_name must match'
);

insert into public.tags (id, name, normalized_name)
values (
  '91000000-0000-4000-8000-000000000002',
  'café',
  'café'
);

select throws_ok(
  $$
    insert into public.tags (name, normalized_name)
    values ('café', 'café')
  $$,
  '23505',
  null,
  'Canonical duplicate tags are rejected'
);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'tags-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'tags-b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'tags-c@example.test');

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    '92000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A private',
    'A private post',
    'private',
    null
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B public',
    'B public post',
    'public',
    null
  ),
  (
    '92000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B followers',
    'B followers post',
    'followers',
    null
  ),
  (
    '92000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B private',
    'B private post',
    'private',
    null
  ),
  (
    '92000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B deleted',
    'B deleted post',
    'public',
    now()
  ),
  (
    '92000000-0000-4000-8000-000000000006',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B visibility',
    'B visibility post',
    'public',
    null
  ),
  (
    '92000000-0000-4000-8000-000000000007',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'C public',
    'C public post',
    'public',
    null
  );

insert into public.tags (id, name, normalized_name)
values
  ('93000000-0000-4000-8000-000000000001', 'own-tag', 'own-tag'),
  ('93000000-0000-4000-8000-000000000002', 'public-tag', 'public-tag'),
  ('93000000-0000-4000-8000-000000000003', 'followers-tag', 'followers-tag'),
  ('93000000-0000-4000-8000-000000000004', 'private-tag', 'private-tag'),
  ('93000000-0000-4000-8000-000000000005', 'deleted-tag', 'deleted-tag'),
  ('93000000-0000-4000-8000-000000000006', 'visibility-tag', 'visibility-tag'),
  ('93000000-0000-4000-8000-000000000007', 'other-public-tag', 'other-public-tag'),
  ('93000000-0000-4000-8000-000000000008', 'cascade-tag', 'cascade-tag');

insert into public.post_tags (post_id, tag_id)
values
  (
    '92000000-0000-4000-8000-000000000001',
    '93000000-0000-4000-8000-000000000001'
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    '93000000-0000-4000-8000-000000000002'
  ),
  (
    '92000000-0000-4000-8000-000000000003',
    '93000000-0000-4000-8000-000000000003'
  ),
  (
    '92000000-0000-4000-8000-000000000004',
    '93000000-0000-4000-8000-000000000004'
  ),
  (
    '92000000-0000-4000-8000-000000000005',
    '93000000-0000-4000-8000-000000000005'
  ),
  (
    '92000000-0000-4000-8000-000000000006',
    '93000000-0000-4000-8000-000000000006'
  ),
  (
    '92000000-0000-4000-8000-000000000007',
    '93000000-0000-4000-8000-000000000007'
  ),
  (
    '92000000-0000-4000-8000-000000000007',
    '93000000-0000-4000-8000-000000000008'
  );

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.tags$$,
  '42501',
  null,
  'Anonymous users cannot read tags'
);

select throws_ok(
  $$select post_id from public.post_tags$$,
  '42501',
  null,
  'Anonymous users cannot read post_tags'
);

select throws_ok(
  $$insert into public.tags (name, normalized_name) values ('anon', 'anon')$$,
  '42501',
  null,
  'Anonymous users cannot create tags'
);

select throws_ok(
  $$
    insert into public.post_tags (post_id, tag_id)
    values (
      '92000000-0000-4000-8000-000000000002',
      '93000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot create post tag links'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$select name from public.tags order by name$$,
  'Selecting visible tags does not cause RLS recursion'
);

select results_eq(
  $$select name from public.tags order by name$$,
  $$
    values
      ('cascade-tag'::text),
      ('other-public-tag'::text),
      ('own-tag'::text),
      ('public-tag'::text),
      ('visibility-tag'::text)
  $$,
  'A non-follower sees own and public-post tags only'
);

select results_eq(
  $$select tag_id from public.post_tags order by tag_id$$,
  $$
    values
      ('93000000-0000-4000-8000-000000000001'::uuid),
      ('93000000-0000-4000-8000-000000000002'::uuid),
      ('93000000-0000-4000-8000-000000000006'::uuid),
      ('93000000-0000-4000-8000-000000000007'::uuid),
      ('93000000-0000-4000-8000-000000000008'::uuid)
  $$,
  'post_tags exposes links only for posts A can view'
);

select throws_ok(
  $$insert into public.tags (name, normalized_name) values ('direct', 'direct')$$,
  '42501',
  null,
  'authenticated cannot insert tags directly'
);

select throws_ok(
  $$update public.tags set name = name$$,
  '42501',
  null,
  'authenticated cannot update tags directly'
);

select throws_ok(
  $$delete from public.tags$$,
  '42501',
  null,
  'authenticated cannot delete tags directly'
);

select throws_ok(
  $$
    insert into public.post_tags (post_id, tag_id)
    values (
      '92000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  null,
  'authenticated cannot insert post_tags directly'
);

select throws_ok(
  $$update public.post_tags set tag_id = tag_id$$,
  '42501',
  null,
  'authenticated cannot update post_tags directly'
);

select throws_ok(
  $$delete from public.post_tags$$,
  '42501',
  null,
  'authenticated cannot delete post_tags directly'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select name
    from public.tags
    where name in ('followers-tag', 'private-tag', 'deleted-tag')
    order by name
  $$,
  $$values ('followers-tag'::text)$$,
  'A follower sees followers tags but not private or soft-deleted tags'
);

select results_eq(
  $$
    select tag_id
    from public.post_tags
    where tag_id in (
      '93000000-0000-4000-8000-000000000003',
      '93000000-0000-4000-8000-000000000004',
      '93000000-0000-4000-8000-000000000005'
    )
    order by tag_id
  $$,
  $$values ('93000000-0000-4000-8000-000000000003'::uuid)$$,
  'A follower sees only the followers post link among restricted links'
);

reset role;
delete from public.follows
where follower_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and following_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select name from public.tags where name = 'followers-tag'$$,
  $$select null::text where false$$,
  'Unfollowing immediately hides a followers-only tag'
);

reset role;
update public.posts
set visibility = 'private'
where id = '92000000-0000-4000-8000-000000000006';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select name from public.tags where name = 'visibility-tag'$$,
  $$select null::text where false$$,
  'Changing a post to private immediately hides its tag'
);

reset role;
update public.posts
set visibility = 'public'
where id = '92000000-0000-4000-8000-000000000006';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select name from public.tags where name = 'visibility-tag'$$,
  $$values ('visibility-tag'::text)$$,
  'Changing a post back to public restores its tag'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select name
    from public.tags
    where name in ('public-tag', 'followers-tag', 'private-tag')
  $$,
  $$select null::text where false$$,
  'Tags from a suspended author do not leak'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
update public.accounts
set status = 'suspended'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select name from public.tags where name = 'public-tag'$$,
  $$select null::text where false$$,
  'A suspended viewer cannot see another user public tag'
);

select results_eq(
  $$select name from public.tags where name = 'own-tag'$$,
  $$values ('own-tag'::text)$$,
  'A suspended viewer retains the existing own-post visibility behavior'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select throws_ok(
  $$
    insert into public.post_tags (post_id, tag_id)
    values (
      '92000000-0000-4000-8000-000000000002',
      '93000000-0000-4000-8000-000000000002'
    )
  $$,
  '23505',
  null,
  'The composite primary key rejects a duplicate post tag link'
);

insert into public.tags (id, name, normalized_name)
select
  (
    '94000000-0000-4000-8000-'
    || pg_catalog.lpad(series::text, 12, '0')
  )::uuid,
  'limit-tag-' || series,
  'limit-tag-' || series
from generate_series(1, 6) as series;

select lives_ok(
  $$
    insert into public.post_tags (post_id, tag_id)
    select
      '92000000-0000-4000-8000-000000000001'::uuid,
      (
        '94000000-0000-4000-8000-'
        || pg_catalog.lpad(series::text, 12, '0')
      )::uuid
    from generate_series(1, 6) as series
  $$,
  'Phase B1 intentionally does not enforce a maximum of five tags in the DB'
);

delete from public.posts
where id = '92000000-0000-4000-8000-000000000007';

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = '92000000-0000-4000-8000-000000000007'
  ),
  0::bigint,
  'Physical post deletion cascades to post_tags'
);

delete from public.tags
where id = '93000000-0000-4000-8000-000000000001';

select is(
  (
    select count(*)
    from public.post_tags
    where tag_id = '93000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'Physical tag deletion cascades to post_tags'
);

select * from finish();

rollback;
