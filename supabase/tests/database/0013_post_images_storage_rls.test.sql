begin;

create extension if not exists pgtap with schema extensions;

select plan(75);

select is(
  (
    select count(*)
    from storage.buckets
    where id = 'post-images'
      and name = 'post-images'
  ),
  1::bigint,
  'The post-images bucket exists exactly once'
);

select is(
  (
    select public
    from storage.buckets
    where id = 'post-images'
  ),
  false,
  'The post-images bucket is private'
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
  ),
  'The post-images bucket limits uploads to supported images of 6 MiB'
);

select has_table('public', 'post_images', 'post_images table exists');
select has_column('public', 'post_images', 'id', 'post_images.id exists');
select has_column(
  'public',
  'post_images',
  'post_id',
  'post_images.post_id exists'
);
select has_column(
  'public',
  'post_images',
  'storage_path',
  'post_images.storage_path exists'
);
select has_column(
  'public',
  'post_images',
  'sort_order',
  'post_images.sort_order exists'
);
select has_column(
  'public',
  'post_images',
  'created_at',
  'post_images.created_at exists'
);
select col_is_pk(
  'public',
  'post_images',
  'id',
  'post_images.id is the primary key'
);

select ok(
  (
    select pg_catalog.array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.post_images'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) = array[
    'id:uuid:t',
    'post_id:uuid:t',
    'storage_path:text:t',
    'sort_order:integer:t',
    'created_at:timestamp with time zone:t'
  ]::text[],
  'post_images has only the five specified non-null columns'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_attrdef as default_value
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.post_images'::pg_catalog.regclass
      and attribute.attname = 'id'
      and pg_catalog.pg_get_expr(
        default_value.adbin,
        default_value.adrelid
      ) = 'gen_random_uuid()'
  ) and exists (
    select 1
    from pg_catalog.pg_attrdef as default_value
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.post_images'::pg_catalog.regclass
      and attribute.attname = 'created_at'
      and pg_catalog.pg_get_expr(
        default_value.adbin,
        default_value.adrelid
      ) = 'now()'
  ),
  'post_images id and created_at have database defaults'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_post_id_fkey'
      and contype = 'f'
      and confrelid = 'public.posts'::pg_catalog.regclass
      and confdeltype = 'c'
  ),
  'post_images.post_id references posts with cascading physical deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_post_sort_key'
      and contype = 'u'
      and condeferrable
      and not condeferred
  ),
  'A post cannot reuse a sort_order and future swaps can defer the check'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_storage_path_key'
      and contype = 'u'
  ),
  'A storage_path cannot be reused'
);

select ok(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname in (
        'my_diary_post_images_sort_order_check',
        'my_diary_post_images_storage_path_length_check'
      )
      and contype = 'c'
  ) = 2,
  'sort_order and storage_path have CHECK constraints'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_index as index_definition
    where index_definition.indexrelid =
        'public.my_diary_post_images_post_sort_key'::pg_catalog.regclass
      and index_definition.indrelid =
        'public.post_images'::pg_catalog.regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indisready
      and index_definition.indpred is null
  ),
  'The post and sort unique index is valid and non-partial'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_index as index_definition
    where index_definition.indexrelid =
        'public.my_diary_post_images_storage_path_key'::pg_catalog.regclass
      and index_definition.indrelid =
        'public.post_images'::pg_catalog.regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indisready
      and index_definition.indpred is null
  ),
  'The storage_path unique index is valid and non-partial'
);

select ok(
  (
    select relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.post_images'::pg_catalog.regclass
  ),
  'post_images is owned by postgres with RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_images'
      and policyname = 'my_diary_post_images_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  'post_images has the authenticated visible-post SELECT policy'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_images'
  ),
  1::bigint,
  'post_images has no mutation policies'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_post_images_storage_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) and exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_post_images_storage_guard_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'RESTRICTIVE'
  ) and exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'my_diary_post_images_storage_guard_anon'
      and cmd = 'SELECT'
      and roles = array['anon']::name[]
      and permissive = 'RESTRICTIVE'
  ),
  'Storage has the post-image allow policy and restrictive guards'
);

select ok(
  (
    select count(*) = 4
      and pg_catalog.count(*) filter (where cmd = 'INSERT') = 2
      and pg_catalog.count(*) filter (where cmd = 'DELETE') = 2
      and pg_catalog.count(*) filter (where cmd in ('ALL', 'UPDATE')) = 0
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'Storage mutation policies allow guarded INSERT and orphan DELETE only'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.post_images', 'DELETE'
  ),
  'authenticated can SELECT but cannot mutate post_images directly'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon', 'public.post_images', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.post_images', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.post_images', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.post_images', 'DELETE'
  ),
  'anon has no post_images privileges'
);

