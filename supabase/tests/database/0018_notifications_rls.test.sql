begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

select has_table(
  'public', 'notifications',
  'notifications table exists'
);
select columns_are(
  'public',
  'notifications',
  array[
    'id',
    'recipient_user_id',
    'actor_user_id',
    'notification_type',
    'target_post_id',
    'target_comment_id',
    'is_read',
    'created_at',
    'exchange_invitation_id',
    'exchange_diary_id',
    'exchange_entry_id'
  ],
  'notifications has only the expected columns'
);
select col_type_is(
  'public', 'notifications', 'id', 'uuid',
  'notifications.id is uuid'
);
select col_type_is(
  'public', 'notifications', 'recipient_user_id', 'uuid',
  'recipient_user_id is uuid'
);
select col_type_is(
  'public', 'notifications', 'actor_user_id', 'uuid',
  'actor_user_id is uuid'
);
select col_type_is(
  'public', 'notifications', 'notification_type', 'text',
  'notification_type is text'
);
select col_type_is(
  'public', 'notifications', 'target_post_id', 'uuid',
  'target_post_id is uuid'
);
select col_type_is(
  'public', 'notifications', 'target_comment_id', 'uuid',
  'target_comment_id is uuid'
);
select col_type_is(
  'public', 'notifications', 'is_read', 'boolean',
  'is_read is boolean'
);
select col_type_is(
  'public', 'notifications', 'created_at', 'timestamp with time zone',
  'created_at is timestamptz'
);
select col_not_null(
  'public', 'notifications', 'recipient_user_id',
  'recipient_user_id is required'
);
select col_not_null(
  'public', 'notifications', 'actor_user_id',
  'actor_user_id is required'
);
select col_not_null(
  'public', 'notifications', 'notification_type',
  'notification_type is required'
);
select col_is_null(
  'public', 'notifications', 'target_post_id',
  'target_post_id is nullable'
);
select col_is_null(
  'public', 'notifications', 'target_comment_id',
  'target_comment_id is nullable'
);
select col_not_null(
  'public', 'notifications', 'is_read',
  'is_read is required'
);
select col_default_is(
  'public', 'notifications', 'is_read', 'false',
  'is_read defaults to false'
);
select col_not_null(
  'public', 'notifications', 'created_at',
  'created_at is required'
);
select ok(
  (
    select column_default like '%gen_random_uuid%'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notifications'
      and column_name = 'id'
  )
  and (
    select column_default = 'now()'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notifications'
      and column_name = 'created_at'
  ),
  'id and created_at use server-side defaults'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'my_diary_notifications_type_check'
      and contype = 'c'
  ),
  'notification_type has a named CHECK'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'my_diary_notifications_not_self_check'
      and contype = 'c'
  ),
  'self notifications have a named CHECK'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'my_diary_notifications_target_shape_check'
      and contype = 'c'
  ),
  'notification targets have a named shape CHECK'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and contype = 'f'
      and confrelid = 'public.accounts'::regclass
      and confdeltype = 'c'
  ),
  2::bigint,
  'recipient and actor reference accounts with cascading deletion'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'my_diary_notifications_target_post_id_fkey'
      and confrelid = 'public.posts'::regclass
      and confdeltype = 'c'
  ),
  'target_post_id references posts with cascading deletion'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'my_diary_notifications_target_comment_id_fkey'
      and confrelid = 'public.comments'::regclass
      and confdeltype = 'c'
  ),
  'target_comment_id references comments with cascading deletion'
);
select hasnt_column(
  'public', 'notifications', 'reaction_id',
  'notifications does not couple to reaction rows'
);
select hasnt_column(
  'public', 'notifications', 'follow_id',
  'notifications does not couple to follow rows'
);
select has_index(
  'public',
  'notifications',
  'my_diary_notifications_recipient_created_id_idx',
  'notifications has the stable recipient list index'
);
select ok(
  (
    select indexdef like
      '%(recipient_user_id, created_at DESC, id DESC)%'
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'notifications'
      and indexname = 'my_diary_notifications_recipient_created_id_idx'
  ),
  'the notification list index covers recipient and stable descending order'
);

