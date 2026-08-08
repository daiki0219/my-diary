begin;

create extension if not exists pgtap with schema extensions;

select plan(79);

-- Catalog and ACL boundary.
select is(
  (
    select pg_catalog.pg_get_constraintdef(constraint_definition.oid)
    from pg_catalog.pg_constraint as constraint_definition
    where constraint_definition.conrelid =
        'public.accounts'::pg_catalog.regclass
      and constraint_definition.conname = 'my_diary_accounts_status_check'
  ),
  $$CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'deactivated'::text])))$$,
  'Account statuses remain active, suspended, and deactivated'
);

select ok(
  (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        like '%my_diary_is_account_active(auth.uid())%'
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_can_view_post'
      and function_definition.proargtypes = '2950 25 1184'::oidvector
  ),
  'Post visibility helper is postgres-owned, hardened, and active-gated'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_can_view_post(uuid,text,timestamptz)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_can_view_post(uuid,text,timestamptz)',
    'EXECUTE'
  ),
  'Only authenticated can invoke the post visibility helper among application roles'
);

select ok(
  (
    select function_definition.prosecdef
      and function_definition.provolatile = 's'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        like '%my_diary_is_account_active(auth.uid())%'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        not like '%profiles.user_id = auth.uid()%'
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname = 'my_diary_search_profiles'
      and function_definition.proargtypes = '25'::oidvector
  ),
  'Profile search keeps its hardened attributes and requires an active viewer'
);

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
  ),
  'Profile search ACL remains authenticated-only'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'my_diary_profiles_select_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_is_account_active%'
  ),
  1::bigint,
  'Profile SELECT is active-gated'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'posts'
      and policyname = 'my_diary_posts_select_visible'
      and qual like '%my_diary_can_view_post%'
  ),
  1::bigint,
  'Posts SELECT continues to delegate to the hardened visibility helper'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_guard_authenticated',
        'my_diary_post_images_storage_select_owned_orphan',
        'my_diary_post_images_storage_delete_owned_orphan',
        'my_diary_post_images_storage_guard_delete_authenticated'
      )
      and coalesce(qual, '') like '%my_diary_is_account_active%'
  ),
  4::bigint,
  'All orphan SELECT and DELETE Storage paths require an active account'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'my_diary_accounts_select_own'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  1::bigint,
  'Own-account SELECT policy remains available for C1b status checks'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'my_diary_accounts_update_own_timezone'
      and qual like '%my_diary_is_account_active%'
      and with_check like '%my_diary_is_account_active%'
  ),
  1::bigint,
  'Timezone UPDATE remains active-gated'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'my_diary_profiles_update_own'
      and qual like '%my_diary_is_account_active%'
      and with_check like '%my_diary_is_account_active%'
  ),
  1::bigint,
  'Profile UPDATE remains active-gated'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_insert_owned_namespace',
        'my_diary_post_images_storage_guard_insert_authenticated'
      )
      and coalesce(with_check, '') like '%my_diary_is_account_active%'
  ),
  2::bigint,
  'Storage INSERT policies remain active-gated'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
      and cmd in ('ALL', 'UPDATE')
  ),
  0::bigint,
  'No post-images Storage UPDATE path exists'
);

select ok(
  not pg_catalog.has_table_privilege('anon', 'public.accounts', 'SELECT')
  and not pg_catalog.has_table_privilege('anon', 'public.profiles', 'SELECT')
  and not pg_catalog.has_table_privilege('anon', 'public.posts', 'SELECT'),
  'Anonymous access to normal data remains closed'
);

-- Fixtures: two active, one suspended, and one deactivated account.
insert into auth.users (id, email)
values
  ('a1600000-0000-4000-8000-000000000001', 'c1a-active-a@example.test'),
  ('b1600000-0000-4000-8000-000000000002', 'c1a-active-b@example.test'),
  ('c1600000-0000-4000-8000-000000000003', 'c1a-suspended@example.test'),
  ('d1600000-0000-4000-8000-000000000004', 'c1a-deactivated@example.test');

