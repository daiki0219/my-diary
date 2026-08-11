begin;

create extension if not exists pgtap with schema extensions;

select plan(88);

-- Catalog, constraints, RLS, ACL, triggers, and hardened functions.
select columns_are(
  'public', 'notifications',
  array[
    'id','recipient_user_id','actor_user_id','notification_type',
    'target_post_id','target_comment_id','is_read','created_at',
    'exchange_invitation_id','exchange_diary_id','exchange_entry_id'
  ],
  'notifications has the existing and exchange target columns'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::pg_catalog.regclass
      and conname in (
        'my_diary_notifications_exchange_invitation_id_fkey',
        'my_diary_notifications_exchange_diary_id_fkey',
        'my_diary_notifications_exchange_entry_id_fkey'
      )
      and contype = 'f'
      and confdeltype = 'c'
  ),
  3::bigint,
  'all exchange notification targets have cascade foreign keys'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::pg_catalog.regclass
      and conname = 'my_diary_notifications_type_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_invitation%'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%exchange_invitation_accepted%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_entry%'
  ),
  'notification type CHECK allows exactly the three exchange types in addition'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.notifications'::pg_catalog.regclass
      and conname = 'my_diary_notifications_target_shape_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_invitation_id%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_diary_id%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_entry_id%'
  ),
  'notification target shape CHECK covers all typed exchange targets'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'notifications'
      and indexname = 'my_diary_notifications_recipient_created_id_idx'
      and indexdef like '%(recipient_user_id, created_at DESC, id DESC)%'
  ),
  'the existing recipient cursor index remains unchanged'
);

select tables_are(
  'public',
  array[
    'accounts','profiles','posts','follows','reactions','comments','tags',
    'post_tags','post_images','notifications','exchange_diaries',
    'exchange_diary_participants','exchange_invitations',
    'exchange_invitation_blocks','exchange_entries','exchange_entry_tags',
    'exchange_entry_images','exchange_notification_preferences',
    'exchange_diary_mutes'
  ],
  'the two exchange notification setting tables are present'
);

select columns_are(
  'public', 'exchange_notification_preferences',
  array['user_id','new_entry_enabled','created_at','updated_at'],
  'preference table has the exact columns'
);

select columns_are(
  'public', 'exchange_diary_mutes',
  array['participant_id','muted','created_at','updated_at'],
  'mute table has the exact columns'
);

select ok(
  (
    select relrowsecurity and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = 'public.exchange_notification_preferences'::regclass
  )
  and (
    select relrowsecurity and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = 'public.exchange_diary_mutes'::regclass
  ),
  'preference and mute tables are postgres-owned with RLS enabled'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated','public.exchange_notification_preferences','SELECT'
  )
  and pg_catalog.has_table_privilege(
    'authenticated','public.exchange_diary_mutes','SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated','public.exchange_notification_preferences',
    'INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated','public.exchange_diary_mutes','INSERT,UPDATE,DELETE'
  ),
  'settings are SELECT-only through direct authenticated table access'
);

select is(
  (
    select pg_catalog.count(*) from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_notification_preferences','exchange_diary_mutes'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  2::bigint,
  'exactly one authenticated SELECT policy protects each setting table'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_accounts_initialize_exchange_notification_preference',
      'my_diary_exchange_notification_preferences_set_updated_at',
      'my_diary_exchange_diary_mutes_set_updated_at'
    ) and tgenabled = 'O' and not tgisinternal
  ),
  3::bigint,
  'future preference initialization and updated_at triggers exist'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname in (
        'my_diary_update_exchange_notification_preference',
        'my_diary_update_exchange_diary_mute'
      )
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  2::bigint,
  'both setting RPCs are hardened exact SECURITY DEFINER functions'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_exchange_notification_preference(boolean)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_exchange_diary_mute(uuid,boolean)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_exchange_notification_preference(boolean)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_update_exchange_diary_mute(uuid,boolean)',
    'EXECUTE'
  ),
  'only authenticated can execute the exact setting RPCs'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_create_exchange_invitation_notification(uuid,text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_create_exchange_entry_notification(uuid)',
    'EXECUTE'
  ),
  'application roles cannot execute the private notification helpers'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_follows_generate_notification',
      'my_diary_reactions_generate_notification',
      'my_diary_comments_generate_notification'
    ) and tgenabled = 'O' and not tgisinternal
  ),
  3::bigint,
  'all existing notification source triggers remain enabled'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated','public.notifications','INSERT,DELETE'
  )
  and pg_catalog.has_column_privilege(
    'authenticated','public.notifications','is_read','UPDATE'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated','public.notifications','exchange_diary_id','UPDATE'
  ),
  'notification direct mutation remains limited to is_read'
);