select ok(
  (
    select relrowsecurity and not relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.notifications'::regclass
  ),
  'notifications has RLS explicitly enabled'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  ),
  2::bigint,
  'notifications has only SELECT and UPDATE policies'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'my_diary_notifications_select_recipient'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_is_account_active%'
      and qual like '%target_post_id%'
  ),
  'SELECT policy checks recipient, active users, and current post visibility'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'my_diary_notifications_update_read_state'
      and cmd = 'UPDATE'
      and roles = array['authenticated']::name[]
      and qual like '%my_diary_is_account_active%'
      and with_check like '%target_post_id%'
  ),
  'UPDATE policy preserves the same current visibility boundary'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and cmd in ('INSERT', 'DELETE')
  ),
  'notifications has no public creation or deletion policy'
);
select ok(
  has_table_privilege('authenticated', 'public.notifications', 'SELECT')
  and has_column_privilege(
    'authenticated', 'public.notifications', 'is_read', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.notifications', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.notifications', 'DELETE'
  ),
  'authenticated receives SELECT and UPDATE(is_read) only'
);
select ok(
  not has_column_privilege(
    'authenticated', 'public.notifications', 'recipient_user_id', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.notifications', 'actor_user_id', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.notifications', 'notification_type', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.notifications', 'target_post_id', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.notifications', 'target_comment_id', 'UPDATE'
  )
  and not has_column_privilege(
    'authenticated', 'public.notifications', 'created_at', 'UPDATE'
  ),
  'authenticated cannot update notification identity, type, targets, or time'
);
select ok(
  not has_table_privilege(
    'anon', 'public.notifications', 'SELECT, INSERT, UPDATE, DELETE'
  ),
  'anon has no notification table privileges'
);

insert into auth.users (id, email)
values
  ('a1800000-0000-4000-8000-000000000001', 'c2c-a@example.test'),
  ('b1800000-0000-4000-8000-000000000002', 'c2c-b@example.test'),
  ('c1800000-0000-4000-8000-000000000003', 'c2c-c@example.test'),
  ('d1800000-0000-4000-8000-000000000004', 'c2c-d@example.test');

insert into public.posts (
  id, user_id, title, body, visibility, deleted_at
)
values
  (
    '11800000-0000-4000-8000-000000000001',
    'a1800000-0000-4000-8000-000000000001',
    'A private', 'A private body', 'private', null
  ),
  (
    '11800000-0000-4000-8000-000000000002',
    'b1800000-0000-4000-8000-000000000002',
    'B followers', 'B followers body', 'followers', null
  ),
  (
    '11800000-0000-4000-8000-000000000003',
    'b1800000-0000-4000-8000-000000000002',
    'B private', 'B private body', 'private', null
  ),
  (
    '11800000-0000-4000-8000-000000000004',
    'b1800000-0000-4000-8000-000000000002',
    'B deleted', 'B deleted body', 'public', now()
  ),
  (
    '11800000-0000-4000-8000-000000000005',
    'b1800000-0000-4000-8000-000000000002',
    'B cascade post', 'B cascade body', 'public', null
  );

insert into public.follows (follower_id, following_id)
values (
  'a1800000-0000-4000-8000-000000000001',
  'b1800000-0000-4000-8000-000000000002'
);

insert into public.comments (
  id, post_id, user_id, body, parent_comment_id, deleted_at
)
values
  (
    '21800000-0000-4000-8000-000000000001',
    '11800000-0000-4000-8000-000000000002',
    'b1800000-0000-4000-8000-000000000002',
    'B comment on followers post', null, null
  ),
  (
    '21800000-0000-4000-8000-000000000002',
    '11800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'B deleted comment on visible post', null, now()
  ),
  (
    '21800000-0000-4000-8000-000000000003',
    '11800000-0000-4000-8000-000000000005',
    'b1800000-0000-4000-8000-000000000002',
    'B cascade comment', null, null
  );