update public.profiles
set username = case user_id
  when 'a1600000-0000-4000-8000-000000000001' then 'C1A Active A'
  when 'b1600000-0000-4000-8000-000000000002' then 'C1A Active B'
  when 'c1600000-0000-4000-8000-000000000003' then 'C1A Suspended'
  when 'd1600000-0000-4000-8000-000000000004' then 'C1A Deactivated'
end
where user_id in (
  'a1600000-0000-4000-8000-000000000001',
  'b1600000-0000-4000-8000-000000000002',
  'c1600000-0000-4000-8000-000000000003',
  'd1600000-0000-4000-8000-000000000004'
);

update public.accounts
set status = case user_id
  when 'c1600000-0000-4000-8000-000000000003' then 'suspended'
  when 'd1600000-0000-4000-8000-000000000004' then 'deactivated'
  else 'active'
end
where user_id in (
  'a1600000-0000-4000-8000-000000000001',
  'b1600000-0000-4000-8000-000000000002',
  'c1600000-0000-4000-8000-000000000003',
  'd1600000-0000-4000-8000-000000000004'
);

insert into public.follows (follower_id, following_id)
values
  (
    'a1600000-0000-4000-8000-000000000001',
    'b1600000-0000-4000-8000-000000000002'
  ),
  (
    'c1600000-0000-4000-8000-000000000003',
    'b1600000-0000-4000-8000-000000000002'
  ),
  (
    'd1600000-0000-4000-8000-000000000004',
    'b1600000-0000-4000-8000-000000000002'
  );

insert into public.posts (id, user_id, title, body, visibility)
values
  (
    '11600000-0000-4000-8000-000000000001',
    'a1600000-0000-4000-8000-000000000001',
    'C1A own private', 'C1A own private body', 'private'
  ),
  (
    '11600000-0000-4000-8000-000000000002',
    'a1600000-0000-4000-8000-000000000001',
    'C1A own followers', 'C1A own followers body', 'followers'
  ),
  (
    '11600000-0000-4000-8000-000000000003',
    'a1600000-0000-4000-8000-000000000001',
    'C1A own public', 'C1A own public body', 'public'
  ),
  (
    '21600000-0000-4000-8000-000000000001',
    'b1600000-0000-4000-8000-000000000002',
    'C1A B private', 'C1A B private body', 'private'
  ),
  (
    '21600000-0000-4000-8000-000000000002',
    'b1600000-0000-4000-8000-000000000002',
    'C1A B followers', 'C1A B followers body', 'followers'
  ),
  (
    '21600000-0000-4000-8000-000000000003',
    'b1600000-0000-4000-8000-000000000002',
    'C1A B public', 'C1A B public searchable', 'public'
  ),
  (
    '31600000-0000-4000-8000-000000000001',
    'c1600000-0000-4000-8000-000000000003',
    'C1A suspended public', 'C1A suspended searchable', 'public'
  ),
  (
    '31600000-0000-4000-8000-000000000002',
    'c1600000-0000-4000-8000-000000000003',
    'C1A suspended followers', 'C1A suspended followers', 'followers'
  ),
  (
    '41600000-0000-4000-8000-000000000001',
    'd1600000-0000-4000-8000-000000000004',
    'C1A deactivated public', 'C1A deactivated searchable', 'public'
  );

insert into public.tags (id, name, normalized_name)
values
  ('51600000-0000-4000-8000-000000000001', 'c1a-active-tag', 'c1a-active-tag'),
  ('51600000-0000-4000-8000-000000000002', 'c1a-suspended-tag', 'c1a-suspended-tag'),
  ('51600000-0000-4000-8000-000000000003', 'c1a-deactivated-tag', 'c1a-deactivated-tag'),
  ('51600000-0000-4000-8000-000000000004', 'c1a-own-tag', 'c1a-own-tag');

insert into public.post_tags (post_id, tag_id)
values
  ('21600000-0000-4000-8000-000000000003', '51600000-0000-4000-8000-000000000001'),
  ('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000002'),
  ('41600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000003'),
  ('11600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000004');