-- Future accounts receive a default-ON preference row.
insert into auth.users (id, email)
values
  ('a2600000-0000-4000-8000-000000000001','e2c-a@example.test'),
  ('b2600000-0000-4000-8000-000000000002','e2c-b@example.test'),
  ('c2600000-0000-4000-8000-000000000003','e2c-c@example.test'),
  ('d2600000-0000-4000-8000-000000000004','e2c-d@example.test');

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_notification_preferences
    where user_id in (
      'a2600000-0000-4000-8000-000000000001',
      'b2600000-0000-4000-8000-000000000002',
      'c2600000-0000-4000-8000-000000000003',
      'd2600000-0000-4000-8000-000000000004'
    ) and new_entry_enabled
  ),
  4::bigint,
  'future accounts receive one default-enabled preference row'
);

select ok(
  exists (select 1 from public.accounts where user_id =
    'a2600000-0000-4000-8000-000000000001')
  and exists (select 1 from public.profiles where user_id =
    'a2600000-0000-4000-8000-000000000001'),
  'existing auth account and profile initialization still succeeds'
);

insert into public.follows (follower_id, following_id)
values
  ('a2600000-0000-4000-8000-000000000001','b2600000-0000-4000-8000-000000000002'),
  ('b2600000-0000-4000-8000-000000000002','a2600000-0000-4000-8000-000000000001'),
  ('a2600000-0000-4000-8000-000000000001','c2600000-0000-4000-8000-000000000003'),
  ('c2600000-0000-4000-8000-000000000003','a2600000-0000-4000-8000-000000000001'),
  ('b2600000-0000-4000-8000-000000000002','c2600000-0000-4000-8000-000000000003'),
  ('c2600000-0000-4000-8000-000000000003','b2600000-0000-4000-8000-000000000002'),
  ('a2600000-0000-4000-8000-000000000001','d2600000-0000-4000-8000-000000000004'),
  ('d2600000-0000-4000-8000-000000000004','a2600000-0000-4000-8000-000000000001'),
  ('c2600000-0000-4000-8000-000000000003','d2600000-0000-4000-8000-000000000004'),
  ('d2600000-0000-4000-8000-000000000004','c2600000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;

select lives_ok(
  $$select set_config(
      'my_diary.e2c_invitation',
      public.my_diary_create_exchange_invitation(
        'b2600000-0000-4000-8000-000000000002'
      )::text, true
    )$$,
  'invitation succeeds and atomically creates its notification'
);

reset role;

select results_eq(
  $$select notification_type, actor_user_id, recipient_user_id,
           exchange_invitation_id
    from public.notifications
    where exchange_invitation_id =
      current_setting('my_diary.e2c_invitation')::uuid$$,
  $$values (
      'exchange_invitation'::text,
      'a2600000-0000-4000-8000-000000000001'::uuid,
      'b2600000-0000-4000-8000-000000000002'::uuid,
      current_setting('my_diary.e2c_invitation')::uuid
    )$$,
  'invitation notification has the exact actor recipient and target'
);

update public.exchange_notification_preferences
set new_entry_enabled = false
where user_id = 'b2600000-0000-4000-8000-000000000002';

select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select set_config(
      'my_diary.e2c_diary',
      public.my_diary_accept_exchange_invitation(
        current_setting('my_diary.e2c_invitation')::uuid
      )::text, true
    )$$,
  'accept succeeds while global entry notifications are disabled'
);

reset role;

select is(
  (select pg_catalog.count(*)
   from public.exchange_diary_participants
   where diary_id = current_setting('my_diary.e2c_diary')::uuid),
  2::bigint,
  'accept preserves exactly two participants'
);

