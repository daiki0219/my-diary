begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'
  ) is not null,
  'The post image update RPC exists with the exact signature'
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
      and function.proname = 'my_diary_update_post_with_images'
      and function.proargtypes =
        '2950 25 25 25 25 1009 3802'::oidvector
      and function.proargnames = array[
        'p_post_id',
        'p_title',
        'p_body',
        'p_mood',
        'p_visibility',
        'p_tags',
        'p_image_manifest'
      ]::text[]
      and function.prorettype = 'jsonb'::pg_catalog.regtype
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
      and function.proname = 'my_diary_update_post_with_images'
  ),
  1::bigint,
  'The RPC has no unexpected overload'
);

select ok(
  pg_catalog.obj_description(
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure,
    'pg_proc'
  ) is not null,
  'The RPC has a catalog comment'
);

select ok(
  not pg_catalog.has_function_privilege(
    'public',
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'PUBLIC and anon cannot execute the RPC'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_update_post_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'Only authenticated receives RPC EXECUTE among application roles'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'INSERT, UPDATE, DELETE'
  ),
  'post_images still has no direct authenticated mutation path'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ),
  'No Storage UPDATE policy was added'
);

insert into auth.users (id, email)
values
  ('a3000000-0000-4000-8000-000000000001', 'b3d-a@example.test'),
  ('b3000000-0000-4000-8000-000000000001', 'b3d-b@example.test'),
  ('c3000000-0000-4000-8000-000000000001', 'b3d-suspended@example.test');

update public.accounts
set status = 'suspended'
where user_id = 'c3000000-0000-4000-8000-000000000001';

insert into public.posts (
  id,
  user_id,
  title,
  body,
  mood,
  location_name,
  visibility
)
values
  (
    'a3000000-0000-4000-8000-000000000010',
    'a3000000-0000-4000-8000-000000000001',
    'Before edit',
    'Before body',
    'neutral',
    'Preserved place',
    'public'
  ),
  (
    'b3000000-0000-4000-8000-000000000010',
    'b3000000-0000-4000-8000-000000000001',
    'Other owner',
    'Other body',
    null,
    null,
    'private'
  ),
  (
    'a3000000-0000-4000-8000-000000000020',
    'a3000000-0000-4000-8000-000000000001',
    'Soft deleted',
    'Deleted body',
    null,
    null,
    'private'
  );

update public.posts
set deleted_at = now()
where id = 'a3000000-0000-4000-8000-000000000020';

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  (
    'd3000000-0000-4000-8000-000000000001',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000001',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/png","size":68}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000002',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000002',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/jpeg","size":1024}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000003',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000003',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/webp","size":2048}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000004',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000004',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/png","size":4096}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000005',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000005',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"text/plain","size":10}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000006',
    'post-images',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000006',
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/png","size":6291457}'::jsonb
  ),
  (
    'd3000000-0000-4000-8000-000000000007',
    'post-images',
    'b3000000-0000-4000-8000-000000000001/b3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000007',
    'b3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/png","size":68}'::jsonb
  );

insert into public.post_images (
  id,
  post_id,
  storage_path,
  sort_order,
  created_at
)
values
  (
    'f3000000-0000-4000-8000-000000000001',
    'a3000000-0000-4000-8000-000000000010',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000001',
    0,
    '2026-08-08 00:00:01+00'
  ),
  (
    'f3000000-0000-4000-8000-000000000002',
    'a3000000-0000-4000-8000-000000000010',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000002',
    1,
    '2026-08-08 00:00:02+00'
  ),
  (
    'f3000000-0000-4000-8000-000000000003',
    'a3000000-0000-4000-8000-000000000010',
    'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000003',
    2,
    '2026-08-08 00:00:03+00'
  ),
  (
    'f3000000-0000-4000-8000-000000000007',
    'b3000000-0000-4000-8000-000000000010',
    'b3000000-0000-4000-8000-000000000001/b3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000007',
    0,
    '2026-08-08 00:00:07+00'
  );

select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select value
    from pg_catalog.jsonb_array_elements_text(
      public.my_diary_update_post_with_images(
        'a3000000-0000-4000-8000-000000000010',
        'After edit',
        'After body',
        'happy',
        'followers',
        array['b3d-tag'],
        '[
          {"existingId":"f3000000-0000-4000-8000-000000000003"},
          {"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000004"},
          {"existingId":"f3000000-0000-4000-8000-000000000002"}
        ]'::jsonb
      ) -> 'removedImagePaths'
    )
  $$,
  $$
    values (
      'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000001'::text
    )
  $$,
  'The mixed update returns only DB-derived removed Storage paths'
);

