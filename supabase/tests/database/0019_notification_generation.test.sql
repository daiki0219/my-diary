begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

select has_function(
  'my_diary_private',
  'my_diary_generate_follow_notification',
  array[]::text[],
  'The private follow notification generator exists'
);
select has_function(
  'my_diary_private',
  'my_diary_generate_reaction_notification',
  array[]::text[],
  'The private reaction notification generator exists'
);
select has_function(
  'my_diary_private',
  'my_diary_generate_comment_notification',
  array[]::text[],
  'The private comment notification generator exists'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function_definition.proname in (
        'my_diary_generate_follow_notification',
        'my_diary_generate_reaction_notification',
        'my_diary_generate_comment_notification'
      )
      and function_definition.proargtypes = ''::oidvector
      and function_definition.prorettype = 'trigger'::pg_catalog.regtype
      and function_definition.prosecdef
      and function_definition.provolatile = 'v'
      and function_definition.proconfig = array['search_path=""']::text[]
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  3::bigint,
  'All generators are hardened volatile postgres-owned trigger functions'
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
      and function_definition.proname in (
        'my_diary_generate_follow_notification',
        'my_diary_generate_reaction_notification',
        'my_diary_generate_comment_notification'
      )
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'my_diary_private.my_diary_generate_follow_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_generate_reaction_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'my_diary_private.my_diary_generate_comment_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticator',
    'my_diary_private.my_diary_generate_comment_notification()',
    'EXECUTE'
  ),
  'Application roles cannot execute notification generators directly'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_trigger as trigger_definition
    join pg_catalog.pg_proc as function_definition
      on function_definition.oid = trigger_definition.tgfoid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where trigger_definition.tgname in (
        'my_diary_follows_generate_notification',
        'my_diary_reactions_generate_notification',
        'my_diary_comments_generate_notification'
      )
      and trigger_definition.tgenabled = 'O'
      and not trigger_definition.tgisinternal
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        like '%AFTER INSERT ON%'
      and pg_catalog.pg_get_triggerdef(trigger_definition.oid)
        ilike '%current_user%authenticated%auth.uid()%'
      and namespace.nspname = 'my_diary_private'
  ),
  3::bigint,
  'Enabled AFTER INSERT triggers require an authenticated matching actor'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.comments'::regclass
      and tgname = 'my_diary_comments_validate_parent'
      and tgenabled = 'O'
      and not tgisinternal
      and pg_catalog.pg_get_triggerdef(oid)
        like '%AFTER INSERT OR UPDATE%'
  ),
  'The C2a reply validator remains enabled'
);

select ok(
  (
    select relrowsecurity and not relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'public.notifications'::regclass
  )
  and (
    select count(*) = 2
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
  )
  and has_table_privilege(
    'authenticated', 'public.notifications', 'SELECT'
  )
  and has_column_privilege(
    'authenticated', 'public.notifications', 'is_read', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.notifications', 'INSERT, DELETE'
  ),
  'C2c-1 notification RLS, policies, and ACL remain unchanged'
);

insert into auth.users (id, email)
values
  ('a1900000-0000-4000-8000-000000000001', 'c2c2-a@example.test'),
  ('b1900000-0000-4000-8000-000000000002', 'c2c2-b@example.test'),
  ('c1900000-0000-4000-8000-000000000003', 'c2c2-c@example.test'),
  ('d1900000-0000-4000-8000-000000000004', 'c2c2-d@example.test');

insert into public.posts (
  id, user_id, title, body, visibility, deleted_at
)
values
  (
    '11900000-0000-4000-8000-000000000001',
    'a1900000-0000-4000-8000-000000000001',
    'A public', 'A public body', 'public', null
  ),
  (
    '11900000-0000-4000-8000-000000000002',
    'b1900000-0000-4000-8000-000000000002',
    'B public', 'B public body', 'public', null
  ),
  (
    '11900000-0000-4000-8000-000000000003',
    'c1900000-0000-4000-8000-000000000003',
    'C public', 'C public body', 'public', null
  ),
  (
    '11900000-0000-4000-8000-000000000004',
    'c1900000-0000-4000-8000-000000000003',
    'C private', 'C private body', 'private', null
  );