select is(
  (select pg_catalog.count(*)
   from public.exchange_diary_mutes as mute
   join public.exchange_diary_participants as participant
     on participant.id = mute.participant_id
   where participant.diary_id = current_setting('my_diary.e2c_diary')::uuid
     and not mute.muted),
  2::bigint,
  'accept atomically creates two default-unmuted rows'
);

select results_eq(
  $$select notification_type, actor_user_id, recipient_user_id,
           exchange_invitation_id, exchange_diary_id
    from public.notifications
    where notification_type = 'exchange_invitation_accepted'
      and exchange_invitation_id =
        current_setting('my_diary.e2c_invitation')::uuid$$,
  $$values (
      'exchange_invitation_accepted'::text,
      'b2600000-0000-4000-8000-000000000002'::uuid,
      'a2600000-0000-4000-8000-000000000001'::uuid,
      current_setting('my_diary.e2c_invitation')::uuid,
      current_setting('my_diary.e2c_diary')::uuid
    )$$,
  'accepted notification ignores the global entry preference'
);

-- Preference and mute setters only affect the authenticated caller.
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;

select lives_ok(
  $$select public.my_diary_update_exchange_notification_preference(true)$$,
  'active viewer can turn global entry notifications on'
);
select throws_ok(
  $$select public.my_diary_update_exchange_notification_preference(null)$$,
  '22023','Invalid exchange notification preference input.',
  'NULL preference is rejected'
);
select lives_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      current_setting('my_diary.e2c_diary')::uuid, true
    )$$,
  'participant can mute only their diary row'
);
select throws_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      current_setting('my_diary.e2c_diary')::uuid, null
    )$$,
  '22023','Invalid exchange diary mute input.',
  'NULL mute input is rejected'
);

reset role;

select is(
  (select pg_catalog.count(*)
   from public.exchange_diary_mutes as mute
   join public.exchange_diary_participants as participant
     on participant.id = mute.participant_id
   where participant.diary_id = current_setting('my_diary.e2c_diary')::uuid
     and participant.user_id =
       'b2600000-0000-4000-8000-000000000002'
     and mute.muted),
  1::bigint,
  'mute setter changes the viewer participant row'
);

select is(
  (select pg_catalog.count(*)
   from public.exchange_diary_mutes as mute
   join public.exchange_diary_participants as participant
     on participant.id = mute.participant_id
   where participant.diary_id = current_setting('my_diary.e2c_diary')::uuid
     and participant.user_id =
       'a2600000-0000-4000-8000-000000000001'
     and not mute.muted),
  1::bigint,
  'mute setter does not change the counterpart row'
);

select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      current_setting('my_diary.e2c_diary')::uuid, true
    )$$,
  '42501','Exchange diary mute is unavailable.',
  'third party cannot mutate diary mute state'
);
reset role;

update public.accounts set status = 'suspended'
where user_id = 'd2600000-0000-4000-8000-000000000004';
select set_config('request.jwt.claim.sub',
  'd2600000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_notification_preference(false)$$,
  '42501','Exchange notification preference is unavailable.',
  'suspended account cannot change its global preference'
);
reset role;
update public.accounts set status = 'deactivated'
where user_id = 'd2600000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_notification_preference(false)$$,
  '42501','Exchange notification preference is unavailable.',
  'deactivated account cannot change its global preference'
);
reset role;
update public.accounts set status = 'active'
where user_id = 'd2600000-0000-4000-8000-000000000004';

insert into public.exchange_diaries (id,created_by_position)
values ('d2600000-0000-4000-8000-000000000099',1);
insert into public.exchange_diary_participants
  (id,diary_id,position,user_id)
values
  ('12600000-0000-4000-8000-000000000099',
   'd2600000-0000-4000-8000-000000000099',1,
   'b2600000-0000-4000-8000-000000000002'),
  ('22600000-0000-4000-8000-000000000099',
   'd2600000-0000-4000-8000-000000000099',2,
   'c2600000-0000-4000-8000-000000000003');
insert into public.exchange_diary_mutes (participant_id)
values
  ('12600000-0000-4000-8000-000000000099'),
  ('22600000-0000-4000-8000-000000000099');