reset role;
select results_eq(
  $$
    select title, body, mood, location_name, visibility
    from public.posts
    where id = 'a3000000-0000-4000-8000-000000000010'
  $$,
  $$values ('After edit'::text, 'After body'::text, 'happy'::text, 'Preserved place'::text, 'followers'::text)$$,
  'The RPC updates editable fields while preserving location_name'
);

select results_eq(
  $$
    select tag.normalized_name
    from public.tags as tag
    join public.post_tags as relation on relation.tag_id = tag.id
    where relation.post_id = 'a3000000-0000-4000-8000-000000000010'
  $$,
  $$values ('b3d-tag'::text)$$,
  'Tags are replaced in the same transaction'
);

select results_eq(
  $$
    select id, sort_order
    from public.post_images
    where post_id = 'a3000000-0000-4000-8000-000000000010'
    order by sort_order
  $$,
  $$
    values
      ('f3000000-0000-4000-8000-000000000003'::uuid, 0),
      ((select id from public.post_images where storage_path like '%e3000000-0000-4000-8000-000000000004'), 1),
      ('f3000000-0000-4000-8000-000000000002'::uuid, 2)
  $$,
  'The final manifest has continuous mixed image order'
);

select results_eq(
  $$
    select id, storage_path, created_at
    from public.post_images
    where id in (
      'f3000000-0000-4000-8000-000000000002',
      'f3000000-0000-4000-8000-000000000003'
    )
    order by id
  $$,
  $$
    values
      (
        'f3000000-0000-4000-8000-000000000002'::uuid,
        'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000002'::text,
        '2026-08-08 00:00:02+00'::timestamptz
      ),
      (
        'f3000000-0000-4000-8000-000000000003'::uuid,
        'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000003'::text,
        '2026-08-08 00:00:03+00'::timestamptz
      )
  $$,
  'Retained image id, storage_path, and created_at stay unchanged'
);

select ok(
  not exists (
    select 1
    from public.post_images
    where id = 'f3000000-0000-4000-8000-000000000001'
  ),
  'Removed image metadata is deleted after the atomic update'
);

select ok(
  exists (
    select 1
    from storage.objects
    where name like '%e3000000-0000-4000-8000-000000000001'
  ),
  'The RPC never deletes the removed Storage object before commit'
);

select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000010',
      'No images',
      'Still valid',
      null,
      'private',
      array[]::text[],
      '[]'::jsonb
    )
  $$,
  'The RPC accepts a zero-image final manifest'
);

reset role;
select is(
  (
    select count(*)
    from public.post_images
    where post_id = 'a3000000-0000-4000-8000-000000000010'
  ),
  0::bigint,
  'The zero-image manifest removes all image metadata'
);

insert into public.posts (id, user_id, body, visibility)
values (
  'a3000000-0000-4000-8000-000000000030',
  'a3000000-0000-4000-8000-000000000001',
  'Ten image post',
  'private'
);

with inserted as (
  insert into storage.objects (id, bucket_id, name, owner_id, metadata)
  select
    pg_catalog.gen_random_uuid(),
    'post-images',
    pg_catalog.format(
      'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000030/%s',
      pg_catalog.gen_random_uuid()
    ),
    'a3000000-0000-4000-8000-000000000001',
    '{"mimetype":"image/png","size":68}'::jsonb
  from pg_catalog.generate_series(1, 10)
  returning name
)
select set_config(
  'my_diary.b3d_ten_manifest',
  (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object('newPath', name)
      order by name
    )::text
    from inserted
  ),
  true
);

