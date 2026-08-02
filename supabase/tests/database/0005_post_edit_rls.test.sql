begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'edit-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'edit-b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'edit-c@example.test');

insert into public.posts (
  id,
  user_id,
  title,
  body,
  mood,
  visibility,
  updated_at,
  deleted_at
)
values
  (
    '50000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Editable',
    'Editable body',
    'neutral',
    'public',
    now() - interval '1 day',
    null
  ),
  (
    '50000000-0000-4000-8000-000000000002',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Deleted',
    'Deleted body',
    null,
    'public',
    now(),
    now()
  ),
  (
    '50000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B public',
    'B body',
    null,
    'public',
    now(),
    null
  ),
  (
    '50000000-0000-4000-8000-000000000004',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Boundaries',
    'Boundary body',
    null,
    'private',
    now(),
    null
  );

insert into public.follows (follower_id, following_id)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

insert into public.reactions (id, post_id, user_id, reaction_type)
values (
  '60000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000001',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'empathy'
);

insert into public.comments (id, post_id, user_id, body)
values (
  '70000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000001',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'Visible with the post'
);

select ok(
  not pg_catalog.has_any_column_privilege(
    'authenticated', 'public.posts', 'UPDATE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_post_with_tags(uuid,text,text,text,text,text[])',
    'EXECUTE'
  ),
  'authenticated updates posts only through the atomic RPC'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.posts',
    'user_id',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.posts',
    'deleted_at',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.posts',
    'created_at',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.posts',
    'updated_at',
    'UPDATE'
  ),
  'authenticated cannot update protected post columns'
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
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Edited title',
      'Editable body',
      'neutral',
      'public',
      null
    )
  $$,
  $$values ('50000000-0000-4000-8000-000000000001'::uuid)$$,
  'An owner can update title'
);

select results_eq(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Edited title',
      E'Edited\nbody',
      'neutral',
      'public',
      null
    )
  $$,
  $$values ('50000000-0000-4000-8000-000000000001'::uuid)$$,
  'An owner can update body while preserving internal newlines'
);

select results_eq(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Edited title',
      E'Edited\nbody',
      'calm',
      'public',
      null
    )
  $$,
  $$values ('50000000-0000-4000-8000-000000000001'::uuid)$$,
  'An owner can update mood'
);

select results_eq(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Edited title',
      E'Edited\nbody',
      'calm',
      'followers',
      null
    )
  $$,
  $$values ('50000000-0000-4000-8000-000000000001'::uuid)$$,
  'An owner can update visibility'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Changed by B',
      E'Edited\nbody',
      'calm',
      'followers',
      null
    )
  $$,
  '42501',
  null,
  'Another user cannot update the post'
);

reset role;
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

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000001',
      'Changed while suspended',
      E'Edited\nbody',
      'calm',
      'followers',
      null
    )
  $$,
  '42501',
  null,
  'A suspended owner cannot update the post'
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

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000002',
      'Changed after deletion',
      'Deleted body',
      null,
      'public',
      null
    )
  $$,
  '42501',
  null,
  'An owner cannot update a soft-deleted post'
);

select lives_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 120),
      'Boundary body',
      null,
      'private',
      null
    )
  $$,
  'A 120-character title is accepted'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 121),
      'Boundary body',
      null,
      'private',
      null
    )
  $$,
  '22023',
  null,
  'A 121-character title is rejected'
);

select lives_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 120),
      repeat('あ', 10000),
      null,
      'private',
      null
    )
  $$,
  'A 10000-character body is accepted'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 120),
      repeat('あ', 10001),
      null,
      'private',
      null
    )
  $$,
  '22023',
  null,
  'A 10001-character body is rejected'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 120),
      repeat('あ', 10000),
      'invalid',
      'private',
      null
    )
  $$,
  '22023',
  null,
  'An invalid mood is rejected'
);

select throws_ok(
  $$
    select public.my_diary_update_post_with_tags(
      '50000000-0000-4000-8000-000000000004',
      repeat('あ', 120),
      repeat('あ', 10000),
      null,
      'invalid',
      null
    )
  $$,
  '22023',
  null,
  'An invalid visibility is rejected'
);

select ok(
  (
    select updated_at > now() - interval '1 minute'
    from public.posts
    where id = '50000000-0000-4000-8000-000000000001'
  ),
  'Updating an editable field refreshes updated_at'
);

select public.my_diary_update_post_with_tags(
  '50000000-0000-4000-8000-000000000001',
  'Edited title',
  E'Edited\nbody',
  'calm',
  'private',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where id = '50000000-0000-4000-8000-000000000001'
  $$,
  $$select null::uuid where false$$,
  'Changing public to private immediately hides the post from another user'
);

select ok(
  not exists (
    select 1
    from public.reactions
    where post_id = '50000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from public.comments
    where post_id = '50000000-0000-4000-8000-000000000001'
  ),
  'Private visibility also hides related reactions and comments'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.my_diary_update_post_with_tags(
  '50000000-0000-4000-8000-000000000001',
  'Edited title',
  E'Edited\nbody',
  'calm',
  'followers',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select set_config(
  'my_diary.follower_can_see_edited_post',
  (
    exists (
      select 1
      from public.posts
      where id = '50000000-0000-4000-8000-000000000001'
    )
  )::text,
  true
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select ok(
  current_setting('my_diary.follower_can_see_edited_post')::boolean
  and not exists (
    select 1
    from public.posts
    where id = '50000000-0000-4000-8000-000000000001'
  ),
  'Changing private to followers makes the post visible only to a follower'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.my_diary_update_post_with_tags(
  '50000000-0000-4000-8000-000000000001',
  'Edited title',
  E'Edited\nbody',
  'calm',
  'public',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select ok(
  exists (
    select 1
    from public.posts
    where id = '50000000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1
    from public.reactions
    where post_id = '50000000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1
    from public.comments
    where post_id = '50000000-0000-4000-8000-000000000001'
  ),
  'Changing followers to public exposes the post and related activity'
);

reset role;

select * from finish();

rollback;