update public.accounts set status = 'suspended'
where user_id = 'c2600000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      'd2600000-0000-4000-8000-000000000099',true
    )$$,
  '42501','Exchange diary mute is unavailable.',
  'mute update fails while the counterpart is suspended'
);
reset role;
update public.accounts set status = 'active'
where user_id = 'c2600000-0000-4000-8000-000000000003';
update public.exchange_diaries
set state = 'archived', archived_at = now(), archive_cause = 'test'
where id = 'd2600000-0000-4000-8000-000000000099';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      'd2600000-0000-4000-8000-000000000099',true
    )$$,
  '42501','Exchange diary mute is unavailable.',
  'mute update fails for an archived diary'
);
reset role;

insert into public.exchange_diaries (id,created_by_position)
values ('d2600000-0000-4000-8000-000000000098',1);
insert into public.exchange_diary_participants
  (id,diary_id,position,user_id)
values
  ('12600000-0000-4000-8000-000000000098',
   'd2600000-0000-4000-8000-000000000098',1,
   'a2600000-0000-4000-8000-000000000001'),
  ('22600000-0000-4000-8000-000000000098',
   'd2600000-0000-4000-8000-000000000098',2,
   'b2600000-0000-4000-8000-000000000002');
insert into public.exchange_diary_mutes (participant_id)
values
  ('12600000-0000-4000-8000-000000000098'),
  ('22600000-0000-4000-8000-000000000098');

-- Entry creation succeeds while settings suppress only the notification.
select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('my_diary.e2c_muted_entry',
      public.my_diary_create_exchange_entry(
        current_setting('my_diary.e2c_diary')::uuid,
        null,'muted entry',null,null,null
      )::text,true)$$,
  'entry creation succeeds while recipient diary mute is on'
);
select lives_ok(
  $$select set_config('my_diary.e2c_other_diary_entry',
      public.my_diary_create_exchange_entry(
        'd2600000-0000-4000-8000-000000000098',
        null,'other diary entry',null,null,null
      )::text,true)$$,
  'entry creation in another unmuted diary succeeds'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     current_setting('my_diary.e2c_muted_entry')::uuid),
  0::bigint,
  'individual mute suppresses only the entry notification'
);
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     current_setting('my_diary.e2c_other_diary_entry')::uuid),
  1::bigint,
  'mute on one diary does not suppress another diary notification'
);

select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_update_exchange_diary_mute(
      current_setting('my_diary.e2c_diary')::uuid, false
    )$$,
  'participant can unmute the diary'
);
reset role;

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('my_diary.e2c_entry',
      public.my_diary_create_exchange_entry(
        current_setting('my_diary.e2c_diary')::uuid,
        null,'visible entry',null,null,array['notify']
      )::text,true)$$,
  'legacy entry create succeeds with notification enabled'
);
reset role;

select results_eq(
  $$select notification_type, actor_user_id, recipient_user_id,
           exchange_diary_id, exchange_entry_id
    from public.notifications
    where exchange_entry_id = current_setting('my_diary.e2c_entry')::uuid$$,
  $$values (
      'exchange_entry'::text,
      'a2600000-0000-4000-8000-000000000001'::uuid,
      'b2600000-0000-4000-8000-000000000002'::uuid,
      current_setting('my_diary.e2c_diary')::uuid,
      current_setting('my_diary.e2c_entry')::uuid
    )$$,
  'legacy entry create emits one exact recipient notification'
);

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2600000-0000-4000-8000-000000000001',
      current_setting('my_diary.e2c_diary')::uuid,
      null,'image route entry',null,null,null,array[]::text[]
    )$$,
  'image-integrated entry route succeeds without changing notification semantics'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     'e2600000-0000-4000-8000-000000000001'),
  1::bigint,
  'image-integrated entry route emits exactly one notification'
);

select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_update_exchange_notification_preference(false)$$,
  'recipient can disable global entry notifications'
);
reset role;

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('my_diary.e2c_off_entry',
      public.my_diary_create_exchange_entry(
        current_setting('my_diary.e2c_diary')::uuid,
        null,'global off entry',null,null,null
      )::text,true)$$,
  'entry creation succeeds while global preference is off'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     current_setting('my_diary.e2c_off_entry')::uuid),
  0::bigint,
  'global OFF suppresses only the new entry notification'
);

