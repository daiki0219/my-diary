begin;

create extension if not exists pgtap with schema extensions;

select plan(68);

insert into auth.users (id, email)
values
  ('a1000000-0000-4000-8000-000000000001', 'rpc-a@example.test'),
  ('b1000000-0000-4000-8000-000000000002', 'rpc-b@example.test'),
  ('c1000000-0000-4000-8000-000000000003', 'rpc-c@example.test');

update public.accounts
set status = 'suspended'
where user_id = 'c1000000-0000-4000-8000-000000000003';

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_create_post_with_tags'
      and function.proargtypes = '25 25 25 25 1009'::oidvector
  ),
  1::bigint,
  'The create RPC has the exact text/text-array signature'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_update_post_with_tags'
      and function.proargtypes = '2950 25 25 25 25 1009'::oidvector
  ),
  1::bigint,
  'The update RPC has the exact uuid/text/text-array signature'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_tags',
        'my_diary_update_post_with_tags'
      )
  ),
  2::bigint,
  'The post/tag mutation RPCs have no overloads'
);

select ok(
  (
    select function.prorettype = 'uuid'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_create_post_with_tags'
  ),
  'The create RPC is PL/pgSQL and returns uuid'
);

select ok(
  (
    select function.prorettype = 'uuid'::pg_catalog.regtype
      and language.lanname = 'plpgsql'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_update_post_with_tags'
  ),
  'The update RPC is PL/pgSQL and returns uuid'
);

select ok(
  (
    select function.provolatile = 'v'
      and function.prosecdef
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_create_post_with_tags'
  ),
  'The create RPC is VOLATILE SECURITY DEFINER with hardened ownership and search_path'
);

select ok(
  (
    select function.provolatile = 'v'
      and function.prosecdef
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_update_post_with_tags'
  ),
  'The update RPC is VOLATILE SECURITY DEFINER with hardened ownership and search_path'
);

select ok(
  pg_catalog.obj_description(
    'public.my_diary_create_post_with_tags(text,text,text,text,text[])'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null
  and pg_catalog.obj_description(
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null,
  'Both RPCs have database comments'
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
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_tags',
        'my_diary_update_post_with_tags'
      )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute either RPC'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_post_with_tags(text,text,text,text,text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])',
    'EXECUTE'
  ),
  'anon cannot execute either RPC'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_post_with_tags(text,text,text,text,text[])',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])',
    'EXECUTE'
  ),
  'authenticated can execute both RPCs'
);

select ok(
  not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_post_with_tags(text,text,text,text,text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_create_post_with_tags(text,text,text,text,text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])',
    'EXECUTE'
  ),
  'service_role and authenticator cannot execute the RPCs directly'
);

select ok(
  not pg_catalog.has_any_column_privilege(
    'authenticated', 'public.posts', 'INSERT'
  )
  and not pg_catalog.has_any_column_privilege(
    'authenticated', 'public.posts', 'UPDATE'
  ),
  'authenticated has no direct posts INSERT or UPDATE column privilege'
);

select ok(
  pg_catalog.has_table_privilege('authenticated', 'public.posts', 'SELECT')
  and pg_catalog.has_table_privilege('authenticated', 'public.tags', 'SELECT')
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'SELECT'
  ),
  'authenticated retains SELECT on posts, tags, and post_tags'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.tags', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_tags', 'INSERT, UPDATE, DELETE'
  ),
  'tags and post_tags remain direct-mutation closed'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('posts', 'tags', 'post_tags')
  ),
  5::bigint,
  'Existing posts and tag SELECT/mutation policies remain present'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null, 'anonymous', null, 'private', array[]::text[]
    )
  $$,
  '42501',
  null,
  'An unauthenticated caller cannot create a post'
);

select set_config(
  'request.jwt.claim.sub',
  'c1000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null, 'suspended', null, 'private', array[]::text[]
    )
  $$,
  '42501',
  null,
  'A suspended account cannot create a post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config(
  'my_diary.null_tags_post',
  public.my_diary_create_post_with_tags(
    null, ' null tags body ', null, 'private', null::text[]
  )::text,
  true
);

