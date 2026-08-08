begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'
  ) is not null,
  'The post image create RPC exists with the exact signature'
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
      and function.proname = 'my_diary_create_post_with_images'
      and function.proargtypes =
        '2950 25 25 25 25 1009 1009'::oidvector
      and function.proargnames = array[
        'p_post_id',
        'p_title',
        'p_body',
        'p_mood',
        'p_visibility',
        'p_tags',
        'p_image_paths'
      ]::text[]
      and function.prorettype = 'uuid'::pg_catalog.regtype
      and function.provolatile = 'v'
      and function.prosecdef
      and language.lanname = 'plpgsql'
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
  ),
  'The RPC has the expected catalog security attributes'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_create_post_with_images'
  ),
  1::bigint,
  'The RPC has no unexpected overload'
);

select ok(
  pg_catalog.obj_description(
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null,
  'The RPC has a catalog comment'
);

select ok(
  not pg_catalog.has_function_privilege(
    'public',
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  ),
  'PUBLIC and anon cannot execute the RPC'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_create_post_with_images(uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  ),
  'Only authenticated receives RPC EXECUTE among application roles'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname =
        'my_diary_post_image_path_is_referenced'
      and function.proargtypes = '25'::oidvector
      and function.prorettype = 'boolean'::pg_catalog.regtype
      and function.provolatile = 's'
      and function.prosecdef
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
      and function.proconfig = array['search_path=""']::text[]
  ),
  'The metadata reference helper has fixed security attributes'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_post_image_path_is_referenced(text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_post_image_path_is_referenced(text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_post_image_path_is_referenced(text)',
    'EXECUTE'
  ),
  'Only authenticated can invoke the private helper for policy evaluation'
);

select ok(
  (
    select file_size_limit = 6291456
      and allowed_mime_types = array[
        'image/jpeg',
        'image/png',
        'image/webp'
      ]::text[]
    from storage.buckets
    where id = 'post-images'
      and public is false
  ),
  'The private bucket enforces the B3b MIME and size limits'
);

select ok(
  (
    select count(*) = 8
      and count(*) filter (where cmd = 'SELECT') = 4
      and count(*) filter (where cmd = 'INSERT') = 2
      and count(*) filter (where cmd = 'DELETE') = 2
      and count(*) filter (where cmd in ('ALL', 'UPDATE')) = 0
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
  ),
  'Storage policies expose guarded SELECT, INSERT, and orphan DELETE only'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.post_images', 'SELECT, INSERT, UPDATE, DELETE'
  ),
  'post_images still has no direct application mutation path'
);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'b3b-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b3b-b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'b3b-suspended@example.test');

update public.accounts
set status = 'suspended'
where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000000',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '42501',
  null,
  'Raw authenticated SQL cannot forge uploaded object metadata'
);

select set_config('storage.operation', 'storage.object.upload', true);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  'An active user can insert a new object in the strict owned namespace'
);

select results_eq(
  $$
    select name
    from storage.objects
    where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001'
  $$,
  $$
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001'::text
    )
  $$,
  'The owner can SELECT a pending orphan for upload response and cleanup'
);

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/b2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000002',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '42501',
  null,
  'A user cannot insert into another user namespace'
);

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000002/e2000000-0000-4000-8000-000000000003',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    )
  $$,
  '42501',
  null,
  'A user cannot spoof Storage object ownership'
);

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '23505',
  null,
  'A duplicate path cannot overwrite an existing object'
);

select results_eq(
  $$
    update storage.objects
    set name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000099'
    where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001'
    returning name
  $$,
  $$select null::text where false$$,
  'No UPDATE policy permits object replacement or moves'
);

select set_config('storage.operation', 'storage.object.delete_many', true);

select throws_ok(
  $$
    delete from storage.objects
    where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  'Direct deletion from storage tables is not allowed. Use the Storage API instead.',
  'The orphan passes RLS and reaches the Storage direct-delete safeguard'
);

reset role;
select ok(
  exists (
    select 1
    from storage.objects
    where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000001'
  ),
  'Direct SQL cannot remove the object; cleanup must use the Storage API'
);