select ok(
  not pg_catalog.has_table_privilege(
    'service_role', 'public.post_images', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'service_role', 'public.post_images', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'service_role', 'public.post_images', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'service_role', 'public.post_images', 'DELETE'
  ),
  'post_images does not depend on direct service_role table access'
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
    where relation.oid = 'public.post_images'::pg_catalog.regclass
      and privilege.grantee = 0
  ),
  'PUBLIC has no post_images privileges'
);

select ok(
  (
    select pg_catalog.pg_get_userbyid(relation.relowner)
    from pg_catalog.pg_class as relation
    where relation.oid = 'storage.buckets'::pg_catalog.regclass
  ) = 'supabase_storage_admin'
  and (
    select pg_catalog.pg_get_userbyid(relation.relowner)
    from pg_catalog.pg_class as relation
    where relation.oid = 'storage.objects'::pg_catalog.regclass
  ) = 'supabase_storage_admin',
  'The standard Storage table owners are unchanged'
);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'post-images-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'post-images-b@example.test');

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    'a1000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A private',
    'A private post',
    'private',
    null
  ),
  (
    'b1000000-0000-4000-8000-000000000001',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B public',
    'B public post',
    'public',
    null
  ),
  (
    'b1000000-0000-4000-8000-000000000002',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B followers',
    'B followers post',
    'followers',
    null
  ),
  (
    'b1000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B private',
    'B private post',
    'private',
    null
  ),
  (
    'b1000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B visibility',
    'B visibility post',
    'public',
    null
  ),
  (
    'b1000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B soft delete',
    'B soft delete post',
    'public',
    null
  ),
  (
    'a1000000-0000-4000-8000-000000000006',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A cascade',
    'A cascade post',
    'private',
    null
  ),
  (
    'a1000000-0000-4000-8000-000000000007',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A image limit',
    'A image limit post',
    'private',
    null
  ),
  (
    'a1000000-0000-4000-8000-000000000008',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A constraints',
    'A constraints post',
    'private',
    null
  );

insert into public.post_images (id, post_id, storage_path, sort_order)
values
  (
    'c1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'a/private.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000001',
    'b/public.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000002',
    'b/followers.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000004',
    'b1000000-0000-4000-8000-000000000003',
    'b/private.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000005',
    'b1000000-0000-4000-8000-000000000004',
    'b/visibility.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000006',
    'b1000000-0000-4000-8000-000000000005',
    'b/soft-delete.jpg',
    0
  ),
  (
    'c1000000-0000-4000-8000-000000000007',
    'a1000000-0000-4000-8000-000000000006',
    'a/cascade.jpg',
    0
  );

insert into storage.buckets (id, name, public)
values ('post-images-test-other', 'post-images-test-other', false);