insert into public.notifications (
  id,
  recipient_user_id,
  actor_user_id,
  notification_type,
  target_post_id,
  target_comment_id
)
values
  (
    '31800000-0000-4000-8000-000000000001',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'follow', null, null
  ),
  (
    '31800000-0000-4000-8000-000000000002',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'reaction', '11800000-0000-4000-8000-000000000001', null
  ),
  (
    '31800000-0000-4000-8000-000000000003',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'comment',
    '11800000-0000-4000-8000-000000000002',
    '21800000-0000-4000-8000-000000000001'
  ),
  (
    '31800000-0000-4000-8000-000000000004',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'reply',
    '11800000-0000-4000-8000-000000000001',
    '21800000-0000-4000-8000-000000000002'
  ),
  (
    '31800000-0000-4000-8000-000000000005',
    'a1800000-0000-4000-8000-000000000001',
    'c1800000-0000-4000-8000-000000000003',
    'reaction', '11800000-0000-4000-8000-000000000003', null
  ),
  (
    '31800000-0000-4000-8000-000000000006',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'reaction', '11800000-0000-4000-8000-000000000004', null
  ),
  (
    '31800000-0000-4000-8000-000000000007',
    'a1800000-0000-4000-8000-000000000001',
    'd1800000-0000-4000-8000-000000000004',
    'follow', null, null
  ),
  (
    '31800000-0000-4000-8000-000000000008',
    'c1800000-0000-4000-8000-000000000003',
    'b1800000-0000-4000-8000-000000000002',
    'follow', null, null
  ),
  (
    '31800000-0000-4000-8000-000000000009',
    'a1800000-0000-4000-8000-000000000001',
    'b1800000-0000-4000-8000-000000000002',
    'comment',
    '11800000-0000-4000-8000-000000000005',
    '21800000-0000-4000-8000-000000000003'
  );

update public.accounts
set status = 'suspended'
where user_id = 'd1800000-0000-4000-8000-000000000004';

select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'a1800000-0000-4000-8000-000000000001',
      'follow'
    )
  $$,
  '23514', null,
  'self notification is rejected by the DB constraint'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'unknown'
    )
  $$,
  '23514', null,
  'unknown notification types are rejected'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_post_id
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'follow',
      '11800000-0000-4000-8000-000000000001'
    )
  $$,
  '23514', null,
  'follow notifications reject targets'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'reaction'
    )
  $$,
  '23514', null,
  'reaction notifications require a post target'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_post_id
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'comment',
      '11800000-0000-4000-8000-000000000001'
    )
  $$,
  '23514', null,
  'comment notifications require post and comment targets'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_comment_id
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'reply',
      '21800000-0000-4000-8000-000000000001'
    )
  $$,
  '23514', null,
  'reply notifications require post and comment targets'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;

select throws_ok(
  $$select id from public.notifications$$,
  '42501', null,
  'anon cannot read notifications'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'follow'
    )
  $$,
  '42501', null,
  'anon cannot create notifications'
);
select throws_ok(
  $$update public.notifications set is_read = true$$,
  '42501', null,
  'anon cannot update notifications'
);
select throws_ok(
  $$delete from public.notifications$$,
  '42501', null,
  'anon cannot delete notifications'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a1800000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.notifications
    order by id
  $$,
  $$
    values
      ('31800000-0000-4000-8000-000000000001'::uuid),
      ('31800000-0000-4000-8000-000000000002'::uuid),
      ('31800000-0000-4000-8000-000000000003'::uuid),
      ('31800000-0000-4000-8000-000000000004'::uuid),
      ('31800000-0000-4000-8000-000000000009'::uuid)
  $$,
  'active recipient sees own notifications with active actors and visible posts'
);
select ok(
  exists (
    select 1
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000004'
  ),
  'soft-deleted target comment does not hide a notification for a visible post'
);
select lives_ok(
  $$
    update public.notifications
    set is_read = true
    where id = '31800000-0000-4000-8000-000000000001'
  $$,
  'recipient can update is_read on a visible notification'
);
select throws_ok(
  $$
    update public.notifications
    set actor_user_id = 'c1800000-0000-4000-8000-000000000003'
    where id = '31800000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'recipient cannot update actor identity'
);
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'a1800000-0000-4000-8000-000000000001',
      'b1800000-0000-4000-8000-000000000002',
      'follow'
    )
  $$,
  '42501', null,
  'authenticated recipient cannot create notifications'
);
select throws_ok(
  $$delete from public.notifications where recipient_user_id = auth.uid()$$,
  '42501', null,
  'authenticated recipient cannot delete notifications'
);