insert into public.posts (id, user_id, body, visibility)
values (
  'a2000000-0000-4000-8000-000000000003',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Referenced image post',
  'private'
);
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'd2000000-0000-4000-8000-000000000003',
  'post-images',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000003/e2000000-0000-4000-8000-000000000003',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '{"mimetype":"image/png","size":68}'::jsonb
);
insert into public.post_images (post_id, storage_path, sort_order)
values (
  'a2000000-0000-4000-8000-000000000003',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000003/e2000000-0000-4000-8000-000000000003',
  0
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  my_diary_private.my_diary_post_image_path_is_referenced(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000003/e2000000-0000-4000-8000-000000000003'
  ),
  true,
  'The cleanup policy helper recognizes referenced metadata'
);

reset role;
update public.posts
set deleted_at = now()
where id = 'a2000000-0000-4000-8000-000000000003';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  my_diary_private.my_diary_post_image_path_is_referenced(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000003/e2000000-0000-4000-8000-000000000003'
  ),
  true,
  'Soft-deleted post metadata remains referenced for cleanup policy checks'
);

select ok(
  (
    select count(*) = 2
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'storage.objects'::pg_catalog.regclass
      and policy.polcmd = 'd'
      and policy.polroles = array[
        (select oid from pg_catalog.pg_roles where rolname = 'authenticated')
      ]::oid[]
      and pg_catalog.pg_get_expr(
        policy.polqual,
        policy.polrelid
      ) like '%owner_id = (auth.uid())::text%'
  ),
  'Both DELETE policies bind cleanup to auth.uid object ownership'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config('storage.operation', 'storage.object.upload', true);

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc/c2000000-0000-4000-8000-000000000001/e2000000-0000-4000-8000-000000000004',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    )
  $$,
  '42501',
  null,
  'A suspended user cannot upload a post image'
);

reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'd2000000-0000-4000-8000-000000000010',
  'post-images',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000010/e2000000-0000-4000-8000-000000000010',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '{"mimetype":"image/png","size":68}'::jsonb
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
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000010',
      'Image post',
      'Image body',
      'happy',
      'private',
      array['image-tag'],
      array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000010/e2000000-0000-4000-8000-000000000010']
    )
  $$,
  'The RPC creates a post with one uploaded image'
);

reset role;
select ok(
  exists (
    select 1
    from public.posts
    where id = 'a2000000-0000-4000-8000-000000000010'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and title = 'Image post'
  ),
  'The RPC fixes the post owner to auth.uid()'
);

select results_eq(
  $$
    select storage_path, sort_order
    from public.post_images
    where post_id = 'a2000000-0000-4000-8000-000000000010'
  $$,
  $$
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000010/e2000000-0000-4000-8000-000000000010'::text,
      0
    )
  $$,
  'The RPC stores the image path at sort_order zero'
);

select ok(
  exists (
    select 1
    from public.tags as tag
    join public.post_tags as relation on relation.tag_id = tag.id
    where relation.post_id = 'a2000000-0000-4000-8000-000000000010'
      and tag.normalized_name = 'image-tag'
  ),
  'The RPC creates canonical tag relations in the same transaction'
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
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000011',
      null,
      'No image body',
      null,
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  'The RPC preserves image-free post creation'
);

reset role;
with inserted as (
  insert into storage.objects (id, bucket_id, name, owner_id, metadata)
  select
    pg_catalog.gen_random_uuid(),
    'post-images',
    pg_catalog.format(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000012/%s',
      pg_catalog.gen_random_uuid()
    ),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '{"mimetype":"image/png","size":68}'::jsonb
  from pg_catalog.generate_series(1, 10)
  returning name
)
select set_config(
  'my_diary.b3b_ten_paths',
  (select pg_catalog.array_agg(name order by name)::text from inserted),
  true
);

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_create_post_with_images('a2000000-0000-4000-8000-000000000012', null, 'Ten image body', null, 'private', array[]::text[], %L::text[])$$,
    current_setting('my_diary.b3b_ten_paths')
  ),
  'The RPC accepts ten uploaded image paths'
);

