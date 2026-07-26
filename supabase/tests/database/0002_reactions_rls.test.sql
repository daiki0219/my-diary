begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

select has_table('public', 'reactions', 'reactions table exists');
select has_column('public', 'reactions', 'id', 'reactions.id exists');
select has_column('public', 'reactions', 'post_id', 'reactions.post_id exists');
select has_column('public', 'reactions', 'user_id', 'reactions.user_id exists');
select has_column(
  'public',
  'reactions',
  'reaction_type',
  'reactions.reaction_type exists'
);
select has_column(
  'public',
  'reactions',
  'created_at',
  'reactions.created_at exists'
);
select has_column(
  'public',
  'reactions',
  'updated_at',
  'reactions.updated_at exists'
);
select col_is_pk('public', 'reactions', 'id', 'reactions.id is the primary key');

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reactions'::regclass
      and conname = 'my_diary_reactions_post_user_key'
      and contype = 'u'
  ),
  'A user can have only one reaction per post'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reactions'::regclass
      and conname = 'my_diary_reactions_type_check'
      and contype = 'c'
  ),
  'reaction_type has a check constraint'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reactions'::regclass
      and conname = 'my_diary_reactions_post_id_fkey'
      and confrelid = 'public.posts'::regclass
      and confdeltype = 'c'
  ),
  'post_id references posts with cascading physical deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.reactions'::regclass
      and conname = 'my_diary_reactions_user_id_fkey'
      and confrelid = 'public.accounts'::regclass
      and confdeltype = 'c'
  ),
  'user_id references accounts with cascading user deletion'
);

select has_index(
  'public',
  'reactions',
  'my_diary_reactions_post_type_idx',
  'reactions has a post and type index'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.reactions'::regclass),
  'RLS is enabled on reactions'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reactions'
      and policyname = 'my_diary_reactions_select_visible_post'
      and cmd = 'SELECT'
  ),
  'reactions has a SELECT policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reactions'
      and policyname = 'my_diary_reactions_insert_own_visible_post'
      and cmd = 'INSERT'
  ),
  'reactions has an INSERT policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reactions'
      and policyname = 'my_diary_reactions_update_own_visible_post'
      and cmd = 'UPDATE'
  ),
  'reactions has an UPDATE policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reactions'
      and policyname = 'my_diary_reactions_delete_own_visible_post'
      and cmd = 'DELETE'
  ),
  'reactions has a DELETE policy'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'reactions'
  ),
  4::bigint,
  'reactions has only the four expected policies'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.reactions'::regclass
      and tgname = 'my_diary_reactions_set_updated_at'
      and not tgisinternal
  ),
  'reactions uses the existing updated_at trigger function'
);

select ok(
  has_column_privilege('authenticated', 'public.reactions', 'reaction_type', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.reactions', 'post_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.reactions', 'user_id', 'UPDATE'),
  'authenticated can update only reaction_type'
);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'reactions-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'reactions-b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'reactions-c@example.test');

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    '20000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A private',
    'A private post',
    'private',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A public',
    'A public post',
    'public',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B public',
    'B public post',
    'public',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B followers',
    'B followers post',
    'followers',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B private',
    'B private post',
    'private',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000006',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'C followers',
    'C followers post',
    'followers',
    null
  ),
  (
    '20000000-0000-4000-8000-000000000007',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B deleted',
    'B deleted post',
    'public',
    now()
  );

insert into public.follows (follower_id, following_id)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into public.reactions (post_id, user_id, reaction_type)
values
  (
    '20000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'empathy'
  ),
  (
    '20000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'support'
  );

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.reactions$$,
  '42501',
  null,
  'Anonymous users cannot read reactions'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000002',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot add reactions'
);

select throws_ok(
  $$update public.reactions set reaction_type = 'support'$$,
  '42501',
  null,
  'Anonymous users cannot update reactions'
);

select throws_ok(
  $$delete from public.reactions$$,
  '42501',
  null,
  'Anonymous users cannot delete reactions'
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
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000001',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  'A can react to an own private post'
);

select lives_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'support'
    )
  $$,
  'A can react to B public post'
);

select lives_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000004',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'relatable'
    )
  $$,
  'A can react to followed B followers post'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000006',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '42501',
  null,
  'A cannot react to non-followed C followers post'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000005',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '42501',
  null,
  'A cannot react to B private post'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000007',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '42501',
  null,
  'A cannot react to a soft-deleted post'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000002',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'empathy'
    )
  $$,
  '42501',
  null,
  'A cannot add a reaction as B'
);

select throws_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '23505',
  null,
  'The unique constraint rejects a second reaction on the same post'
);

select results_eq(
  $$
    update public.reactions
    set reaction_type = 'relatable'
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    returning reaction_type
  $$,
  $$values ('relatable'::text)$$,
  'A can change the type of an own reaction'
);

select is(
  (
    select count(*)
    from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  1::bigint,
  'Changing a reaction type keeps exactly one row'
);

select results_eq(
  $$
    update public.reactions
    set reaction_type = 'support'
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    returning id
  $$,
  $$select null::uuid where false$$,
  'A cannot update B reaction'
);

select results_eq(
  $$
    delete from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    returning id
  $$,
  $$select null::uuid where false$$,
  'A cannot delete B reaction'
);

select results_eq(
  $$
    delete from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000001'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    returning user_id
  $$,
  $$values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid)$$,
  'A can delete an own reaction'
);

select results_eq(
  $$
    select id
    from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000005'
  $$,
  $$select null::uuid where false$$,
  'A cannot read reactions belonging to B private post'
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
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '20000000-0000-4000-8000-000000000002',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'empathy'
    )
  $$,
  '42501',
  null,
  'A suspended actor cannot add a reaction'
);

select results_eq(
  $$
    update public.reactions
    set reaction_type = 'support'
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    returning id
  $$,
  $$select null::uuid where false$$,
  'A suspended actor cannot change an own reaction'
);

select results_eq(
  $$
    delete from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000003'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    returning id
  $$,
  $$select null::uuid where false$$,
  'A suspended actor cannot remove an own reaction'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
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
    select id
    from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000003'
  $$,
  $$select null::uuid where false$$,
  'A cannot read reaction counts for a suspended author post'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select set_config(
  'request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (
    select count(*)
    from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000003'
  ),
  2::bigint,
  'Reactions become visible again after the author is active'
);

delete from public.follows
where follower_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and following_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select set_config(
  'my_diary.test_unfollow_hidden',
  (
    not exists (
      select 1
      from public.reactions
      where post_id = '20000000-0000-4000-8000-000000000004'
    )
  )::text,
  true
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

select ok(
  current_setting('my_diary.test_unfollow_hidden')::boolean
  and exists (
    select 1
    from public.reactions
    where post_id = '20000000-0000-4000-8000-000000000004'
  ),
  'Unfollowing hides reactions and following again restores them'
);

select * from finish();

rollback;