select ok(
  current_setting('my_diary.null_tags_post')::uuid is not null,
  'The create RPC returns a uuid'
);

select is(
  (
    select user_id
    from public.posts
    where id = current_setting('my_diary.null_tags_post')::uuid
  ),
  'a1000000-0000-4000-8000-000000000001'::uuid,
  'The create RPC always uses auth.uid() as the owner'
);

select is(
  (
    select body
    from public.posts
    where id = current_setting('my_diary.null_tags_post')::uuid
  ),
  'null tags body',
  'The create RPC trims and stores a valid body'
);

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = current_setting('my_diary.null_tags_post')::uuid
  ),
  0::bigint,
  'NULL tags creates a post without relations'
);

select set_config(
  'my_diary.empty_tags_post',
  public.my_diary_create_post_with_tags(
    '', 'empty tags body', '', 'private', array[]::text[]
  )::text,
  true
);

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = current_setting('my_diary.empty_tags_post')::uuid
  ),
  0::bigint,
  'An empty tag array creates a post without relations'
);

select set_config(
  'my_diary.five_tags_post',
  public.my_diary_create_post_with_tags(
    'Five tags',
    'five tags body',
    'calm',
    'public',
    array['one', 'two', 'three', 'four', 'five']
  )::text,
  true
);

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  5::bigint,
  'One through five distinct tags are accepted'
);

select set_config(
  'my_diary.twenty_raw_post',
  public.my_diary_create_post_with_tags(
    null,
    'twenty raw tags',
    null,
    'private',
    pg_catalog.array_fill('duplicate'::text, array[20])
  )::text,
  true
);

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = current_setting('my_diary.twenty_raw_post')::uuid
  ),
  1::bigint,
  'Twenty raw elements are accepted when they canonicalize to one tag'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null,
      'twenty one raw tags',
      null,
      'private',
      pg_catalog.array_fill('duplicate'::text, array[21])
    )
  $$,
  '22023',
  null,
  'Twenty-one raw tag elements are rejected before deduplication'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null, 'multidimensional', null, 'private', array[['one', 'two']]
    )
  $$,
  '22023',
  null,
  'A multidimensional tag array is rejected'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null, 'null element', null, 'private', array['one', null]::text[]
    )
  $$,
  '22023',
  null,
  'A NULL tag element is rejected'
);

select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array[''])$$,
  '22023', null, 'An empty tag is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array['   '])$$,
  '22023', null, 'A whitespace-only tag is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array['#'])$$,
  '22023', null, 'A hash-only tag is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array[repeat('あ', 31)])$$,
  '22023', null, 'A tag longer than 30 code points is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array['one,two'])$$,
  '22023', null, 'A tag containing a comma is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array['one#two'])$$,
  '22023', null, 'A canonical tag containing a hash is rejected'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'bad', null, 'private', array[E'one\ntwo'])$$,
  '22023', null, 'A tag containing a control character is rejected'
);

select set_config(
  'my_diary.canonical_post',
  public.my_diary_create_post_with_tags(
    null,
    'canonical tags',
    null,
    'private',
    array[' #Foo ', 'foo', 'ＦＯＯ', '#ＢＡＲ', 'bar']
  )::text,
  true
);

select results_eq(
  $$
    select tag.normalized_name
    from public.tags as tag
    join public.post_tags as relation on relation.tag_id = tag.id
    where relation.post_id = current_setting('my_diary.canonical_post')::uuid
    order by tag.normalized_name
  $$,
  $$values ('bar'::text), ('foo'::text)$$,
  'Case, width, and leading-hash variants canonicalize and deduplicate'
);

select lives_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null,
      'six raw five distinct',
      null,
      'private',
      array['one', 'ONE', 'two', 'three', 'four', 'five']
    )
  $$,
  'Six raw tags are accepted when canonical distinct count is five'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      null,
      'six distinct',
      null,
      'private',
      array['one', 'two', 'three', 'four', 'five', 'six']
    )
  $$,
  '22023',
  null,
  'Six canonical distinct tags are rejected'
);

