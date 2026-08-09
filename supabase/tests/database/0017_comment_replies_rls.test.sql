begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

select has_column(
  'public', 'comments', 'parent_comment_id',
  'comments.parent_comment_id exists'
);
select col_type_is(
  'public', 'comments', 'parent_comment_id', 'uuid',
  'comments.parent_comment_id is uuid'
);
select col_is_null(
  'public', 'comments', 'parent_comment_id',
  'comments.parent_comment_id is nullable'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.comments'::regclass
      and contype = 'f'
      and confrelid = 'public.comments'::regclass
  ),
  'Replies avoid a self FK that would cascade, detach, or block physical deletion'
);

select has_index(
  'public',
  'comments',
  'my_diary_comments_post_parent_created_id_idx',
  'comments has the stable reply lookup index'
);

select ok(
  (
    select indexdef like '%(post_id, parent_comment_id, created_at, id)%'
      and indexdef like '%WHERE (deleted_at IS NULL)%'
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'comments'
      and indexname = 'my_diary_comments_post_parent_created_id_idx'
  ),
  'The reply index covers post, parent, and stable order for live comments'
);

select ok(
  (
    select relrowsecurity and not relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.comments'::regclass
  ),
  'comments keeps RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'comments'
  ),
  2::bigint,
  'comments keeps only the existing SELECT and INSERT policies'
);

select ok(
  has_column_privilege(
    'authenticated', 'public.comments', 'parent_comment_id', 'INSERT'
  )
  and not has_column_privilege(
    'authenticated', 'public.comments', 'parent_comment_id', 'UPDATE'
  ),
  'authenticated can set reply parents only during INSERT'
);

select ok(
  not has_column_privilege(
    'anon', 'public.comments', 'parent_comment_id', 'INSERT'
  ),
  'anon cannot set reply parents'
);

select has_function(
  'my_diary_private',
  'my_diary_validate_comment_parent',
  array[]::text[],
  'The private reply validator exists'
);

select ok(
  (
    select function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
      and pg_catalog.pg_get_functiondef(function_definition.oid)
        like '%for update%'
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_comment_parent'
      and function_definition.proargtypes = ''::oidvector
  ),
  'The validator is volatile, hardened, postgres-owned, and locks the parent'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_definition.proacl,
        pg_catalog.acldefault('f', function_definition.proowner)
      )
    ) as function_acl
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_comment_parent'
      and function_definition.proargtypes = ''::oidvector
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'my_diary_private.my_diary_validate_comment_parent()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_validate_comment_parent()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_validate_comment_parent()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_validate_comment_parent()',
    'EXECUTE'
  ),
  'No application role can execute the trigger function directly'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger_definition
    join pg_catalog.pg_proc as function_definition
      on function_definition.oid = trigger_definition.tgfoid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where trigger_definition.tgrelid = 'public.comments'::regclass
      and trigger_definition.tgname = 'my_diary_comments_validate_parent'
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgisinternal
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        like '%AFTER INSERT OR UPDATE%'
      and namespace.nspname = 'my_diary_private'
      and function_definition.proname = 'my_diary_validate_comment_parent'
  ),
  'The reply validator runs after comments RLS checks'
);

select hasnt_table(
  'public', 'notifications',
  'C2a does not add notifications'
);

insert into auth.users (id, email)
values
  ('a1700000-0000-4000-8000-000000000001', 'c2a-a@example.test'),
  ('b1700000-0000-4000-8000-000000000002', 'c2a-b@example.test'),
  ('c1700000-0000-4000-8000-000000000003', 'c2a-c@example.test'),
  ('d1700000-0000-4000-8000-000000000004', 'c2a-d@example.test');

insert into public.posts (
  id, user_id, title, body, visibility, deleted_at
)
values
  (
    '11700000-0000-4000-8000-000000000001',
    'b1700000-0000-4000-8000-000000000002',
    'C2a B public', 'C2a B public body', 'public', null
  ),
  (
    '11700000-0000-4000-8000-000000000002',
    'b1700000-0000-4000-8000-000000000002',
    'C2a B followers', 'C2a B followers body', 'followers', null
  ),
  (
    '11700000-0000-4000-8000-000000000003',
    'b1700000-0000-4000-8000-000000000002',
    'C2a B private', 'C2a B private body', 'private', null
  ),
  (
    '11700000-0000-4000-8000-000000000004',
    'b1700000-0000-4000-8000-000000000002',
    'C2a B deleted', 'C2a B deleted body', 'public', now()
  ),
  (
    '21700000-0000-4000-8000-000000000001',
    'c1700000-0000-4000-8000-000000000003',
    'C2a C public', 'C2a C public body', 'public', null
  );