insert into public.post_images (id, post_id, storage_path, sort_order)
values
  (
    '61600000-0000-4000-8000-000000000001',
    '21600000-0000-4000-8000-000000000003',
    'b1600000-0000-4000-8000-000000000002/21600000-0000-4000-8000-000000000003/61600000-0000-4000-8000-000000000001',
    0
  ),
  (
    '61600000-0000-4000-8000-000000000002',
    '31600000-0000-4000-8000-000000000001',
    'c1600000-0000-4000-8000-000000000003/31600000-0000-4000-8000-000000000001/61600000-0000-4000-8000-000000000002',
    0
  ),
  (
    '61600000-0000-4000-8000-000000000003',
    '41600000-0000-4000-8000-000000000001',
    'd1600000-0000-4000-8000-000000000004/41600000-0000-4000-8000-000000000001/61600000-0000-4000-8000-000000000003',
    0
  );

insert into storage.objects (id, bucket_id, name, owner_id)
values
  (
    '71600000-0000-4000-8000-000000000001', 'post-images',
    'b1600000-0000-4000-8000-000000000002/21600000-0000-4000-8000-000000000003/61600000-0000-4000-8000-000000000001',
    'b1600000-0000-4000-8000-000000000002'
  ),
  (
    '71600000-0000-4000-8000-000000000002', 'post-images',
    'c1600000-0000-4000-8000-000000000003/31600000-0000-4000-8000-000000000001/61600000-0000-4000-8000-000000000002',
    'c1600000-0000-4000-8000-000000000003'
  ),
  (
    '71600000-0000-4000-8000-000000000003', 'post-images',
    'd1600000-0000-4000-8000-000000000004/41600000-0000-4000-8000-000000000001/61600000-0000-4000-8000-000000000003',
    'd1600000-0000-4000-8000-000000000004'
  ),
  (
    '71600000-0000-4000-8000-000000000004', 'post-images',
    'c1600000-0000-4000-8000-000000000003/81600000-0000-4000-8000-000000000001/91600000-0000-4000-8000-000000000001',
    'c1600000-0000-4000-8000-000000000003'
  ),
  (
    '71600000-0000-4000-8000-000000000005', 'post-images',
    'd1600000-0000-4000-8000-000000000004/81600000-0000-4000-8000-000000000002/91600000-0000-4000-8000-000000000002',
    'd1600000-0000-4000-8000-000000000004'
  );

insert into public.reactions (id, post_id, user_id, reaction_type)
values (
  'a1600000-0000-4000-8000-000000000010',
  '21600000-0000-4000-8000-000000000003',
  'a1600000-0000-4000-8000-000000000001',
  'empathy'
);

insert into public.comments (id, post_id, user_id, body)
values (
  'a1600000-0000-4000-8000-000000000011',
  '21600000-0000-4000-8000-000000000003',
  'a1600000-0000-4000-8000-000000000001',
  'C1A active comment'
);

-- Active viewer regression and non-active target filtering.
select set_config(
  'request.jwt.claim.sub',
  'a1600000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where user_id = 'a1600000-0000-4000-8000-000000000001' order by id$$,
  $$values
    ('11600000-0000-4000-8000-000000000001'::uuid),
    ('11600000-0000-4000-8000-000000000002'::uuid),
    ('11600000-0000-4000-8000-000000000003'::uuid)$$,
  'An active viewer can read own private, followers, and public posts'
);

select results_eq(
  $$select id from public.posts where id = '21600000-0000-4000-8000-000000000003'$$,
  $$values ('21600000-0000-4000-8000-000000000003'::uuid)$$,
  'An active viewer can read another active public post'
);

select results_eq(
  $$select id from public.posts where id = '21600000-0000-4000-8000-000000000002'$$,
  $$values ('21600000-0000-4000-8000-000000000002'::uuid)$$,
  'An active follower can read an active followers-only post'
);

select is_empty(
  $$select id from public.posts where id = '21600000-0000-4000-8000-000000000001'$$,
  'An active viewer cannot read another private post'
);