-- Missing setting rows fail closed without failing the diary entry.
delete from public.exchange_notification_preferences
where user_id = 'b2600000-0000-4000-8000-000000000002';

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('my_diary.e2c_missing_pref_entry',
      public.my_diary_create_exchange_entry(
        current_setting('my_diary.e2c_diary')::uuid,
        null,'missing preference entry',null,null,null
      )::text,true)$$,
  'missing preference does not fail entry creation'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     current_setting('my_diary.e2c_missing_pref_entry')::uuid),
  0::bigint,
  'missing preference fails closed for notification generation'
);

insert into public.exchange_notification_preferences
  (user_id,new_entry_enabled)
values ('b2600000-0000-4000-8000-000000000002',true);

delete from public.exchange_diary_mutes
where participant_id = (
  select participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = current_setting('my_diary.e2c_diary')::uuid
    and participant.user_id = 'b2600000-0000-4000-8000-000000000002'
);

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('my_diary.e2c_missing_mute_entry',
      public.my_diary_create_exchange_entry(
        current_setting('my_diary.e2c_diary')::uuid,
        null,'missing mute entry',null,null,null
      )::text,true)$$,
  'missing mute does not fail entry creation'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     current_setting('my_diary.e2c_missing_mute_entry')::uuid),
  0::bigint,
  'missing mute fails closed for notification generation'
);

insert into public.exchange_diary_mutes (participant_id)
select participant.id
from public.exchange_diary_participants as participant
where participant.diary_id = current_setting('my_diary.e2c_diary')::uuid
  and participant.user_id = 'b2600000-0000-4000-8000-000000000002';

-- Update and soft-delete never create additional exchange notifications.
select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2c_entry')::uuid,
      null,'updated entry',null,null,null
    )$$,
  'entry text update succeeds'
);
select lives_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2600000-0000-4000-8000-000000000001',
      null,'updated image entry',null,null,null,'[]'::jsonb
    )$$,
  'image-integrated entry update succeeds'
);
select lives_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      current_setting('my_diary.e2c_entry')::uuid
    )$$,
  'entry soft delete succeeds'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id = current_setting('my_diary.e2c_entry')::uuid),
  1::bigint,
  'entry update and delete create no additional notification'
);
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     'e2600000-0000-4000-8000-000000000001'),
  1::bigint,
  'image-integrated update creates no additional notification'
);

-- RLS: recipient only, soft-deleted entry retained, actor active fail-closed.
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id = current_setting('my_diary.e2c_entry')::uuid),
  1::bigint,
  'recipient sees the entry notification after target soft delete'
);
reset role;

select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_diary_id = current_setting('my_diary.e2c_diary')::uuid),
  0::bigint,
  'third party sees no exchange diary notification'
);
reset role;

update public.accounts set status = 'suspended'
where user_id = 'a2600000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_entry_id =
     'e2600000-0000-4000-8000-000000000001'),
  0::bigint,
  'recipient cannot see exchange notification from a non-active actor'
);
reset role;
update public.accounts set status = 'active'
where user_id = 'a2600000-0000-4000-8000-000000000001';

-- Invalidating a pending invitation hides its notification target.
select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select set_config('my_diary.e2c_invalidated_invitation',
  public.my_diary_create_exchange_invitation(
    'c2600000-0000-4000-8000-000000000003'
  )::text,true);
reset role;

select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2c_invalidated_invitation')::uuid),
  1::bigint,
  'invitee initially sees the invitation notification'
);
select lives_ok(
  $$select public.my_diary_block_exchange_invitations_from_user(
      'a2600000-0000-4000-8000-000000000001'
    )$$,
  'invitee can invalidate the invitation through the existing block RPC'
);
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2c_invalidated_invitation')::uuid),
  0::bigint,
  'invalidated invitation notification is hidden without exposing the target'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2c_invalidated_invitation')::uuid),
  1::bigint,
  'block invalidation creates no additional notification row'
);

