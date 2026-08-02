begin;

create extension if not exists pgtap with schema extensions;

select plan(63);

select has_table('public', 'comments', 'comments table exists');
select has_column('public', 'comments', 'id', 'comments.id exists');
select has_column('public', 'comments', 'post_id', 'comments.post_id exists');
select has_column('public', 'comments', 'user_id', 'comments.user_id exists');
select has_column('public', 'comments', 'body', 'comments.body exists');
select has_column(
  'public',
  'comments',
  'created_at',
  'comments.created_at exists'
);
select has_column(
  'public',
  'comments',
  'updated_at',
  'comments.updated_at exists'
);
select has_column(
  'public',
  'comments',
  'deleted_at',
  'comments.deleted_at exists'
);
select col_is_pk('public', 'comments', 'id', 'comments.id is the primary key');

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.comments'::regclass
      and conname = 'my_diary_comments_post_id_fkey'
      and confrelid = 'public.posts'::regclass
      and confdeltype = 'c'
  ),
  'post_id references posts with cascading physical deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.comments'::regclass
      and conname = 'my_diary_comments_user_id_fkey'
      and confrelid = 'public.accounts'::regclass
      and confdeltype = 'c'
  ),
  'user_id references accounts with cascading user deletion'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.comments'::regclass
      and conname = 'my_diary_comments_body_check'
      and contype = 'c'
  ),
  'body has a check constraint'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.comments'::regclass
      and conname = 'my_diary_comments_deleted_at_check'
      and contype = 'c'
  ),
  'deleted_at has a check constraint'
);

select has_index(
  'public',
  'comments',
  'my_diary_comments_post_created_id_idx',
  'comments has the ordered partial post index'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.comments'::regclass
  ),
  'RLS is enabled on comments'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
      and policyname = 'my_diary_comments_select_visible'
      and cmd = 'SELECT'
  ),
  'comments has a SELECT policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
      and policyname = 'my_diary_comments_insert_own_visible_post'
      and cmd = 'INSERT'
  ),
  'comments has an INSERT policy'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
  ),
  2::bigint,
  'comments has only the two expected policies'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
      and cmd in ('UPDATE', 'DELETE')
  ),
  'comments has no direct UPDATE or DELETE policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.comments'::regclass
      and tgname = 'my_diary_comments_set_updated_at'
      and not tgisinternal
  ),
  'comments uses the existing updated_at trigger function'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.comments',
    'body',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.comments',
    'post_id',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.comments',
    'user_id',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.comments',
    'created_at',
    'UPDATE'
  )
  and not has_column_privilege(
    'authenticated',
    'public.comments',
    'deleted_at',
    'UPDATE'
  ),
  'authenticated cannot directly update any comment column'
);

select ok(
  not has_table_privilege('authenticated', 'public.comments', 'DELETE'),
  'authenticated has no physical DELETE privilege'
);

select has_function(
  'my_diary_private',
  'my_diary_can_view_post',
  array['uuid', 'text', 'timestamp with time zone'],
  'The private post visibility function exists'
);

select hasnt_function(
  'my_diary_private',
  'my_diary_can_view_post',
  array['uuid'],
  'The obsolete ID-based visibility function no longer exists'
);

select has_function(
  'public',
  'my_diary_soft_delete_comment',
  array['uuid'],
  'The comment soft-delete RPC exists'
);

select ok(
  (
    select function.prosecdef
      and function.proconfig @> array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_can_view_post'
      and function.proargtypes = '2950 25 1184'::oidvector
  ),
  'The visibility function is a hardened postgres-owned SECURITY DEFINER'
);

select ok(
  (
    select function.prosecdef
      and function.proconfig @> array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'my_diary_soft_delete_comment'
      and function.proargtypes = '2950'::oidvector
  ),
  'The soft-delete RPC is a hardened postgres-owned SECURITY DEFINER'
);

