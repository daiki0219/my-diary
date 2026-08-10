begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])'
  ) is not null,
  'The location-aware create RPC has the exact signature'
);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)'
  ) is not null,
  'The location-aware update RPC has the exact signature'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname =
        'my_diary_create_post_with_images_and_location'
      and function.proargtypes =
        '2950 25 25 25 25 25 1009 1009'::oidvector
      and function.proargnames = array[
        'p_post_id', 'p_title', 'p_body', 'p_mood',
        'p_location_name', 'p_visibility', 'p_tags', 'p_image_paths'
      ]::text[]
      and function.prorettype = 'uuid'::pg_catalog.regtype
      and function.provolatile = 'v'
      and function.prosecdef
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
  ),
  'The create RPC has fixed security attributes and argument names'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    join pg_catalog.pg_language as language
      on language.oid = function.prolang
    where namespace.nspname = 'public'
      and function.proname =
        'my_diary_update_post_with_images_and_location'
      and function.proargtypes =
        '2950 25 25 25 25 25 1009 3802'::oidvector
      and function.proargnames = array[
        'p_post_id', 'p_title', 'p_body', 'p_mood',
        'p_location_name', 'p_visibility', 'p_tags', 'p_image_manifest'
      ]::text[]
      and function.prorettype = 'jsonb'::pg_catalog.regtype
      and function.provolatile = 'v'
      and function.prosecdef
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
  ),
  'The update RPC has fixed security attributes and argument names'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname =
        'my_diary_create_post_with_images_and_location'
  ),
  1::bigint,
  'The create RPC has no unexpected overload'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname =
        'my_diary_update_post_with_images_and_location'
  ),
  1::bigint,
  'The update RPC has no unexpected overload'
);

select ok(
  pg_catalog.obj_description(
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null
  and pg_catalog.obj_description(
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null,
  'Both successor RPCs have catalog comments'
);

select ok(
  not pg_catalog.has_function_privilege(
    'public',
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'public',
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'PUBLIC and anon cannot execute either successor RPC'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_post_with_images_and_location(uuid,text,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_update_post_with_images_and_location(uuid,text,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'Only authenticated receives successor EXECUTE among application roles'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.posts', 'INSERT, UPDATE'
  ),
  'Direct authenticated posts mutation remains closed'
);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
  ) is not null
  and pg_catalog.to_regprocedure(
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'
  ) is not null,
  'Both Application predecessor RPC signatures remain available'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
  ),
  3::bigint,
  'The existing posts RLS policy count is unchanged'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.unnest(function.proargnames)
      as argument(name)
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_images_and_location',
        'my_diary_update_post_with_images_and_location'
      )
      and argument.name in ('p_user_id', 'user_id')
  ),
  'Neither successor RPC accepts a client supplied user ID'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.posts'::pg_catalog.regclass
      and conname = 'my_diary_posts_location_name_check'
      and contype = 'c'
      and convalidated
  ),
  'The existing location_name CHECK remains validated'
);

insert into auth.users (id, email)
values
  ('a4100000-0000-4000-8000-000000000001', 'c4b-a@example.test'),
  ('b4100000-0000-4000-8000-000000000001', 'c4b-b@example.test'),
  ('c4100000-0000-4000-8000-000000000001', 'c4b-suspended@example.test'),
  ('d4100000-0000-4000-8000-000000000001', 'c4b-deactivated@example.test');

update public.accounts
set status = 'suspended'
where user_id = 'c4100000-0000-4000-8000-000000000001';

update public.accounts
set status = 'deactivated'
where user_id = 'd4100000-0000-4000-8000-000000000001';