select results_eq(
  $$select user_id from public.profiles order by user_id$$,
  $$values
    ('a1600000-0000-4000-8000-000000000001'::uuid),
    ('b1600000-0000-4000-8000-000000000002'::uuid)$$,
  'An active viewer can read active profiles'
);

select is_empty(
  $$select user_id from public.profiles where user_id in (
    'c1600000-0000-4000-8000-000000000003',
    'd1600000-0000-4000-8000-000000000004'
  )$$,
  'Suspended and deactivated target profiles are hidden from active viewers'
);

select results_eq(
  $$select name from public.tags where name in ('c1a-active-tag', 'c1a-own-tag') order by name$$,
  $$values ('c1a-active-tag'::text), ('c1a-own-tag'::text)$$,
  'Active viewers keep visible active and own tags'
);

select is_empty(
  $$select name from public.tags where name in ('c1a-suspended-tag', 'c1a-deactivated-tag')$$,
  'Tags used only by non-active targets do not leak'
);

select results_eq(
  $$select id from public.post_images where id = '61600000-0000-4000-8000-000000000001'$$,
  $$values ('61600000-0000-4000-8000-000000000001'::uuid)$$,
  'Active viewers can read visible image metadata'
);

select is_empty(
  $$select id from public.post_images where id in (
    '61600000-0000-4000-8000-000000000002',
    '61600000-0000-4000-8000-000000000003'
  )$$,
  'Image metadata from non-active targets does not leak'
);

select results_eq(
  $$select id from storage.objects where id = '71600000-0000-4000-8000-000000000001'$$,
  $$values ('71600000-0000-4000-8000-000000000001'::uuid)$$,
  'Active viewers can read a visible post image object'
);

select is_empty(
  $$select id from storage.objects where id in (
    '71600000-0000-4000-8000-000000000002',
    '71600000-0000-4000-8000-000000000003'
  )$$,
  'Image objects from non-active targets do not leak'
);

select results_eq(
  $$select id from public.reactions where id = 'a1600000-0000-4000-8000-000000000010'$$,
  $$values ('a1600000-0000-4000-8000-000000000010'::uuid)$$,
  'Active viewers retain visible reactions'
);

select results_eq(
  $$select id from public.comments where id = 'a1600000-0000-4000-8000-000000000011'$$,
  $$values ('a1600000-0000-4000-8000-000000000011'::uuid)$$,
  'Active viewers retain visible comments'
);

select results_eq(
  $$select user_id from public.my_diary_search_profiles('C1A Active B')$$,
  $$values ('b1600000-0000-4000-8000-000000000002'::uuid)$$,
  'Active viewers can search an active profile'
);

select is_empty(
  $$select user_id from public.my_diary_search_profiles('C1A Suspended')$$,
  'Profile search hides suspended targets'
);

select results_eq(
  $$select id from public.my_diary_search_posts('C1A B public searchable', null, null)$$,
  $$values ('21600000-0000-4000-8000-000000000003'::uuid)$$,
  'Active viewers can search visible posts'
);

select results_eq(
  $$select normalized_name from public.my_diary_search_tags('c1a-active-tag', null)$$,
  $$values ('c1a-active-tag'::text)$$,
  'Active viewers can search visible tags'
);

select results_eq(
  $$select following_id from public.follows order by following_id$$,
  $$values ('b1600000-0000-4000-8000-000000000002'::uuid)$$,
  'Active viewers see only follows whose endpoints are active'
);

select results_eq(
  $$update public.profiles set bio = 'active bio' where user_id = 'a1600000-0000-4000-8000-000000000001' returning bio$$,
  $$values ('active bio'::text)$$,
  'Active viewers retain own profile mutation'
);

select results_eq(
  $$update public.accounts set timezone = 'UTC' where user_id = 'a1600000-0000-4000-8000-000000000001' returning timezone$$,
  $$values ('UTC'::text)$$,
  'Active viewers retain timezone mutation'
);

-- Suspended viewer keeps only the own accounts status path.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'c1600000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;

select results_eq(
  $$select status from public.accounts where user_id = 'c1600000-0000-4000-8000-000000000003'$$,
  $$values ('suspended'::text)$$,
  'A suspended viewer can read their own status for C1b'
);