insert into storage.objects (id, bucket_id, name, owner_id)
values
  (
    'd1000000-0000-4000-8000-000000000001',
    'post-images',
    'a/private.jpg',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (
    'd1000000-0000-4000-8000-000000000002',
    'post-images',
    'b/public.jpg',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  (
    'd1000000-0000-4000-8000-000000000003',
    'post-images',
    'b/followers.jpg',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  (
    'd1000000-0000-4000-8000-000000000004',
    'post-images',
    'b/private.jpg',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (
    'd1000000-0000-4000-8000-000000000005',
    'post-images',
    'b/visibility.jpg',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  (
    'd1000000-0000-4000-8000-000000000006',
    'post-images',
    'b/soft-delete.jpg',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  (
    'd1000000-0000-4000-8000-000000000007',
    'post-images',
    'a/cascade.jpg',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (
    'd1000000-0000-4000-8000-000000000008',
    'post-images',
    'orphan.jpg',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (
    'd1000000-0000-4000-8000-000000000009',
    'post-images-test-other',
    'b/public.jpg',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );

select lives_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    select
      'a1000000-0000-4000-8000-000000000007'::uuid,
      pg_catalog.format('limit/%s.jpg', position),
      position
    from pg_catalog.generate_series(0, 9) as positions(position)
  $$,
  'A post accepts ten distinct image slots'
);

select is(
  (
    select count(*)
    from public.post_images
    where post_id = 'a1000000-0000-4000-8000-000000000007'
  ),
  10::bigint,
  'The ten image rows are retained'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000007',
      'limit/10.jpg',
      10
    )
  $$,
  '23514',
  null,
  'An eleventh image slot is rejected'
);

select is(
  (
    select count(*)
    from public.post_images
    where post_id = 'a1000000-0000-4000-8000-000000000007'
  ),
  10::bigint,
  'The rejected eleventh image leaves the post at ten images'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      'constraints/negative.jpg',
      -1
    )
  $$,
  '23514',
  null,
  'A negative sort_order is rejected'
);

select lives_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values
      (
        'a1000000-0000-4000-8000-000000000008',
        'constraints/last.jpg',
        9
      ),
      (
        'a1000000-0000-4000-8000-000000000008',
        'constraints/first.jpg',
        0
      )
  $$,
  'Boundary sort_order values zero and nine are accepted'
);

select results_eq(
  $$
    select storage_path
    from public.post_images
    where post_id = 'a1000000-0000-4000-8000-000000000008'
    order by sort_order
  $$,
  $$
    values
      ('constraints/first.jpg'::text),
      ('constraints/last.jpg'::text)
  $$,
  'sort_order provides a stable image order independent of insert order'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      'constraints/duplicate-sort.jpg',
      0
    )
  $$,
  '23505',
  null,
  'A post cannot reuse a sort_order'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      'b/public.jpg',
      1
    )
  $$,
  '23505',
  null,
  'A storage_path cannot be reused across posts'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      '',
      1
    )
  $$,
  '23514',
  null,
  'An empty storage_path is rejected'
);

select lives_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      pg_catalog.repeat('x', 1024),
      1
    )
  $$,
  'A storage_path of exactly 1024 characters is accepted'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000008',
      pg_catalog.repeat('x', 1025),
      2
    )
  $$,
  '23514',
  null,
  'A storage_path longer than 1024 characters is rejected'
);

delete from public.posts
where id = 'a1000000-0000-4000-8000-000000000006';

select is(
  (
    select count(*)
    from public.post_images
    where storage_path = 'a/cascade.jpg'
  ),
  0::bigint,
  'Physical post deletion cascades to image metadata'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.post_images$$,
  '42501',
  null,
  'Anonymous users cannot read post image metadata'
);

select results_eq(
  $$select id from storage.objects where bucket_id = 'post-images'$$,
  $$select null::uuid where false$$,
  'Anonymous users receive no private post image objects'
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
  $$
    select storage_path
    from public.post_images
    where storage_path in (
      'a/private.jpg',
      'b/public.jpg',
      'b/followers.jpg',
      'b/private.jpg'
    )
    order by storage_path
  $$,
  $$
    values
      ('a/private.jpg'::text),
      ('b/public.jpg'::text)
  $$,
  'A non-follower sees own private and another active public metadata only'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name in (
        'a/private.jpg',
        'b/public.jpg',
        'b/followers.jpg',
        'b/private.jpg'
      )
    order by name
  $$,
  $$
    values
      ('a/private.jpg'::text),
      ('b/public.jpg'::text)
  $$,
  'Storage SELECT follows the same non-follower visibility boundary'
);

select throws_ok(
  $$
    insert into public.post_images (post_id, storage_path, sort_order)
    values (
      'a1000000-0000-4000-8000-000000000001',
      'direct/insert.jpg',
      1
    )
  $$,
  '42501',
  null,
  'authenticated cannot insert post_images directly'
);

select throws_ok(
  $$
    update public.post_images
    set storage_path = 'direct/update.jpg'
    where id = 'c1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'authenticated cannot update post_images directly'
);

select throws_ok(
  $$
    delete from public.post_images
    where id = 'c1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'authenticated cannot delete post_images directly'
);

select is(
  (
    select storage_path
    from public.post_images
    where id = 'c1000000-0000-4000-8000-000000000001'
  ),
  'a/private.jpg'::text,
  'Rejected direct mutations leave existing metadata unchanged'
);

select throws_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'post-images',
      'direct/storage-insert.jpg',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '42501',
  null,
  'authenticated cannot insert post image Storage objects directly'
);

select results_eq(
  $$
    update storage.objects
    set name = 'direct/storage-update.jpg'
    where id = 'd1000000-0000-4000-8000-000000000001'
    returning id
  $$,
  $$select null::uuid where false$$,
  'authenticated cannot update post image Storage objects directly'
);

select throws_ok(
  $$
    delete from storage.objects
    where id = 'd1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'authenticated cannot delete post image Storage objects directly'
);