select set_config('request.jwt.claim.sub',
  'd2600000-0000-4000-8000-000000000004', true);
set local role authenticated;
select set_config('my_diary.e2c_cancel_invitation',
  public.my_diary_create_exchange_invitation(
    'a2600000-0000-4000-8000-000000000001'
  )::text,true);
select lives_ok(
  $$select public.my_diary_cancel_exchange_invitation(
      current_setting('my_diary.e2c_cancel_invitation')::uuid
    )$$,
  'inviter can cancel through the existing RPC'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2c_cancel_invitation')::uuid),
  1::bigint,
  'invitation cancellation creates no additional notification'
);

select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select set_config('my_diary.e2c_reject_invitation',
  public.my_diary_create_exchange_invitation(
    'd2600000-0000-4000-8000-000000000004'
  )::text,true);
reset role;
select set_config('request.jwt.claim.sub',
  'd2600000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_reject_exchange_invitation(
      current_setting('my_diary.e2c_reject_invitation')::uuid
    )$$,
  'invitee can reject through the existing RPC'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.notifications
   where exchange_invitation_id =
     current_setting('my_diary.e2c_reject_invitation')::uuid),
  1::bigint,
  'invitation rejection creates no additional notification'
);

-- Settings RLS exposes only the active owner.
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select pg_catalog.count(*)
   from public.exchange_notification_preferences),
  1::bigint,
  'active viewer sees only their preference row'
);
select is(
  (select pg_catalog.count(*) from public.exchange_diary_mutes),
  3::bigint,
  'active participant sees only their own mute rows for visible diaries'
);
select throws_ok(
  $$update public.exchange_notification_preferences
      set new_entry_enabled = false$$,
  '42501',null,
  'direct preference update remains unavailable'
);
reset role;

-- Notification failure rolls back invitation, accept, and entry source work.
create function pg_temp.my_diary_force_exchange_notification_failure()
returns trigger
language plpgsql
as $function$
begin
  if new.notification_type = current_setting(
       'my_diary.e2c_fail_notification_type', true
     ) then
    raise exception 'Forced exchange notification failure.';
  end if;
  return new;
end;
$function$;

create trigger my_diary_test_force_exchange_notification_failure
before insert on public.notifications
for each row execute function
  pg_temp.my_diary_force_exchange_notification_failure();

select set_config('my_diary.e2c_fail_notification_type',
  'exchange_invitation',true);
select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_invitation(
      'b2600000-0000-4000-8000-000000000002'
    )$$,
  'P0001','Forced exchange notification failure.',
  'notification failure aborts invitation creation'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.exchange_invitations
   where inviter_user_id = 'c2600000-0000-4000-8000-000000000003'
     and invitee_user_id = 'b2600000-0000-4000-8000-000000000002'),
  0::bigint,
  'failed invitation notification rolls back the invitation row'
);

select set_config('my_diary.e2c_fail_notification_type','',true);
select set_config('request.jwt.claim.sub',
  'c2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select set_config('my_diary.e2c_atomic_accept_invitation',
  public.my_diary_create_exchange_invitation(
    'b2600000-0000-4000-8000-000000000002'
  )::text,true);
reset role;

select set_config('my_diary.e2c_before_accept_diaries',
  (select pg_catalog.count(*)::text from public.exchange_diaries),true);
select set_config('my_diary.e2c_before_accept_participants',
  (select pg_catalog.count(*)::text
   from public.exchange_diary_participants),true);
select set_config('my_diary.e2c_before_accept_mutes',
  (select pg_catalog.count(*)::text from public.exchange_diary_mutes),true);

select set_config('my_diary.e2c_fail_notification_type',
  'exchange_invitation_accepted',true);
select set_config('request.jwt.claim.sub',
  'b2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_accept_exchange_invitation(
      current_setting('my_diary.e2c_atomic_accept_invitation')::uuid
    )$$,
  'P0001','Forced exchange notification failure.',
  'accepted notification failure aborts the accept transaction'
);
reset role;