insert into public.follows (follower_id, following_id)
values (
  'a1700000-0000-4000-8000-000000000001',
  'b1700000-0000-4000-8000-000000000002'
);

insert into public.comments (
  id, post_id, user_id, body, parent_comment_id
)
values
  (
    '31700000-0000-4000-8000-000000000001',
    '11700000-0000-4000-8000-000000000001',
    'b1700000-0000-4000-8000-000000000002',
    'B top-level public', null
  ),
  (
    '31700000-0000-4000-8000-000000000002',
    '11700000-0000-4000-8000-000000000002',
    'b1700000-0000-4000-8000-000000000002',
    'B top-level followers', null
  ),
  (
    '31700000-0000-4000-8000-000000000003',
    '21700000-0000-4000-8000-000000000001',
    'c1700000-0000-4000-8000-000000000003',
    'C top-level public', null
  ),
  (
    '31700000-0000-4000-8000-000000000004',
    '11700000-0000-4000-8000-000000000001',
    'c1700000-0000-4000-8000-000000000003',
    'C deleted parent', null
  ),
  (
    '31700000-0000-4000-8000-000000000005',
    '11700000-0000-4000-8000-000000000001',
    'd1700000-0000-4000-8000-000000000004',
    'D non-active parent', null
  ),
  (
    '31700000-0000-4000-8000-000000000006',
    '11700000-0000-4000-8000-000000000003',
    'b1700000-0000-4000-8000-000000000002',
    'B parent on private post', null
  ),
  (
    '31700000-0000-4000-8000-000000000007',
    '11700000-0000-4000-8000-000000000004',
    'b1700000-0000-4000-8000-000000000002',
    'B parent on deleted post', null
  ),
  (
    '31700000-0000-4000-8000-000000000008',
    '11700000-0000-4000-8000-000000000001',
    'c1700000-0000-4000-8000-000000000003',
    'C live parent on B post', null
  );

update public.comments
set deleted_at = now()
where id = '31700000-0000-4000-8000-000000000004';

update public.accounts
set status = 'suspended'
where user_id = 'd1700000-0000-4000-8000-000000000004';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    )
    values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'A top-level regression', null
    )
  $$,
  'Existing top-level comment creation still works'
);

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    )
    values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'A reply to B',
      '31700000-0000-4000-8000-000000000001'
    )
  $$,
  'A can reply to another active user top-level comment'
);

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    )
    values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'A reply to own top-level',
      (
        select id
        from public.comments
        where body = 'A top-level regression'
      )
    )
  $$,
  'A can reply to an own top-level comment'
);

select results_eq(
  $$
    select parent_comment_id
    from public.comments
    where body = 'A top-level regression'
  $$,
  $$values (null::uuid)$$,
  'Top-level comments retain a null parent'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'missing parent',
      '99999999-0000-4000-8000-000000000999'
    )
  $$,
  '23514', 'invalid parent comment',
  'A nonexistent parent gets the generic parent validation failure'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'cross-post reply',
      '31700000-0000-4000-8000-000000000003'
    )
  $$,
  '23514', 'invalid parent comment',
  'A parent from another post is rejected by the DB trigger'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'hidden cross-post reply probe',
      '31700000-0000-4000-8000-000000000006'
    )
  $$,
  '23514', 'invalid parent comment',
  'An inaccessible private-post parent gets the same generic failure'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'grandchild reply',
      (
        select id
        from public.comments
        where body = 'A reply to B'
      )
    )
  $$,
  '23514', 'invalid parent comment',
  'A reply to a reply is rejected by the DB trigger'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'reply to deleted parent',
      '31700000-0000-4000-8000-000000000004'
    )
  $$,
  '23514', 'invalid parent comment',
  'A new reply to a soft-deleted parent is rejected'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'reply to non-active parent author',
      '31700000-0000-4000-8000-000000000005'
    )
  $$,
  '23514', 'invalid parent comment',
  'A new reply to a non-active author comment is rejected'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'b1700000-0000-4000-8000-000000000002',
      'spoofed reply',
      '31700000-0000-4000-8000-000000000001'
    )
  $$,
  '42501', null,
  'A cannot create a reply in another user name'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000003',
      'a1700000-0000-4000-8000-000000000001',
      'reply on private post',
      '31700000-0000-4000-8000-000000000006'
    )
  $$,
  '42501', null,
  'Post RLS rejects a reply on an inaccessible private post'
);

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000004',
      'a1700000-0000-4000-8000-000000000001',
      'reply on deleted post',
      '31700000-0000-4000-8000-000000000007'
    )
  $$,
  '42501', null,
  'Post RLS rejects a reply on a soft-deleted post'
);

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000002',
      'a1700000-0000-4000-8000-000000000001',
      'A followers reply',
      '31700000-0000-4000-8000-000000000002'
    )
  $$,
  'A can reply on a currently visible followers post'
);