select is_empty(
  $$select status from public.accounts where user_id = 'a1600000-0000-4000-8000-000000000001'$$,
  'A suspended viewer cannot read another account row'
);

select is_empty(
  $$update public.accounts set timezone = 'Asia/Tokyo' where user_id = 'c1600000-0000-4000-8000-000000000003' returning timezone$$,
  'A suspended viewer cannot update timezone'
);

select is_empty($$select user_id from public.profiles$$, 'A suspended viewer cannot read profiles');
select is_empty($$select id from public.posts$$, 'A suspended viewer cannot read posts including own posts');
select is_empty($$select id from public.tags$$, 'A suspended viewer cannot read tags');
select is_empty($$select post_id from public.post_tags$$, 'A suspended viewer cannot read post tags');
select is_empty($$select id from public.post_images$$, 'A suspended viewer cannot read image metadata');
select is_empty(
  $$select id from storage.objects where id in (
    '71600000-0000-4000-8000-000000000001',
    '71600000-0000-4000-8000-000000000002'
  )$$,
  'A suspended viewer cannot read referenced image objects'
);
select is_empty($$select id from public.reactions$$, 'A suspended viewer cannot read reactions');
select is_empty($$select id from public.comments$$, 'A suspended viewer cannot read comments');
select is_empty($$select follower_id from public.follows$$, 'A suspended viewer cannot read follows');

select throws_ok(
  $$select * from public.my_diary_search_profiles('C1A Active')$$,
  '42501', null,
  'A suspended viewer cannot execute profile search'
);
select is_empty(
  $$select id from public.my_diary_search_posts('C1A B public', null, null)$$,
  'A suspended viewer gets no post search results'
);
select is_empty(
  $$select id from public.my_diary_search_tags('c1a-active-tag', null)$$,
  'A suspended viewer gets no tag search results'
);
select is_empty(
  $$update public.profiles set bio = 'blocked' where user_id = 'c1600000-0000-4000-8000-000000000003' returning user_id$$,
  'A suspended viewer cannot update profile'
);
select throws_ok(
  $$insert into public.follows (follower_id, following_id) values (
    'c1600000-0000-4000-8000-000000000003',
    'a1600000-0000-4000-8000-000000000001'
  )$$,
  '42501', null,
  'A suspended viewer cannot follow'
);
select throws_ok(
  $$insert into public.reactions (post_id, user_id, reaction_type) values (
    '21600000-0000-4000-8000-000000000003',
    'c1600000-0000-4000-8000-000000000003',
    'support'
  )$$,
  '42501', null,
  'A suspended viewer cannot react'
);
select throws_ok(
  $$insert into public.comments (post_id, user_id, body) values (
    '21600000-0000-4000-8000-000000000003',
    'c1600000-0000-4000-8000-000000000003',
    'blocked suspended comment'
  )$$,
  '42501', null,
  'A suspended viewer cannot comment'
);
select is_empty(
  $$select id from storage.objects where id = '71600000-0000-4000-8000-000000000004'$$,
  'A suspended viewer cannot select an owned orphan during delete-many'
);
reset role;
select results_eq(
  $$select id from storage.objects where id = '71600000-0000-4000-8000-000000000004'$$,
  $$values ('71600000-0000-4000-8000-000000000004'::uuid)$$,
  'The suspended viewer orphan remains stored after the rejected delete'
);