insert into public.follows (follower_id, following_id)
values (
  'c1900000-0000-4000-8000-000000000003',
  'b1900000-0000-4000-8000-000000000002'
);

insert into public.reactions (post_id, user_id, reaction_type)
values (
  '11900000-0000-4000-8000-000000000002',
  'c1900000-0000-4000-8000-000000000003',
  'empathy'
);

insert into public.comments (
  id, post_id, user_id, body, parent_comment_id, deleted_at
)
values
  (
    '21900000-0000-4000-8000-000000000001',
    '11900000-0000-4000-8000-000000000003',
    'a1900000-0000-4000-8000-000000000001',
    'A parent on C public', null, null
  ),
  (
    '21900000-0000-4000-8000-000000000002',
    '11900000-0000-4000-8000-000000000003',
    'b1900000-0000-4000-8000-000000000002',
    'B nested reply fixture',
    '21900000-0000-4000-8000-000000000001',
    null
  ),
  (
    '21900000-0000-4000-8000-000000000003',
    '11900000-0000-4000-8000-000000000003',
    'a1900000-0000-4000-8000-000000000001',
    'A deleted parent', null, null
  ),
  (
    '21900000-0000-4000-8000-000000000004',
    '11900000-0000-4000-8000-000000000003',
    'd1900000-0000-4000-8000-000000000004',
    'D non-active parent', null, null
  ),
  (
    '21900000-0000-4000-8000-000000000005',
    '11900000-0000-4000-8000-000000000004',
    'c1900000-0000-4000-8000-000000000003',
    'C parent on private post', null, null
  );

update public.comments
set deleted_at = now()
where id = '21900000-0000-4000-8000-000000000003';

update public.accounts
set status = 'suspended'
where user_id = 'd1900000-0000-4000-8000-000000000004';

select is(
  (select count(*) from public.notifications),
  0::bigint,
  'Privileged fixtures with no authenticated identity create no notifications'
);

select set_config(
  'request.jwt.claim.sub',
  'a1900000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

insert into public.follows (follower_id, following_id)
values (
  'a1900000-0000-4000-8000-000000000001',
  'b1900000-0000-4000-8000-000000000002'
);

reset role;
select results_eq(
  $$
    select
      recipient_user_id,
      actor_user_id,
      notification_type,
      target_post_id,
      target_comment_id
    from public.notifications
    where notification_type = 'follow'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  $$,
  $$
    values (
      'b1900000-0000-4000-8000-000000000002'::uuid,
      'a1900000-0000-4000-8000-000000000001'::uuid,
      'follow'::text,
      null::uuid,
      null::uuid
    )
  $$,
  'A follow INSERT creates one correctly shaped notification for B'
);

set local role authenticated;
select throws_ok(
  $$
    insert into public.follows (follower_id, following_id)
    values (
      'a1900000-0000-4000-8000-000000000001',
      'a1900000-0000-4000-8000-000000000001'
    )
  $$,
  '42501', null,
  'The existing follows RLS still rejects self-follow'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'follow'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Rejected self-follow creates no notification'
);

set local role authenticated;
delete from public.follows
where follower_id = 'a1900000-0000-4000-8000-000000000001'
  and following_id = 'b1900000-0000-4000-8000-000000000002';
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'follow'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Unfollow preserves the earlier follow notification'
);

set local role authenticated;
insert into public.follows (follower_id, following_id)
values (
  'a1900000-0000-4000-8000-000000000001',
  'b1900000-0000-4000-8000-000000000002'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'follow'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'Refollow creates a new event notification'
);

set local role authenticated;
select throws_ok(
  $$
    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type
    ) values (
      'b1900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'follow'
    )
  $$,
  '42501', null,
  'Authenticated users still cannot insert notifications directly'
);

