begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (id, email)
values
  ('a7000000-0000-4000-8000-000000000001', 'profile-posts-a@example.test'),
  ('b7000000-0000-4000-8000-000000000002', 'profile-posts-b@example.test'),
  ('c7000000-0000-4000-8000-000000000003', 'profile-posts-c@example.test'),
  ('d7000000-0000-4000-8000-000000000004', 'profile-posts-d@example.test'),
  ('e7000000-0000-4000-8000-000000000005', 'profile-posts-e@example.test'),
  ('f7000000-0000-4000-8000-000000000006', 'profile-posts-f@example.test');

insert into public.posts (
  id,
  user_id,
  title,
  body,
  visibility,
  created_at,
  deleted_at
)
values
  (
    '71000000-0000-4000-8000-000000000001',
    'a7000000-0000-4000-8000-000000000001',
    'A public older',
    'A public older body',
    'public',
    '2026-07-29 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000002',
    'a7000000-0000-4000-8000-000000000001',
    'A followers',
    'A followers body',
    'followers',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000003',
    'a7000000-0000-4000-8000-000000000001',
    'A private',
    'A private body',
    'private',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000004',
    'a7000000-0000-4000-8000-000000000001',
    'A deleted',
    'A deleted body',
    'public',
    '2026-07-30 00:00:00+00',
    '2026-07-30 01:00:00+00'
  ),
  (
    '71000000-0000-4000-8000-000000000005',
    'd7000000-0000-4000-8000-000000000004',
    'D public',
    'D public body',
    'public',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000006',
    'f7000000-0000-4000-8000-000000000006',
    'F public',
    'F public body',
    'public',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000007',
    'a7000000-0000-4000-8000-000000000001',
    'A public tied lower',
    'A public tied lower body',
    'public',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000008',
    'a7000000-0000-4000-8000-000000000001',
    'A public tied higher',
    'A public tied higher body',
    'public',
    '2026-07-30 00:00:00+00',
    null
  ),
  (
    '71000000-0000-4000-8000-000000000009',
    'a7000000-0000-4000-8000-000000000001',
    'A visibility changes',
    'A visibility changes body',
    'public',
    '2026-07-28 00:00:00+00',
    null
  );

insert into public.follows (follower_id, following_id)
values (
  'b7000000-0000-4000-8000-000000000002',
  'a7000000-0000-4000-8000-000000000001'
);

update public.accounts
set status = 'suspended'
where user_id in (
  'e7000000-0000-4000-8000-000000000005',
  'f7000000-0000-4000-8000-000000000006'
);

select set_config(
  'request.jwt.claim.sub',
  'c7000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where user_id = 'a7000000-0000-4000-8000-000000000001'
      and deleted_at is null
    order by created_at desc, id desc
  $$,
  $$
    values
      ('71000000-0000-4000-8000-000000000008'::uuid),
      ('71000000-0000-4000-8000-000000000007'::uuid),
      ('71000000-0000-4000-8000-000000000001'::uuid),
      ('71000000-0000-4000-8000-000000000009'::uuid)
  $$,
  'A non-follower gets only the target user public posts in stable newest-first order'
);

select results_eq(
  $$
    select id
    from public.posts
    where id in (
      '71000000-0000-4000-8000-000000000002',
      '71000000-0000-4000-8000-000000000003',
      '71000000-0000-4000-8000-000000000004'
    )
  $$,
  $$select null::uuid where false$$,
  'A non-follower cannot get followers, private, or soft-deleted target posts'
);

select results_eq(
  $$
    select id
    from public.posts
    where user_id = 'a7000000-0000-4000-8000-000000000001'
      and id = '71000000-0000-4000-8000-000000000005'
  $$,
  $$select null::uuid where false$$,
  'The target user filter does not mix in another author post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b7000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select visibility
    from public.posts
    where user_id = 'a7000000-0000-4000-8000-000000000001'
      and deleted_at is null
    group by visibility
    order by visibility
  $$,
  $$
    values
      ('followers'::text),
      ('public'::text)
  $$,
  'A follower gets the target user public and followers posts'
);

select results_eq(
  $$
    select id
    from public.posts
    where id in (
      '71000000-0000-4000-8000-000000000003',
      '71000000-0000-4000-8000-000000000004'
    )
  $$,
  $$select null::uuid where false$$,
  'A follower cannot get private or soft-deleted target posts'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c7000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where user_id = 'f7000000-0000-4000-8000-000000000006'
      and deleted_at is null
  $$,
  $$select null::uuid where false$$,
  'Another user cannot get a suspended author post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e7000000-0000-4000-8000-000000000005',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where user_id = 'a7000000-0000-4000-8000-000000000001'
      and deleted_at is null
  $$,
  $$select null::uuid where false$$,
  'A suspended viewer cannot get another user post'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b7000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

delete from public.follows
where follower_id = 'b7000000-0000-4000-8000-000000000002'
  and following_id = 'a7000000-0000-4000-8000-000000000001';

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000002'
  $$,
  $$select null::uuid where false$$,
  'A follower loses followers-post access immediately after unfollowing'
);

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000001'
  $$,
  $$values ('71000000-0000-4000-8000-000000000001'::uuid)$$,
  'A public target post remains visible after unfollowing'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a7000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.my_diary_update_post_with_tags(
  '71000000-0000-4000-8000-000000000009',
  'A visibility changes',
  'A visibility changes body',
  null,
  'followers',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c7000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000009'
  $$,
  $$select null::uuid where false$$,
  'Changing public to followers immediately hides the post from a non-follower'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'b7000000-0000-4000-8000-000000000002',
  'a7000000-0000-4000-8000-000000000001'
);
select set_config(
  'request.jwt.claim.sub',
  'b7000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000009'
  $$,
  $$values ('71000000-0000-4000-8000-000000000009'::uuid)$$,
  'A follower sees the post after its visibility changes to followers'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a7000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.my_diary_update_post_with_tags(
  '71000000-0000-4000-8000-000000000009',
  'A visibility changes',
  'A visibility changes body',
  null,
  'private',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b7000000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000009'
  $$,
  $$select null::uuid where false$$,
  'Changing followers to private immediately hides the post from a follower'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a7000000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select public.my_diary_update_post_with_tags(
  '71000000-0000-4000-8000-000000000009',
  'A visibility changes',
  'A visibility changes body',
  null,
  'public',
  null
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c7000000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.posts
    where id = '71000000-0000-4000-8000-000000000009'
  $$,
  $$values ('71000000-0000-4000-8000-000000000009'::uuid)$$,
  'Changing private to public immediately exposes the post to a non-follower'
);

reset role;

select * from finish();

rollback;