select lives_ok(
  $$
    select public.my_diary_create_post_with_tags(
      repeat('あ', 120), repeat('い', 10000), 'neutral', 'followers', null
    )
  $$,
  'Create accepts title and body upper boundaries and valid enum values'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(repeat('あ', 121), 'body', null, 'private', null)$$,
  '22023', null, 'Create rejects a title longer than 120 code points'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, E' \n\t ', null, 'private', null)$$,
  '22023', null, 'Create rejects a blank body after trimming'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, repeat('あ', 10001), null, 'private', null)$$,
  '22023', null, 'Create rejects a body longer than 10000 code points'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'body', 'invalid', 'private', null)$$,
  '22023', null, 'Create rejects an invalid mood'
);
select throws_ok(
  $$select public.my_diary_create_post_with_tags(null, 'body', null, 'invalid', null)$$,
  '22023', null, 'Create rejects an invalid visibility'
);

select set_config(
  'my_diary.null_relation_snapshot',
  (
    select pg_catalog.array_agg(
      relation.tag_id::text || ':' || relation.created_at::text
      order by relation.tag_id
    )::text
    from public.post_tags as relation
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  true
);

select results_eq(
  pg_catalog.format(
    $$
      select public.my_diary_update_post_with_tags(
        %L::uuid, 'Updated', 'updated body', 'happy', 'followers', null
      )
    $$,
    current_setting('my_diary.five_tags_post')
  ),
  pg_catalog.format(
    $$values (%L::uuid)$$,
    current_setting('my_diary.five_tags_post')
  ),
  'An owner can update a post and receives its uuid'
);

select is(
  (
    select body
    from public.posts
    where id = current_setting('my_diary.five_tags_post')::uuid
  ),
  'updated body',
  'The update RPC changes post fields'
);

select is(
  (
    select pg_catalog.array_agg(
      relation.tag_id::text || ':' || relation.created_at::text
      order by relation.tag_id
    )::text
    from public.post_tags as relation
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  current_setting('my_diary.null_relation_snapshot'),
  'NULL p_tags leaves every relation and created_at unchanged'
);

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, 'Cleared', 'body', null, 'private', array[]::text[])$$,
    current_setting('my_diary.five_tags_post')
  ),
  'An empty p_tags array is accepted for update'
);

select is(
  (
    select count(*)
    from public.post_tags
    where post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  0::bigint,
  'An empty p_tags array removes every relation'
);

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, 'Set tags', 'body', null, 'private', array['alpha', 'beta', 'gamma'])$$,
    current_setting('my_diary.five_tags_post')
  ),
  'A non-empty p_tags array adds the desired relation set'
);

select set_config(
  'my_diary.beta_created_at',
  (
    select relation.created_at::text
    from public.post_tags as relation
    join public.tags as tag on tag.id = relation.tag_id
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
      and tag.normalized_name = 'beta'
  ),
  true
);

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, 'Replace tags', 'body', null, 'private', array['beta', 'delta'])$$,
    current_setting('my_diary.five_tags_post')
  ),
  'A non-empty p_tags array replaces by differential mutation'
);

select results_eq(
  pg_catalog.format(
    $$
      select tag.normalized_name
      from public.tags as tag
      join public.post_tags as relation on relation.tag_id = tag.id
      where relation.post_id = %L::uuid
      order by tag.normalized_name
    $$,
    current_setting('my_diary.five_tags_post')
  ),
  $$values ('beta'::text), ('delta'::text)$$,
  'Differential update removes old tags and inserts new tags'
);

select is(
  (
    select relation.created_at::text
    from public.post_tags as relation
    join public.tags as tag on tag.id = relation.tag_id
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
      and tag.normalized_name = 'beta'
  ),
  current_setting('my_diary.beta_created_at'),
  'An unchanged relation preserves created_at'
);