select lives_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '11900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'empathy'
    )
  $$,
  'A can react to B public post'
);
reset role;
select results_eq(
  $$
    select
      recipient_user_id,
      actor_user_id,
      target_post_id,
      target_comment_id
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
      and target_post_id = '11900000-0000-4000-8000-000000000002'
  $$,
  $$
    values (
      'b1900000-0000-4000-8000-000000000002'::uuid,
      'a1900000-0000-4000-8000-000000000001'::uuid,
      '11900000-0000-4000-8000-000000000002'::uuid,
      null::uuid
    )
  $$,
  'A new reaction notifies the post owner with the post target'
);

set local role authenticated;
select lives_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '11900000-0000-4000-8000-000000000001',
      'a1900000-0000-4000-8000-000000000001',
      'support'
    )
  $$,
  'A can react to A own post'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'A reaction to A own post creates no self notification'
);

set local role authenticated;
select lives_ok(
  $$
    update public.reactions
    set reaction_type = 'support'
    where post_id = '11900000-0000-4000-8000-000000000002'
      and user_id = 'a1900000-0000-4000-8000-000000000001'
  $$,
  'A can change the existing reaction type'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Reaction UPDATE creates no additional notification'
);

set local role authenticated;
select lives_ok(
  $$
    delete from public.reactions
    where post_id = '11900000-0000-4000-8000-000000000002'
      and user_id = 'a1900000-0000-4000-8000-000000000001'
  $$,
  'A can remove the reaction from B post'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Reaction DELETE preserves the earlier notification'
);

set local role authenticated;
select lives_ok(
  $$
    insert into public.reactions (post_id, user_id, reaction_type)
    values (
      '11900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'relatable'
    )
  $$,
  'A can react again after deleting the old reaction'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
      and target_post_id = '11900000-0000-4000-8000-000000000002'
  ),
  2::bigint,
  'A new reaction INSERT after deletion creates a new notification'
);

set local role authenticated;
select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '11900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'A top-level comment on B post'
    )
  $$,
  'A can comment on B public post'
);
reset role;
select results_eq(
  $$
    select
      notification.recipient_user_id,
      notification.actor_user_id,
      notification.target_post_id,
      notification.target_comment_id
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where notification.notification_type = 'comment'
      and target_comment.body = 'A top-level comment on B post'
  $$,
  $$
    select
      'b1900000-0000-4000-8000-000000000002'::uuid,
      'a1900000-0000-4000-8000-000000000001'::uuid,
      '11900000-0000-4000-8000-000000000002'::uuid,
      id
    from public.comments
    where body = 'A top-level comment on B post'
  $$,
  'A top-level comment notifies B and targets the new comment'
);

set local role authenticated;
select lives_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '11900000-0000-4000-8000-000000000001',
      'a1900000-0000-4000-8000-000000000001',
      'A comment on A own post'
    )
  $$,
  'A can comment on A own post'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'A comment on A own post'
  ),
  0::bigint,
  'A comment on A own post creates no self notification'
);

set local role authenticated;
select is(
  public.my_diary_soft_delete_comment(
    (
      select id
      from public.comments
      where body = 'A top-level comment on B post'
    )
  ),
  true,
  'A can soft-delete the notified top-level comment'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'A top-level comment on B post'
      and target_comment.deleted_at is not null
  ),
  1::bigint,
  'Comment soft delete preserves notification metadata'
);

select set_config(
  'request.jwt.claim.sub',
  'b1900000-0000-4000-8000-000000000002',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'b1900000-0000-4000-8000-000000000002',
      'B reply to A parent',
      '21900000-0000-4000-8000-000000000001'
    )
  $$,
  'B can reply to A top-level comment'
);
reset role;
select results_eq(
  $$
    select
      notification.recipient_user_id,
      notification.actor_user_id,
      notification.notification_type,
      notification.target_post_id,
      notification.target_comment_id
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'B reply to A parent'
  $$,
  $$
    select
      'a1900000-0000-4000-8000-000000000001'::uuid,
      'b1900000-0000-4000-8000-000000000002'::uuid,
      'reply'::text,
      '11900000-0000-4000-8000-000000000003'::uuid,
      id
    from public.comments
    where body = 'B reply to A parent'
  $$,
  'Reply notifies only the parent author and targets the new reply'
);
select is(
  (
    select count(*)
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'B reply to A parent'
  ),
  1::bigint,
  'One reply produces exactly one notification'
);
select is(
  (
    select count(*)
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'B reply to A parent'
      and notification.recipient_user_id =
        'c1900000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'Reply does not also notify the post owner as a comment'
);

select set_config(
  'request.jwt.claim.sub',
  'a1900000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'A reply to A own parent',
      '21900000-0000-4000-8000-000000000001'
    )
  $$,
  'A can reply to A own top-level comment'
);
reset role;
select is(
  (
    select count(*)
    from public.notifications as notification
    join public.comments as target_comment
      on target_comment.id = notification.target_comment_id
    where target_comment.body = 'A reply to A own parent'
  ),
  0::bigint,
  'A reply to A own comment creates no self notification'
);