select ok(
  not has_function_privilege(
    'anon',
    'my_diary_private.my_diary_can_view_post(uuid,text,timestamp with time zone)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_can_view_post(uuid,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'Only authenticated RLS evaluation can execute the private visibility function'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.my_diary_soft_delete_comment(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.my_diary_soft_delete_comment(uuid)',
    'EXECUTE'
  ),
  'Only authenticated users can execute the soft-delete RPC'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id,
      user_id,
      body,
      created_at,
      deleted_at
    )
    values (
      gen_random_uuid(),
      gen_random_uuid(),
      'invalid deleted timestamp',
      now(),
      now() - interval '1 second'
    )
  $$,
  '23514',
  null,
  'deleted_at cannot be earlier than created_at'
);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'comments-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'comments-b@example.test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'comments-c@example.test');

insert into public.posts (id, user_id, title, body, visibility, deleted_at)
values
  (
    '30000000-0000-4000-8000-000000000001',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A private',
    'A private post',
    'private',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A followers',
    'A followers post',
    'followers',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'A public',
    'A public post',
    'public',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B public',
    'B public post',
    'public',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B followers',
    'B followers post',
    'followers',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000006',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B private',
    'B private post',
    'private',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000007',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B deleted',
    'B deleted post',
    'public',
    now()
  ),
  (
    '30000000-0000-4000-8000-000000000008',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'C public',
    'C public post',
    'public',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000009',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'C followers',
    'C followers post',
    'followers',
    null
  ),
  (
    '30000000-0000-4000-8000-000000000010',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'C private',
    'C private post',
    'private',
    null
  );

insert into public.follows (follower_id, following_id)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into public.comments (id, post_id, user_id, body)
values
  (
    '40000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B comment on B public'
  ),
  (
    '40000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B comment on A public'
  ),
  (
    '40000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000006',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B comment on B private'
  ),
  (
    '40000000-0000-4000-8000-000000000004',
    '30000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'B comment on B followers'
  );

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.comments$$,
  '42501',
  null,
  'Anonymous users cannot read comments'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'anonymous comment'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot add comments'
);

select throws_ok(
  $$update public.comments set deleted_at = now()$$,
  '42501',
  null,
  'Anonymous users cannot soft-delete comments'
);

select throws_ok(
  $$delete from public.comments$$,
  '42501',
  null,
  'Anonymous users cannot physically delete comments'
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
    select public.my_diary_create_post_with_tags(
      null,
      'INSERT RETURNING regression',
      null,
      'private',
      null
    ) is not null
  $$,
  $$values (true)$$,
  'A can create an own post and receive a uuid through the atomic RPC'
);

select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000001',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'A on own private'
    )
  $$,
  'A can comment on an own private post'
);

select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values
      (
        '30000000-0000-4000-8000-000000000002',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'A on own followers'
      ),
      (
        '30000000-0000-4000-8000-000000000003',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'A on own public'
      )
  $$,
  'A can comment on own followers and public posts'
);

select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values
      (
        '30000000-0000-4000-8000-000000000004',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'A on B public'
      ),
      (
        '30000000-0000-4000-8000-000000000005',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'A on followed B followers'
      ),
      (
        '30000000-0000-4000-8000-000000000008',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'A on C public'
      )
  $$,
  'A can comment on visible posts by other users'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000009',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'A on non-followed C followers'
    )
  $$,
  '42501',
  null,
  'A cannot comment on non-followed C followers post'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000006',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'A on B private'
    )
  $$,
  '42501',
  null,
  'A cannot comment on B private post'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000010',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'A on C private'
    )
  $$,
  '42501',
  null,
  'A cannot comment on C private post'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000007',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'A on deleted post'
    )
  $$,
  '42501',
  null,
  'A cannot comment on a soft-deleted post'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'spoofed B comment'
    )
  $$,
  '42501',
  null,
  'A cannot add a comment as B'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ''
    )
  $$,
  '23514',
  null,
  'Empty comment bodies are rejected'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      E' \n\t '
    )
  $$,
  '23514',
  null,
  'Whitespace-only comment bodies are rejected'
);