select results_eq(
  $$select status, processed_at, diary_id
    from public.exchange_invitations
    where id = current_setting(
      'my_diary.e2c_atomic_accept_invitation'
    )::uuid$$,
  $$values ('pending'::text,null::timestamptz,null::uuid)$$,
  'failed accept leaves invitation pending with no diary link'
);
select is(
  (select pg_catalog.count(*) from public.exchange_diaries),
  current_setting('my_diary.e2c_before_accept_diaries')::bigint,
  'failed accepted notification rolls back the diary'
);
select is(
  (select pg_catalog.count(*) from public.exchange_diary_participants),
  current_setting('my_diary.e2c_before_accept_participants')::bigint,
  'failed accepted notification rolls back both participants'
);
select is(
  (select pg_catalog.count(*) from public.exchange_diary_mutes),
  current_setting('my_diary.e2c_before_accept_mutes')::bigint,
  'failed accepted notification rolls back both mute rows'
);

select set_config('my_diary.e2c_fail_notification_type','exchange_entry',true);
select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      current_setting('my_diary.e2c_diary')::uuid,
      null,'atomic entry',null,null,array['atomicnotify']
    )$$,
  'P0001','Forced exchange notification failure.',
  'entry notification failure aborts entry and tag work'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.exchange_entries
   where body = 'atomic entry'),
  0::bigint,
  'failed entry notification rolls back the entry'
);
select is(
  (select pg_catalog.count(*) from public.tags
   where normalized_name = 'atomicnotify'),
  0::bigint,
  'failed entry notification rolls back tag master work'
);

insert into storage.objects (id,bucket_id,name,owner_id,metadata)
values (
  'f2690000-0000-4000-8000-000000000009',
  'exchange-entry-images',
  'a2600000-0000-4000-8000-000000000001/' ||
    current_setting('my_diary.e2c_diary') ||
    '/e2600000-0000-4000-8000-000000000009/' ||
    'f2600000-0000-4000-8000-000000000009',
  'a2600000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'::jsonb
);

select set_config('request.jwt.claim.sub',
  'a2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2600000-0000-4000-8000-000000000009',
      current_setting('my_diary.e2c_diary')::uuid,
      null,'atomic image entry',null,null,array['atomicimage'],
      array[
        'a2600000-0000-4000-8000-000000000001/' ||
        current_setting('my_diary.e2c_diary') ||
        '/e2600000-0000-4000-8000-000000000009/' ||
        'f2600000-0000-4000-8000-000000000009'
      ]
    )$$,
  'P0001','Forced exchange notification failure.',
  'image entry notification failure aborts entry tag and image metadata work'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.exchange_entries
   where id = 'e2600000-0000-4000-8000-000000000009'),
  0::bigint,
  'failed image entry notification rolls back the entry'
);
select is(
  (select pg_catalog.count(*) from public.tags
   where normalized_name = 'atomicimage'),
  0::bigint,
  'failed image entry notification rolls back tag master work'
);
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2600000-0000-4000-8000-000000000009'),
  0::bigint,
  'failed image entry notification rolls back image metadata'
);
select is(
  (select pg_catalog.count(*) from storage.objects
   where id = 'f2690000-0000-4000-8000-000000000009'),
  1::bigint,
  'pre-uploaded Storage object remains outside the DB RPC transaction'
);

drop trigger my_diary_test_force_exchange_notification_failure
on public.notifications;

-- Existing notification target shape and self-notification checks remain strict.
select throws_ok(
  $$insert into public.notifications(
      recipient_user_id,actor_user_id,notification_type,exchange_diary_id
    ) values (
      'a2600000-0000-4000-8000-000000000001',
      'b2600000-0000-4000-8000-000000000002',
      'follow',current_setting('my_diary.e2c_diary')::uuid
    )$$,
  '23514',null,
  'existing follow shape rejects an exchange target'
);

select throws_ok(
  $$insert into public.notifications(
      recipient_user_id,actor_user_id,notification_type,
      exchange_diary_id,exchange_entry_id
    ) values (
      'a2600000-0000-4000-8000-000000000001',
      'a2600000-0000-4000-8000-000000000001',
      'exchange_entry',current_setting('my_diary.e2c_diary')::uuid,
      'e2600000-0000-4000-8000-000000000001'
    )$$,
  '23514',null,
  'self notification remains impossible for exchange types'
);

select * from finish();

rollback;