reset role;
select results_eq(
  $$
    select storage_path, sort_order
    from public.post_images
    where post_id = 'a2000000-0000-4000-8000-000000000012'
    order by sort_order
  $$,
  $$
    select paths.path, paths.ordinality::integer - 1
    from pg_catalog.unnest(
      current_setting('my_diary.b3b_ten_paths')::text[]
    ) with ordinality as paths(path, ordinality)
    order by paths.ordinality
  $$,
  'Ten images preserve caller order with continuous sort_order values'
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
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000013',
      null,
      'Eleven image body',
      null,
      'private',
      array[]::text[],
      (
        select pg_catalog.array_agg(
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000013/e2000000-0000-4000-8000-' ||
          pg_catalog.lpad(sequence::text, 12, '0')
          order by sequence
        )
        from pg_catalog.generate_series(1, 11) as generated(sequence)
      )
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects eleven images'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000014',
      null,
      'Mismatched path body',
      null,
      'private',
      array[]::text[],
      array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000099/e2000000-0000-4000-8000-000000000014']
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a path bound to another post ID'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000015',
      null,
      'Missing object body',
      null,
      'private',
      array[]::text[],
      array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000015/e2000000-0000-4000-8000-000000000015']
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects metadata for a missing Storage object'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000016',
      null,
      'Duplicate image body',
      null,
      'private',
      array[]::text[],
      array[
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000016/e2000000-0000-4000-8000-000000000016',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000016/e2000000-0000-4000-8000-000000000016'
      ]
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects duplicate image paths'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000017',
      null,
      '   ',
      null,
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '22023',
  'Invalid post input.',
  'The successor RPC rejects a blank body'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000018',
      null,
      'Invalid mood body',
      'unknown',
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '22023',
  'Invalid post input.',
  'The successor RPC rejects an invalid mood'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000019',
      null,
      'Invalid visibility body',
      null,
      'friends',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '22023',
  'Invalid post input.',
  'The successor RPC rejects an invalid visibility'
);

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000020',
      null,
      'Too many tags body',
      null,
      'private',
      array['one', 'two', 'three', 'four', 'five', 'six'],
      array[]::text[]
    )
  $$,
  '22023',
  'Invalid tag input.',
  'The successor RPC rejects six canonical tags'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'c2000000-0000-4000-8000-000000000020',
      null,
      'Suspended body',
      null,
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '42501',
  'Post mutation is not permitted.',
  'A suspended user cannot execute the post mutation'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000021',
      null,
      'Anonymous body',
      null,
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '42501',
  null,
  'Anonymous callers cannot execute the RPC'
);

reset role;
insert into public.posts (id, user_id, body, visibility)
values (
  'b2000000-0000-4000-8000-000000000022',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'Existing B post',
  'private'
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
    select public.my_diary_create_post_with_images(
      'b2000000-0000-4000-8000-000000000022',
      null,
      'Take over body',
      null,
      'private',
      array[]::text[],
      array[]::text[]
    )
  $$,
  '23505',
  null,
  'A caller cannot reuse another owner post ID'
);

reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  (
    'd2000000-0000-4000-8000-000000000030',
    'post-images',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000030/e2000000-0000-4000-8000-000000000030',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '{"mimetype":"image/png","size":68}'::jsonb
  ),
  (
    'd2000000-0000-4000-8000-000000000031',
    'post-images',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000030/e2000000-0000-4000-8000-000000000031',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '{"mimetype":"image/png","size":68}'::jsonb
  );

create function public.test_reject_second_post_image()
returns trigger
language plpgsql
set search_path = ''
as $test_trigger$
begin
  if new.sort_order = 1 then
    raise exception 'forced post_images failure';
  end if;
  return new;
end;
$test_trigger$;

create trigger test_reject_second_post_image
before insert on public.post_images
for each row execute function public.test_reject_second_post_image();

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_create_post_with_images(
      'a2000000-0000-4000-8000-000000000030',
      'Rollback image post',
      'Rollback image body',
      null,
      'private',
      array['rollback-image-tag'],
      array[
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000030/e2000000-0000-4000-8000-000000000030',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000030/e2000000-0000-4000-8000-000000000031'
      ]
    )
  $$,
  'P0001',
  'forced post_images failure',
  'An image metadata failure aborts the RPC transaction'
);

reset role;
select ok(
  not exists (
    select 1
    from public.posts
    where id = 'a2000000-0000-4000-8000-000000000030'
  ),
  'RPC rollback leaves no post'
);

select ok(
  not exists (
    select 1
    from public.tags
    where normalized_name = 'rollback-image-tag'
  ),
  'RPC rollback leaves no new tag master'
);

select ok(
  not exists (
    select 1
    from public.post_images
    where post_id = 'a2000000-0000-4000-8000-000000000030'
  ),
  'RPC rollback leaves no image metadata'
);

select is(
  (
    select count(*)
    from storage.objects
    where name like
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a2000000-0000-4000-8000-000000000030/%'
  ),
  2::bigint,
  'Storage uploads remain outside the failed database transaction for app cleanup'
);

select * from finish();

rollback;