insert into public.posts (
  id, user_id, title, body, mood, location_name, visibility, deleted_at
)
values
  (
    'a4100000-0000-4000-8000-000000000010',
    'a4100000-0000-4000-8000-000000000001',
    'Editable', 'Before body', 'neutral', null, 'private', null
  ),
  (
    'a4100000-0000-4000-8000-000000000020',
    'a4100000-0000-4000-8000-000000000001',
    'Deleted', 'Deleted body', null, null, 'private', pg_catalog.now()
  ),
  (
    'b4100000-0000-4000-8000-000000000010',
    'b4100000-0000-4000-8000-000000000001',
    'Other owner', 'Other body', null, null, 'private', null
  ),
  (
    'a4100000-0000-4000-8000-000000000030',
    'a4100000-0000-4000-8000-000000000001',
    'Legacy', 'Legacy body', null, 'Legacy place', 'private', null
  );

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'e4100000-0000-4000-8000-000000000001',
  'post-images',
  'a4100000-0000-4000-8000-000000000001/a4100000-0000-4000-8000-000000000105/e4100000-0000-4000-8000-000000000001',
  'a4100000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  'a4100000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000101', null, 'Null location',
    null, null, 'private', array[]::text[], array[]::text[]
  )$$,
  'An active user can create a post with NULL location_name'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000101'),
  null::text,
  'NULL is stored as NULL'
);

select lives_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000100', null, 'Empty location',
    null, '', 'private', array[]::text[], array[]::text[]
  )$$,
  'An empty location_name is accepted'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000100'),
  null::text,
  'An empty location_name is normalized to NULL'
);

select lives_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000102', null, 'Whitespace location',
    null, E' \t\n ', 'private', array[]::text[], array[]::text[]
  )$$,
  'Whitespace-only location_name is accepted'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000102'),
  null::text,
  'Whitespace-only location_name is normalized to NULL'
);

select lives_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000103', null, 'Trim location',
    null, '  東京駅  ', 'private', array['trip'], array[]::text[]
  )$$,
  'A valid location_name can be created with tags'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000103'),
  '東京駅'::text,
  'location_name is trimmed before storage'
);

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_create_post_with_images_and_location(
      'a4100000-0000-4000-8000-000000000104', null, '100 location',
      null, %L, 'private', array[]::text[], array[]::text[]
    )$$,
    pg_catalog.repeat('あ', 100)
  ),
  'A 100-codepoint location_name is accepted'
);

select is(
  (select pg_catalog.char_length(location_name) from public.posts where id =
    'a4100000-0000-4000-8000-000000000104'),
  100,
  'The 100-codepoint location_name is stored intact'
);

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_create_post_with_images_and_location(
      'a4100000-0000-4000-8000-000000000199', null, 'Too long',
      null, %L, 'private', array[]::text[], array[]::text[]
    )$$,
    pg_catalog.repeat('あ', 101)
  ),
  '22023',
  'Invalid location name.',
  'A 101-codepoint location_name is rejected'
);

select is(
  (select pg_catalog.count(*) from public.posts where id =
    'a4100000-0000-4000-8000-000000000199'),
  0::bigint,
  'Location validation failure rolls back post creation'
);

select lives_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000105', null, 'Image location',
    null, '横浜', 'public', array['photo'], array[
      'a4100000-0000-4000-8000-000000000001/a4100000-0000-4000-8000-000000000105/e4100000-0000-4000-8000-000000000001'
    ]::text[]
  )$$,
  'Location, tag, and image metadata can be created atomically'
);

select results_eq(
  $$select
      posts.location_name,
      (select count(*) from public.post_tags where post_id = posts.id),
      (select count(*) from public.post_images where post_id = posts.id)
    from public.posts
    where posts.id = 'a4100000-0000-4000-8000-000000000105'$$,
  $$values ('横浜'::text, 1::bigint, 1::bigint)$$,
  'The atomic create stores location, one tag, and one image'
);

select lives_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000010', 'Updated', 'Updated body',
    'happy', '  渋谷  ', 'public', array['updated'], '[]'::jsonb
  )$$,
  'An owned post can be updated to a valid location_name'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000010'),
  '渋谷'::text,
  'Update stores the trimmed location_name'
);

select lives_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000010', 'Cleared', 'Cleared body',
    null, null, 'private', array[]::text[], '[]'::jsonb
  )$$,
  'NULL explicitly clears location_name during update'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000010'),
  null::text,
  'The cleared location_name is stored as NULL'
);