select is(
  (
    select name
    from storage.objects
    where id = 'd1000000-0000-4000-8000-000000000001'
  ),
  'a/private.jpg'::text,
  'Rejected Storage mutations leave the visible object unchanged'
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
    select storage_path
    from public.post_images
    where storage_path in ('b/followers.jpg', 'b/private.jpg')
    order by storage_path
  $$,
  $$values ('b/followers.jpg'::text)$$,
  'A follower sees followers metadata but not private metadata'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name in ('b/followers.jpg', 'b/private.jpg')
    order by name
  $$,
  $$values ('b/followers.jpg'::text)$$,
  'A follower sees the followers object but not the private object'
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
  $$select storage_path from public.post_images where storage_path = 'b/followers.jpg'$$,
  $$select null::text where false$$,
  'Unfollowing immediately hides followers metadata'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/followers.jpg'
  $$,
  $$select null::text where false$$,
  'Unfollowing immediately hides the followers object'
);

reset role;
update public.posts
set visibility = 'followers'
where id = 'b1000000-0000-4000-8000-000000000004';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select storage_path from public.post_images where storage_path = 'b/visibility.jpg'$$,
  $$select null::text where false$$,
  'Changing public to followers immediately hides metadata from a non-follower'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/visibility.jpg'
  $$,
  $$select null::text where false$$,
  'Changing public to followers immediately hides the object from a non-follower'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);
update public.posts
set visibility = 'private'
where id = 'b1000000-0000-4000-8000-000000000004';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select storage_path from public.post_images where storage_path = 'b/visibility.jpg'$$,
  $$select null::text where false$$,
  'Changing followers to private hides metadata even from a follower'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/visibility.jpg'
  $$,
  $$select null::text where false$$,
  'Changing followers to private hides the object even from a follower'
);

reset role;
update public.posts
set visibility = 'public'
where id = 'b1000000-0000-4000-8000-000000000004';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select storage_path from public.post_images where storage_path = 'b/visibility.jpg'$$,
  $$values ('b/visibility.jpg'::text)$$,
  'Changing private to public restores metadata visibility'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/visibility.jpg'
  $$,
  $$values ('b/visibility.jpg'::text)$$,
  'Changing private to public restores object visibility'
);

reset role;
update public.posts
set deleted_at = now()
where id = 'b1000000-0000-4000-8000-000000000005';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select storage_path from public.post_images where storage_path = 'b/soft-delete.jpg'$$,
  $$select null::text where false$$,
  'Soft deletion immediately hides image metadata'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/soft-delete.jpg'
  $$,
  $$select null::text where false$$,
  'Soft deletion immediately hides the Storage object'
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
  $$select storage_path from public.post_images where storage_path = 'b/public.jpg'$$,
  $$select null::text where false$$,
  'A suspended author public image does not leak metadata'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/public.jpg'
  $$,
  $$select null::text where false$$,
  'A suspended author public image object is inaccessible'
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
  $$select storage_path from public.post_images where storage_path = 'b/public.jpg'$$,
  $$select null::text where false$$,
  'A suspended viewer cannot see another user public image metadata'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/public.jpg'
  $$,
  $$select null::text where false$$,
  'A suspended viewer cannot read another user public image object'
);

select results_eq(
  $$select storage_path from public.post_images where storage_path = 'a/private.jpg'$$,
  $$values ('a/private.jpg'::text)$$,
  'A suspended viewer retains existing own-post metadata visibility'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'a/private.jpg'
  $$,
  $$values ('a/private.jpg'::text)$$,
  'A suspended viewer retains existing own-post object visibility'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

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
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'orphan.jpg'
  $$,
  $$select null::text where false$$,
  'Knowing an orphan object path is insufficient for access'
);

select results_eq(
  $$
    select bucket_id
    from storage.objects
    where bucket_id = 'post-images-test-other'
      and name = 'b/public.jpg'
  $$,
  $$select null::text where false$$,
  'The post image policy does not expose another bucket with the same path'
);

select results_eq(
  $$
    select name
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'a/cascade.jpg'
  $$,
  $$select null::text where false$$,
  'An object becomes inaccessible after metadata cascades away'
);

reset role;
create policy my_diary_test_broad_storage_select
on storage.objects
for select
to authenticated
using (true);

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
    from storage.objects
    where bucket_id = 'post-images'
      and name = 'b/private.jpg'
  $$,
  $$select null::text where false$$,
  'A broad permissive policy cannot bypass the post-images restrictive guard'
);

select * from finish();

rollback;