select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      repeat('あ', 1000)
    )
  $$,
  'A 1000-character comment is accepted'
);

select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      repeat('あ', 1001)
    )
  $$,
  '23514',
  null,
  'A 1001-character comment is rejected'
);

select throws_ok(
  $$
    update public.comments
    set body = 'edited'
    where id = '40000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Comment body editing is not permitted'
);

select throws_ok(
  $$
    update public.comments
    set post_id = '30000000-0000-4000-8000-000000000004'
    where id = '40000000-0000-4000-8000-000000000002'
  $$,
  '42501',
  null,
  'Moving a comment to another post is not permitted'
);

select is(
  public.my_diary_soft_delete_comment(
    '40000000-0000-4000-8000-000000000001'
  ),
  false,
  'A cannot soft-delete B comment'
);

select is(
  public.my_diary_soft_delete_comment(
    '40000000-0000-4000-8000-000000000002'
  ),
  false,
  'A cannot delete B comment even as the post author'
);

select throws_ok(
  $$delete from public.comments where user_id = auth.uid()$$,
  '42501',
  null,
  'A cannot physically delete an own comment'
);

select is(
  public.my_diary_soft_delete_comment(
    (
      select id
      from public.comments
      where post_id = '30000000-0000-4000-8000-000000000001'
        and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  ),
  true,
  'A can soft-delete an own undeleted comment'
);

reset role;

select ok(
  (
    select deleted_at is not null
      and updated_at = deleted_at
      and updated_at >= created_at
    from public.comments
    where post_id = '30000000-0000-4000-8000-000000000001'
      and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  'Soft deletion sets deleted_at and updates updated_at'
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
    select id
    from public.comments
    where post_id = '30000000-0000-4000-8000-000000000001'
  $$,
  $$select null::uuid where false$$,
  'A cannot read an own soft-deleted comment'
);

select throws_ok(
  $$
    update public.comments
    set deleted_at = null
  $$,
  '42501',
  null,
  'A cannot restore a soft-deleted comment'
);

select results_eq(
  $$
    select id
    from public.comments
    where post_id = '30000000-0000-4000-8000-000000000006'
  $$,
  $$select null::uuid where false$$,
  'A cannot read comments or counts for B private post'
);

delete from public.follows
where follower_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and following_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select set_config(
  'my_diary.comments_hidden_after_unfollow',
  (
    not exists (
      select 1
      from public.comments
      where post_id = '30000000-0000-4000-8000-000000000005'
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
  current_setting('my_diary.comments_hidden_after_unfollow')::boolean
  and exists (
    select 1
    from public.comments
    where post_id = '30000000-0000-4000-8000-000000000005'
  ),
  'Unfollowing hides comments and following again restores them'
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
    insert into public.comments (post_id, user_id, body)
    values (
      '30000000-0000-4000-8000-000000000003',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'suspended actor'
    )
  $$,
  '42501',
  null,
  'A suspended actor cannot add a comment'
);

select is(
  public.my_diary_soft_delete_comment(
    (
      select id
      from public.comments
      where post_id = '30000000-0000-4000-8000-000000000003'
        and user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      limit 1
    )
  ),
  false,
  'A suspended actor cannot soft-delete an own comment'
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
    from public.comments
    where post_id = '30000000-0000-4000-8000-000000000004'
  $$,
  $$select null::uuid where false$$,
  'A cannot read comments or counts for a suspended post author'
);

select results_eq(
  $$
    select id
    from public.comments
    where id = '40000000-0000-4000-8000-000000000002'
  $$,
  $$select null::uuid where false$$,
  'A cannot read a comment written by a suspended commenter'
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

select ok(
  exists (
    select 1
    from public.comments
    where id = '40000000-0000-4000-8000-000000000002'
  ),
  'A sees the comment again after its author is active'
);

select * from finish();

rollback;