reset role;
select ok(
  exists (select 1 from public.tags where normalized_name = 'alpha')
  and exists (select 1 from public.tags where normalized_name = 'gamma'),
  'Unused tag masters are not deleted'
);

select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, null, 'other user', null, 'private', null)$$,
    current_setting('my_diary.five_tags_post')
  ),
  '42501',
  null,
  'Another user cannot update the post'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      'dead0000-0000-4000-8000-000000000000',
      null,
      'missing',
      null,
      'private',
      null
    )
  $$,
  '42501',
  null,
  'A missing post is rejected with the same authorization error'
);

reset role;
update public.posts
set deleted_at = now()
where id = current_setting('my_diary.empty_tags_post')::uuid;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, null, 'deleted', null, 'private', null)$$,
    current_setting('my_diary.empty_tags_post')
  ),
  '42501',
  null,
  'A soft-deleted post is rejected with the same authorization error'
);

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, repeat('あ', 120), repeat('い', 10000), 'neutral', 'public', null)$$,
    current_setting('my_diary.five_tags_post')
  ),
  'Update accepts post input upper boundaries'
);

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, repeat('あ', 121), 'body', null, 'private', null)$$,
    current_setting('my_diary.five_tags_post')
  ),
  '22023', null, 'Update rejects a title longer than 120 code points'
);

reset role;
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
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, null, 'suspended', null, 'private', null)$$,
    current_setting('my_diary.five_tags_post')
  ),
  '42501',
  null,
  'A suspended owner cannot update a post'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a1000000-0000-4000-8000-000000000001';

create function public.test_reject_post_tag_mutation()
returns trigger
language plpgsql
set search_path = ''
as $test_trigger$
begin
  raise exception 'forced post_tags failure';
end;
$test_trigger$;

create trigger test_reject_post_tag_mutation
before insert on public.post_tags
for each row execute function public.test_reject_post_tag_mutation();

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_create_post_with_tags(
      'rollback create',
      'rollback body',
      null,
      'private',
      array['rollback-new', 'beta']
    )
  $$,
  'P0001',
  'forced post_tags failure',
  'A relation failure rolls back the create RPC'
);

reset role;
select ok(
  not exists (select 1 from public.posts where title = 'rollback create'),
  'Create rollback leaves no post'
);
select ok(
  not exists (select 1 from public.tags where normalized_name = 'rollback-new'),
  'Create rollback leaves no newly-created tag master'
);
select ok(
  not exists (
    select 1
    from public.post_tags as relation
    join public.posts as post on post.id = relation.post_id
    where post.title = 'rollback create'
  ),
  'Create rollback leaves no partial relation'
);

select set_config(
  'my_diary.rollback_update_snapshot',
  (
    select pg_catalog.array_agg(tag.normalized_name order by tag.normalized_name)::text
    from public.tags as tag
    join public.post_tags as relation on relation.tag_id = tag.id
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  true
);

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_tags(%L::uuid, 'rollback update', 'rollback update body', null, 'private', array['beta', 'update-new'])$$,
    current_setting('my_diary.five_tags_post')
  ),
  'P0001',
  'forced post_tags failure',
  'A relation failure rolls back the update RPC'
);

reset role;
select isnt(
  (
    select title
    from public.posts
    where id = current_setting('my_diary.five_tags_post')::uuid
  ),
  'rollback update',
  'Update rollback restores the post fields'
);
select is(
  (
    select pg_catalog.array_agg(tag.normalized_name order by tag.normalized_name)::text
    from public.tags as tag
    join public.post_tags as relation on relation.tag_id = tag.id
    where relation.post_id = current_setting('my_diary.five_tags_post')::uuid
  ),
  current_setting('my_diary.rollback_update_snapshot'),
  'Update rollback restores the complete relation set'
);
select ok(
  not exists (select 1 from public.tags where normalized_name = 'update-new')
  and exists (select 1 from public.tags where normalized_name = 'beta'),
  'Update rollback removes the new tag and preserves existing tag masters'
);

select * from finish();

rollback;