select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  pg_catalog.format(
    $$select public.my_diary_update_post_with_images('a3000000-0000-4000-8000-000000000030', null, 'Ten image post', null, 'private', array[]::text[], %L::jsonb)$$,
    current_setting('my_diary.b3d_ten_manifest')
  ),
  'The RPC accepts ten final images'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030',
      null,
      'Eleven images',
      null,
      'private',
      array[]::text[],
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object('existingId', pg_catalog.gen_random_uuid())
        )
        from pg_catalog.generate_series(1, 11)
      )
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects eleven final images'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Duplicate', null, 'private', array[]::text[],
      '[{"existingId":"f3000000-0000-4000-8000-000000000002"},{"existingId":"f3000000-0000-4000-8000-000000000002"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects duplicate existing image IDs'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Foreign', null, 'private', array[]::text[],
      '[{"existingId":"f3000000-0000-4000-8000-000000000007"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a foreign image ID'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Missing', null, 'private', array[]::text[],
      '[{"existingId":"f3000000-0000-4000-8000-000000000099"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a missing image ID'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Duplicate path', null, 'private', array[]::text[],
      '[
        {"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000030/e3000000-0000-4000-8000-000000000099"},
        {"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000030/e3000000-0000-4000-8000-000000000099"}
      ]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects duplicate new paths'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Foreign namespace', null, 'private', array[]::text[],
      '[{"newPath":"b3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000030/e3000000-0000-4000-8000-000000000099"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a foreign user namespace'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Wrong post', null, 'private', array[]::text[],
      '[{"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000099/e3000000-0000-4000-8000-000000000099"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a path for another post ID'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000030', null, 'Missing object', null, 'private', array[]::text[],
      '[{"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000030/e3000000-0000-4000-8000-000000000099"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects a missing Storage object'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000010', null, 'Bad MIME', null, 'private', array[]::text[],
      '[{"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000005"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects an invalid Storage MIME type'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000010', null, 'Too large', null, 'private', array[]::text[],
      '[{"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000010/e3000000-0000-4000-8000-000000000006"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects an oversized Storage object'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000010', null, 'Malformed', null, 'private', array[]::text[],
      '[{"existingId":"f3000000-0000-4000-8000-000000000002","newPath":"x"}]'::jsonb
    )
  $$,
  '22023',
  'Invalid post image input.',
  'The RPC rejects malformed manifest entries'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'b3000000-0000-4000-8000-000000000010', null, 'Other owner', null, 'private', array[]::text[], '[]'::jsonb
    )
  $$,
  '42501',
  'Post mutation is not permitted.',
  'A user cannot update another owner post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000010', null, 'Suspended', null, 'private', array[]::text[], '[]'::jsonb
    )
  $$,
  '42501',
  'Post mutation is not permitted.',
  'A suspended user cannot execute the mutation'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000020', null, 'Deleted', null, 'private', array[]::text[], '[]'::jsonb
    )
  $$,
  '42501',
  'Post mutation is not permitted.',
  'A soft-deleted post cannot be updated'
);

reset role;
insert into public.posts (id, user_id, title, body, visibility)
values (
  'a3000000-0000-4000-8000-000000000040',
  'a3000000-0000-4000-8000-000000000001',
  'Rollback before',
  'Rollback before body',
  'private'
);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'd3000000-0000-4000-8000-000000000040',
  'post-images',
  'a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000040/e3000000-0000-4000-8000-000000000040',
  'a3000000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'::jsonb
);

create function public.test_reject_b3d_post_image()
returns trigger
language plpgsql
set search_path = ''
as $test_trigger$
begin
  raise exception 'forced B3d post_images failure';
end;
$test_trigger$;

create trigger test_reject_b3d_post_image
before insert on public.post_images
for each row execute function public.test_reject_b3d_post_image();

select set_config(
  'request.jwt.claim.sub',
  'a3000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_update_post_with_images(
      'a3000000-0000-4000-8000-000000000040',
      'Rollback after',
      'Rollback after body',
      null,
      'public',
      array['rollback-b3d-tag'],
      '[{"newPath":"a3000000-0000-4000-8000-000000000001/a3000000-0000-4000-8000-000000000040/e3000000-0000-4000-8000-000000000040"}]'::jsonb
    )
  $$,
  'P0001',
  'forced B3d post_images failure',
  'An image metadata failure aborts the whole RPC transaction'
);

reset role;
select results_eq(
  $$select title, body, visibility from public.posts where id = 'a3000000-0000-4000-8000-000000000040'$$,
  $$values ('Rollback before'::text, 'Rollback before body'::text, 'private'::text)$$,
  'Post field updates roll back with an image failure'
);

select ok(
  not exists (
    select 1
    from public.tags
    where normalized_name = 'rollback-b3d-tag'
  ),
  'Tag updates roll back with an image failure'
);

select is(
  (
    select count(*)
    from public.post_images
    where post_id = 'a3000000-0000-4000-8000-000000000040'
  ),
  0::bigint,
  'Image metadata updates roll back atomically'
);

select * from finish();