set local role authenticated;
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'Missing parent probe',
      '99999999-0000-4000-8000-000000000999'
    )
  $$,
  '23514', 'invalid parent comment',
  'Missing parent retains the generic C2a failure'
);
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'Cross-post parent probe',
      '21900000-0000-4000-8000-000000000001'
    )
  $$,
  '23514', 'invalid parent comment',
  'Cross-post parent retains the generic C2a failure'
);
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'Nested parent probe',
      '21900000-0000-4000-8000-000000000002'
    )
  $$,
  '23514', 'invalid parent comment',
  'Nested parent retains the generic C2a failure'
);
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'Deleted parent probe',
      '21900000-0000-4000-8000-000000000003'
    )
  $$,
  '23514', 'invalid parent comment',
  'Deleted parent retains the generic C2a failure'
);
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'Non-active parent probe',
      '21900000-0000-4000-8000-000000000004'
    )
  $$,
  '23514', 'invalid parent comment',
  'Non-active parent author retains the generic C2a failure'
);
select throws_ok(
  $$
    insert into public.comments (
      post_id, user_id, body, parent_comment_id
    ) values (
      '11900000-0000-4000-8000-000000000003',
      'a1900000-0000-4000-8000-000000000001',
      'Private-post parent probe',
      '21900000-0000-4000-8000-000000000005'
    )
  $$,
  '23514', 'invalid parent comment',
  'An inaccessible private-post parent retains the generic C2a failure'
);
reset role;
select is(
  (select count(*) from public.notifications),
  6::bigint,
  'Invalid reply attempts create no notifications'
);

insert into public.reactions (post_id, user_id, reaction_type)
values (
  '11900000-0000-4000-8000-000000000003',
  'a1900000-0000-4000-8000-000000000001',
  'support'
);
select is(
  (
    select count(*)
    from public.notifications
    where notification_type = 'reaction'
      and actor_user_id = 'a1900000-0000-4000-8000-000000000001'
      and target_post_id = '11900000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'A privileged INSERT with a residual JWT claim still creates no notification'
);

create function pg_temp.my_diary_fail_comment_after_notification()
returns trigger
language plpgsql
as $function$
begin
  raise exception using
    errcode = 'P0001',
    message = 'forced notification transaction rollback';
end;
$function$;

create trigger zz_my_diary_test_fail_comment
after insert on public.comments
for each row execute function
  pg_temp.my_diary_fail_comment_after_notification();

set local role authenticated;
select throws_ok(
  $$
    insert into public.comments (post_id, user_id, body)
    values (
      '11900000-0000-4000-8000-000000000002',
      'a1900000-0000-4000-8000-000000000001',
      'Forced rollback comment'
    )
  $$,
  'P0001', 'forced notification transaction rollback',
  'A later trigger failure rolls back the source INSERT'
);
reset role;
select is(
  (
    select count(*)
    from public.comments
    where body = 'Forced rollback comment'
  ),
  0::bigint,
  'The failed source comment is absent after statement rollback'
);
select is(
  (select count(*) from public.notifications),
  6::bigint,
  'The generated notification rolls back with its source comment'
);

drop trigger zz_my_diary_test_fail_comment on public.comments;
drop function pg_temp.my_diary_fail_comment_after_notification();

select * from finish();

rollback;