delete from public.follows
where follower_id = 'a1800000-0000-4000-8000-000000000001'
  and following_id = 'b1800000-0000-4000-8000-000000000002';

select results_eq(
  $$
    select id
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000003'
  $$,
  $$select null::uuid where false$$,
  'follow loss hides a notification whose post is no longer visible'
);

reset role;
insert into public.follows (follower_id, following_id)
values (
  'a1800000-0000-4000-8000-000000000001',
  'b1800000-0000-4000-8000-000000000002'
);

select set_config(
  'request.jwt.claim.sub',
  'a1800000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select ok(
  exists (
    select 1
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000003'
  ),
  'following again restores visibility on the next SELECT'
);

reset role;
update public.posts
set visibility = 'private'
where id = '11800000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1800000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000003'
  $$,
  $$select null::uuid where false$$,
  'visibility change is re-evaluated on the next SELECT'
);

reset role;
update public.posts
set visibility = 'followers'
where id = '11800000-0000-4000-8000-000000000002';
update public.accounts
set status = 'suspended'
where user_id = 'b1800000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1800000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.notifications$$,
  $$select null::uuid where false$$,
  'a non-active actor hides every notification from that actor'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'b1800000-0000-4000-8000-000000000002';
update public.accounts
set status = 'suspended'
where user_id = 'a1800000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'a1800000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.notifications$$,
  $$select null::uuid where false$$,
  'a non-active recipient cannot read own notifications'
);
select results_eq(
  $$
    update public.notifications
    set is_read = true
    returning id
  $$,
  $$select null::uuid where false$$,
  'a non-active recipient cannot update own notifications'
);

reset role;
update public.accounts
set status = 'active'
where user_id = 'a1800000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claim.sub',
  'b1800000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$select id from public.notifications$$,
  $$select null::uuid where false$$,
  'actor cannot read notifications addressed to another user'
);
select results_eq(
  $$
    update public.notifications
    set is_read = true
    returning id
  $$,
  $$select null::uuid where false$$,
  'actor cannot update notifications addressed to another user'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c1800000-0000-4000-8000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select results_eq(
  $$
    select id
    from public.notifications
    where recipient_user_id = 'a1800000-0000-4000-8000-000000000001'
  $$,
  $$select null::uuid where false$$,
  'third party cannot read another recipient notifications'
);

reset role;
select ok(
  (
    select is_read
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000001'
  ),
  'recipient read-state update was persisted'
);

delete from public.comments
where id = '21800000-0000-4000-8000-000000000003';

select ok(
  not exists (
    select 1
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000009'
  ),
  'physical target comment deletion cascades to its notification'
);

insert into public.comments (
  id, post_id, user_id, body, parent_comment_id
)
values (
  '21800000-0000-4000-8000-000000000004',
  '11800000-0000-4000-8000-000000000005',
  'b1800000-0000-4000-8000-000000000002',
  'B replacement cascade comment', null
);
insert into public.notifications (
  id,
  recipient_user_id,
  actor_user_id,
  notification_type,
  target_post_id,
  target_comment_id
)
values (
  '31800000-0000-4000-8000-000000000010',
  'a1800000-0000-4000-8000-000000000001',
  'b1800000-0000-4000-8000-000000000002',
  'reply',
  '11800000-0000-4000-8000-000000000005',
  '21800000-0000-4000-8000-000000000004'
);

delete from public.posts
where id = '11800000-0000-4000-8000-000000000005';

select ok(
  not exists (
    select 1
    from public.notifications
    where id = '31800000-0000-4000-8000-000000000010'
  ),
  'physical target post deletion cascades without dangling notifications'
);

select * from finish();

rollback;