select is(
  public.my_diary_soft_delete_comment(
    '31700000-0000-4000-8000-000000000001'
  ),
  false,
  'A cannot soft-delete another user parent comment'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b1700000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  public.my_diary_soft_delete_comment(
    '31700000-0000-4000-8000-000000000001'
  ),
  true,
  'The parent author can soft-delete a parent that has replies'
);

reset role;
select ok(
  exists (
    select 1
    from public.comments
    where body = 'A reply to B'
      and parent_comment_id = '31700000-0000-4000-8000-000000000001'
      and deleted_at is null
  ),
  'Soft-deleting a parent retains the existing reply row and relation'
);

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'reply after parent deletion',
      '31700000-0000-4000-8000-000000000001'
    )
  $$,
  '23514', null,
  'No new reply can be added after parent soft deletion'
);

select is(
  public.my_diary_soft_delete_comment(
    (
      select id
      from public.comments
      where body = 'A reply to B'
    )
  ),
  true,
  'A can soft-delete an own reply'
);

reset role;
select ok(
  exists (
    select 1
    from public.comments
    where body = 'A reply to B'
      and deleted_at is not null
  ),
  'Soft-deleting a reply retains the row as deleted'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'anonymous reply',
      '31700000-0000-4000-8000-000000000001'
    )
  $$,
  '42501', null,
  'Anonymous users cannot create replies'
);

reset role;
update public.accounts
set status = 'suspended'
where user_id = 'a1700000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000002',
      'a1700000-0000-4000-8000-000000000001',
      'suspended viewer reply',
      '31700000-0000-4000-8000-000000000002'
    )
  $$,
  '42501', null,
  'A suspended viewer cannot create replies'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a1700000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select parent_comment_id from public.comments
    where body = 'A followers reply'
  $$,
  $$values ('31700000-0000-4000-8000-000000000002'::uuid)$$,
  'A can read a reply on a followed followers post'
);

delete from public.follows
where follower_id = 'a1700000-0000-4000-8000-000000000001'
  and following_id = 'b1700000-0000-4000-8000-000000000002';

select is_empty(
  $$
    select id from public.comments
    where body = 'A followers reply'
  $$,
  'Unfollowing hides an existing reply with its followers post'
);

reset role;
update public.posts
set visibility = 'public'
where id = '11700000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select parent_comment_id from public.comments
    where body = 'A followers reply'
  $$,
  $$values ('31700000-0000-4000-8000-000000000002'::uuid)$$,
  'Changing the post to public reveals its existing reply'
);

reset role;
update public.posts
set visibility = 'private'
where id = '11700000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is_empty(
  $$
    select id from public.comments
    where body = 'A followers reply'
  $$,
  'Changing the post to private hides its existing reply'
);

reset role;
update public.posts
set visibility = 'public'
where id = '11700000-0000-4000-8000-000000000002';
update public.accounts
set status = 'suspended'
where user_id = 'a1700000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is_empty(
  $$select id from public.comments$$,
  'A non-active viewer cannot read replies even on public posts'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a1700000-0000-4000-8000-000000000001';
update public.accounts
set status = 'suspended'
where user_id = 'b1700000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is_empty(
  $$
    select id from public.comments
    where body = 'A followers reply'
  $$,
  'A non-active post author hides existing replies through post RLS'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'b1700000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1700000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000001',
      'A reply to C for physical deletion test',
      '31700000-0000-4000-8000-000000000008'
    )
  $$,
  'A can create a reply used for physical parent deletion regression'
);

reset role;
delete from auth.users
where id = 'c1700000-0000-4000-8000-000000000003';

select ok(
  exists (
    select 1
    from public.comments
    where body = 'A reply to C for physical deletion test'
      and parent_comment_id = '31700000-0000-4000-8000-000000000008'
  )
  and not exists (
    select 1
    from public.comments
    where id = '31700000-0000-4000-8000-000000000008'
  ),
  'Physical parent-author deletion preserves another user reply as a reply'
);

select throws_ok(
  $$
    update public.comments
    set parent_comment_id = (
      select id
      from public.comments
      where body = 'A reply to own top-level'
    )
    where body = 'A reply to C for physical deletion test'
  $$,
  '23514', 'invalid parent comment',
  'Privileged direct relation updates cannot create grandchildren'
);

select * from finish();

rollback;