-- Deactivated viewer has the same fail-closed boundary.
select set_config(
  'request.jwt.claim.sub',
  'd1600000-0000-4000-8000-000000000004',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('storage.operation', 'storage.object.delete_many', true);
set local role authenticated;

select results_eq(
  $$select status from public.accounts where user_id = 'd1600000-0000-4000-8000-000000000004'$$,
  $$values ('deactivated'::text)$$,
  'A deactivated viewer can read their own status for C1b'
);
select is_empty(
  $$select status from public.accounts where user_id = 'a1600000-0000-4000-8000-000000000001'$$,
  'A deactivated viewer cannot read another account row'
);
select is_empty(
  $$update public.accounts set timezone = 'UTC' where user_id = 'd1600000-0000-4000-8000-000000000004' returning timezone$$,
  'A deactivated viewer cannot update timezone'
);
select is_empty($$select user_id from public.profiles$$, 'A deactivated viewer cannot read profiles');
select is_empty($$select id from public.posts$$, 'A deactivated viewer cannot read posts including own posts');
select is_empty($$select id from public.tags$$, 'A deactivated viewer cannot read tags');
select is_empty($$select id from public.post_images$$, 'A deactivated viewer cannot read image metadata');
select is_empty(
  $$select id from storage.objects where bucket_id = 'post-images'$$,
  'A deactivated viewer cannot read post image objects'
);
select is_empty($$select id from public.reactions$$, 'A deactivated viewer cannot read reactions');
select is_empty($$select id from public.comments$$, 'A deactivated viewer cannot read comments');
select throws_ok(
  $$select * from public.my_diary_search_profiles('C1A Active')$$,
  '42501', null,
  'A deactivated viewer cannot execute profile search'
);
select is_empty(
  $$select id from public.my_diary_search_posts('C1A B public', null, null)$$,
  'A deactivated viewer gets no post search results'
);
select is_empty(
  $$select id from public.my_diary_search_tags('c1a-active-tag', null)$$,
  'A deactivated viewer gets no tag search results'
);
select is_empty(
  $$update public.profiles set bio = 'blocked' where user_id = 'd1600000-0000-4000-8000-000000000004' returning user_id$$,
  'A deactivated viewer cannot update profile'
);
select throws_ok(
  $$insert into public.follows (follower_id, following_id) values (
    'd1600000-0000-4000-8000-000000000004',
    'a1600000-0000-4000-8000-000000000001'
  )$$,
  '42501', null,
  'A deactivated viewer cannot follow'
);
select throws_ok(
  $$insert into public.reactions (post_id, user_id, reaction_type) values (
    '21600000-0000-4000-8000-000000000003',
    'd1600000-0000-4000-8000-000000000004',
    'support'
  )$$,
  '42501', null,
  'A deactivated viewer cannot react'
);
select throws_ok(
  $$insert into public.comments (post_id, user_id, body) values (
    '21600000-0000-4000-8000-000000000003',
    'd1600000-0000-4000-8000-000000000004',
    'blocked deactivated comment'
  )$$,
  '42501', null,
  'A deactivated viewer cannot comment'
);
select is_empty(
  $$select id from storage.objects where id = '71600000-0000-4000-8000-000000000005'$$,
  'A deactivated viewer cannot select an owned orphan during delete-many'
);
reset role;
select results_eq(
  $$select id from storage.objects where id = '71600000-0000-4000-8000-000000000005'$$,
  $$values ('71600000-0000-4000-8000-000000000005'::uuid)$$,
  'The deactivated viewer orphan remains stored after the rejected delete'
);

-- Status restoration reveals retained, non-deleted data through normal RLS again.
update public.accounts
set status = 'active'
where user_id = 'c1600000-0000-4000-8000-000000000003';

select set_config(
  'request.jwt.claim.sub',
  'c1600000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '31600000-0000-4000-8000-000000000001'$$,
  $$values ('31600000-0000-4000-8000-000000000001'::uuid)$$,
  'Reactivating an account restores own retained post visibility'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a1600000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.posts where id = '31600000-0000-4000-8000-000000000001'$$,
  $$values ('31600000-0000-4000-8000-000000000001'::uuid)$$,
  'Active viewers can see the reactivated public post'
);
select results_eq(
  $$select user_id from public.profiles where user_id = 'c1600000-0000-4000-8000-000000000003'$$,
  $$values ('c1600000-0000-4000-8000-000000000003'::uuid)$$,
  'Active viewers can see the reactivated profile'
);
select results_eq(
  $$select name from public.tags where name = 'c1a-suspended-tag'$$,
  $$values ('c1a-suspended-tag'::text)$$,
  'Reactivation restores retained tag visibility'
);

select * from finish();

rollback;