select lives_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000010', 'Set again', 'Set again body',
    null, '大阪', 'private', array[]::text[], '[]'::jsonb
  )$$,
  'A NULL location_name can be changed to a value'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000010'),
  '大阪'::text,
  'The new location_name is stored after NULL'
);

select throws_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_images_and_location(
      'a4100000-0000-4000-8000-000000000010', 'Should rollback',
      'Should rollback body', null, %L, 'private', array[]::text[], '[]'::jsonb
    )$$,
    pg_catalog.repeat('界', 101)
  ),
  '22023',
  'Invalid location name.',
  'Update rejects a 101-codepoint location_name'
);

select results_eq(
  $$select title, location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000010'$$,
  $$values ('Set again'::text, '大阪'::text)$$,
  'Location validation failure leaves the post unchanged'
);

select throws_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'b4100000-0000-4000-8000-000000000010', null, 'Other update',
    null, 'Other place', 'private', array[]::text[], '[]'::jsonb
  )$$,
  '42501',
  'Post mutation is not permitted.',
  'Another users post cannot be updated'
);

select throws_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000020', null, 'Deleted update',
    null, 'Deleted place', 'private', array[]::text[], '[]'::jsonb
  )$$,
  '42501',
  'Post mutation is not permitted.',
  'A soft-deleted post cannot be updated'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c4100000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'c4100000-0000-4000-8000-000000000101', null, 'Suspended',
    null, 'Denied', 'private', array[]::text[], array[]::text[]
  )$$,
  '42501',
  'Post mutation is not permitted.',
  'A suspended user cannot create a location-aware post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'd4100000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.my_diary_create_post_with_images_and_location(
    'd4100000-0000-4000-8000-000000000101', null, 'Deactivated',
    null, 'Denied', 'private', array[]::text[], array[]::text[]
  )$$,
  '42501',
  'Post mutation is not permitted.',
  'A deactivated user cannot create a location-aware post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a4100000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_post_with_images(
    'a4100000-0000-4000-8000-000000000106', null, 'Legacy create',
    null, 'private', array[]::text[], array[]::text[]
  )$$,
  'The existing create RPC remains callable'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000106'),
  null::text,
  'The existing create RPC preserves its NULL location behavior'
);

select lives_ok(
  $$select public.my_diary_update_post_with_images(
    'a4100000-0000-4000-8000-000000000030', 'Legacy updated',
    'Legacy updated body', null, 'private', array[]::text[], '[]'::jsonb
  )$$,
  'The existing update RPC remains callable'
);

select is(
  (select location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000030'),
  'Legacy place'::text,
  'The existing update RPC preserves location_name'
);

select throws_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000030', 'Tag rollback',
    'Tag rollback body', null, 'Tag rollback place', 'private',
    array['one','two','three','four','five','six'], '[]'::jsonb
  )$$,
  '22023',
  'Invalid tag input.',
  'Tag validation failure aborts the location-aware update'
);

select results_eq(
  $$select title, location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000030'$$,
  $$values ('Legacy updated'::text, 'Legacy place'::text)$$,
  'Tag failure rolls back both post and location changes'
);

select throws_ok(
  $$select public.my_diary_update_post_with_images_and_location(
    'a4100000-0000-4000-8000-000000000030', 'Image rollback',
    'Image rollback body', null, 'Image rollback place', 'private',
    array[]::text[],
    '[{"newPath":"a4100000-0000-4000-8000-000000000001/a4100000-0000-4000-8000-000000000030/e4100000-0000-4000-8000-000000000099"}]'::jsonb
  )$$,
  '22023',
  'Invalid post image input.',
  'Image validation failure aborts the location-aware update'
);

select results_eq(
  $$select title, location_name from public.posts where id =
    'a4100000-0000-4000-8000-000000000030'$$,
  $$values ('Legacy updated'::text, 'Legacy place'::text)$$,
  'Image failure rolls back both post and location changes'
);

select * from finish();

rollback;
