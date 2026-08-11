begin;

do $preflight$
declare
  notifications_oid oid := pg_catalog.to_regclass('public.notifications');
begin
  if notifications_oid is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.exchange_invitations') is null
     or pg_catalog.to_regclass('public.exchange_diaries') is null
     or pg_catalog.to_regclass('public.exchange_diary_participants') is null
     or pg_catalog.to_regclass('public.exchange_entries') is null
     or pg_catalog.to_regprocedure('public.my_diary_set_updated_at()') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_can_view_exchange_diary(uuid)'
     ) is null then
    raise exception
      'add_exchange_diary_notifications preflight failed: required dependency missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = notifications_oid
      and attname in (
        'exchange_invitation_id', 'exchange_diary_id', 'exchange_entry_id'
      )
      and attnum > 0
      and not attisdropped
  )
  or pg_catalog.to_regclass('public.exchange_notification_preferences') is not null
  or pg_catalog.to_regclass('public.exchange_diary_mutes') is not null
  or pg_catalog.to_regprocedure(
       'public.my_diary_update_exchange_notification_preference(boolean)'
     ) is not null
  or pg_catalog.to_regprocedure(
       'public.my_diary_update_exchange_diary_mute(uuid,boolean)'
     ) is not null
  or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_create_exchange_invitation_notification(uuid,text)'
     ) is not null
  or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_create_exchange_entry_notification(uuid)'
     ) is not null then
    raise exception
      'add_exchange_diary_notifications preflight failed: new objects already exist';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute
    where attrelid = notifications_oid
      and attnum > 0
      and not attisdropped
  ) <> 8
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname = 'my_diary_notifications_type_check'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%follow%reaction%comment%reply%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname = 'my_diary_notifications_target_shape_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%target_post_id%'
      and pg_catalog.pg_get_constraintdef(oid) like '%target_comment_id%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname = 'my_diary_notifications_not_self_check'
  ) then
    raise exception
      'add_exchange_diary_notifications preflight failed: notification shape differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = notifications_oid
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname in (
        'my_diary_notifications_select_recipient',
        'my_diary_notifications_update_read_state'
      )
      and roles = array['authenticated']::name[]
  ) <> 2
  or not pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'SELECT'
     )
  or not pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'is_read', 'UPDATE'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'INSERT, DELETE'
     ) then
    raise exception
      'add_exchange_diary_notifications preflight failed: notification RLS or ACL differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_follows_generate_notification',
      'my_diary_reactions_generate_notification',
      'my_diary_comments_generate_notification'
    )
      and tgenabled = 'O'
      and not tgisinternal
  ) <> 3 then
    raise exception
      'add_exchange_diary_notifications preflight failed: notification triggers differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join (
      values
        ('my_diary_create_exchange_invitation', '2950'::oidvector,
         array['p_invitee_user_id']::text[]),
        ('my_diary_accept_exchange_invitation', '2950'::oidvector,
         array['p_invitation_id']::text[]),
        ('my_diary_create_exchange_entry',
         '2950 25 25 25 25 1009'::oidvector,
         array['p_diary_id','p_title','p_body','p_mood',
               'p_location_name','p_tags']::text[]),
        ('my_diary_create_exchange_entry_with_images',
         '2950 2950 25 25 25 25 1009 1009'::oidvector,
         array['p_entry_id','p_diary_id','p_title','p_body','p_mood',
               'p_location_name','p_tags','p_image_paths']::text[])
    ) as expected(function_name, argument_types, argument_names)
      on expected.function_name = function_definition.proname
     and expected.argument_types = function_definition.proargtypes
     and expected.argument_names = function_definition.proargnames
    where namespace.nspname = 'public'
      and function_definition.prorettype = 'uuid'::pg_catalog.regtype
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) <> 4 then
    raise exception
      'add_exchange_diary_notifications preflight failed: exchange RPC catalog differs';
  end if;
end;
$preflight$;

alter table public.notifications
  add column exchange_invitation_id uuid,
  add column exchange_diary_id uuid,
  add column exchange_entry_id uuid,
  add constraint my_diary_notifications_exchange_invitation_id_fkey
    foreign key (exchange_invitation_id)
    references public.exchange_invitations (id)
    on delete cascade,
  add constraint my_diary_notifications_exchange_diary_id_fkey
    foreign key (exchange_diary_id)
    references public.exchange_diaries (id)
    on delete cascade,
  add constraint my_diary_notifications_exchange_entry_id_fkey
    foreign key (exchange_entry_id)
    references public.exchange_entries (id)
    on delete cascade;

alter table public.notifications
  drop constraint my_diary_notifications_type_check,
  drop constraint my_diary_notifications_target_shape_check,
  add constraint my_diary_notifications_type_check
    check (notification_type in (
      'follow', 'reaction', 'comment', 'reply',
      'exchange_invitation', 'exchange_invitation_accepted', 'exchange_entry'
    )),
  add constraint my_diary_notifications_target_shape_check
    check (
      (
        notification_type = 'follow'
        and target_post_id is null
        and target_comment_id is null
        and exchange_invitation_id is null
        and exchange_diary_id is null
        and exchange_entry_id is null
      )
      or (
        notification_type = 'reaction'
        and target_post_id is not null
        and target_comment_id is null
        and exchange_invitation_id is null
        and exchange_diary_id is null
        and exchange_entry_id is null
      )
      or (
        notification_type in ('comment', 'reply')
        and target_post_id is not null
        and target_comment_id is not null
        and exchange_invitation_id is null
        and exchange_diary_id is null
        and exchange_entry_id is null
      )
      or (
        notification_type = 'exchange_invitation'
        and target_post_id is null
        and target_comment_id is null
        and exchange_invitation_id is not null
        and exchange_diary_id is null
        and exchange_entry_id is null
      )
      or (
        notification_type = 'exchange_invitation_accepted'
        and target_post_id is null
        and target_comment_id is null
        and exchange_invitation_id is not null
        and exchange_diary_id is not null
        and exchange_entry_id is null
      )
      or (
        notification_type = 'exchange_entry'
        and target_post_id is null
        and target_comment_id is null
        and exchange_invitation_id is null
        and exchange_diary_id is not null
        and exchange_entry_id is not null
      )
    );

create table public.exchange_notification_preferences (
  user_id uuid not null,
  new_entry_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_exchange_notification_preferences_pkey
    primary key (user_id),
  constraint my_diary_exchange_notification_preferences_user_id_fkey
    foreign key (user_id)
    references public.accounts (user_id)
    on delete cascade
);

create table public.exchange_diary_mutes (
  participant_id uuid not null,
  muted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_exchange_diary_mutes_pkey
    primary key (participant_id),
  constraint my_diary_exchange_diary_mutes_participant_id_fkey
    foreign key (participant_id)
    references public.exchange_diary_participants (id)
    on delete cascade
);

alter table public.exchange_notification_preferences owner to postgres;
alter table public.exchange_diary_mutes owner to postgres;

insert into public.exchange_notification_preferences (user_id)
select account.user_id
from public.accounts as account
order by account.user_id
on conflict (user_id) do nothing;

insert into public.exchange_diary_mutes (participant_id)
select participant.id
from public.exchange_diary_participants as participant
order by participant.diary_id, participant.position, participant.id
on conflict (participant_id) do nothing;

create function my_diary_private.my_diary_initialize_exchange_notification_preference()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  insert into public.exchange_notification_preferences (user_id)
  values (new.user_id);
  return new;
end;
$function$;

alter function
  my_diary_private.my_diary_initialize_exchange_notification_preference()
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_initialize_exchange_notification_preference()
  from public, anon, authenticated, service_role, authenticator;

create trigger my_diary_accounts_initialize_exchange_notification_preference
after insert on public.accounts
for each row execute function
  my_diary_private.my_diary_initialize_exchange_notification_preference();

create trigger my_diary_exchange_notification_preferences_set_updated_at
before update on public.exchange_notification_preferences
for each row execute function public.my_diary_set_updated_at();

create trigger my_diary_exchange_diary_mutes_set_updated_at
before update on public.exchange_diary_mutes
for each row execute function public.my_diary_set_updated_at();

alter table public.exchange_notification_preferences enable row level security;
alter table public.exchange_diary_mutes enable row level security;

revoke all on table public.exchange_notification_preferences
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.exchange_diary_mutes
  from public, anon, authenticated, service_role, authenticator;
grant select on table public.exchange_notification_preferences to authenticated;
grant select on table public.exchange_diary_mutes to authenticated;

create policy my_diary_exchange_notification_preferences_select_own
on public.exchange_notification_preferences
for select
to authenticated
using (
  user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

create policy my_diary_exchange_diary_mutes_select_own
on public.exchange_diary_mutes
for select
to authenticated
using (
  my_diary_private.my_diary_is_account_active((select auth.uid()))
  and exists (
    select 1
    from public.exchange_diary_participants as participant
    where participant.id = exchange_diary_mutes.participant_id
      and participant.user_id = (select auth.uid())
  )
);

create function public.my_diary_update_exchange_notification_preference(
  p_new_entry_enabled boolean
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  locked_user_id uuid;
begin
  if p_new_entry_enabled is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange notification preference input.';
  end if;

  select account.user_id
  into locked_user_id
  from public.accounts as account
  where account.user_id = viewer_user_id
    and account.status = 'active'
  for update;

  if locked_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange notification preference is unavailable.';
  end if;

  perform preference.user_id
  from public.exchange_notification_preferences as preference
  where preference.user_id = viewer_user_id
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange notification preference is unavailable.';
  end if;

  update public.exchange_notification_preferences as preference
  set new_entry_enabled = p_new_entry_enabled
  where preference.user_id = viewer_user_id;

  return true;
end;
$function$;

create function public.my_diary_update_exchange_diary_mute(
  p_diary_id uuid,
  p_muted boolean
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  participant_user_ids uuid[];
  viewer_participant_id uuid;
  participant_count integer;
  locked_account_count integer;
  locked_participant_count integer;
  locked_diary_state text;
begin
  if p_diary_id is null or p_muted is null or viewer_user_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary mute input.';
  end if;

  select
    pg_catalog.array_agg(participant.user_id order by participant.user_id),
    pg_catalog.count(*),
    (pg_catalog.max(participant.id::text) filter (
      where participant.user_id = viewer_user_id
    ))::uuid
  into participant_user_ids, participant_count, viewer_participant_id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id;

  if participant_count <> 2
     or viewer_participant_id is null
     or pg_catalog.cardinality(participant_user_ids) <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary mute is unavailable.';
  end if;

  perform account.user_id
  from public.accounts as account
  where account.user_id = any(participant_user_ids)
  order by account.user_id
  for update;
  get diagnostics locked_account_count = row_count;

  select diary.state
  into locked_diary_state
  from public.exchange_diaries as diary
  where diary.id = p_diary_id
  for update;

  perform participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = p_diary_id
  order by participant.position, participant.id
  for update;
  get diagnostics locked_participant_count = row_count;

  if locked_account_count <> 2
     or locked_participant_count <> 2
     or locked_diary_state <> 'active'
     or (
       select pg_catalog.count(*)
       from public.accounts as account
       where account.user_id = any(participant_user_ids)
         and account.status = 'active'
     ) <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary mute is unavailable.';
  end if;

  perform mute.participant_id
  from public.exchange_diary_mutes as mute
  where mute.participant_id = viewer_participant_id
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary mute is unavailable.';
  end if;

  update public.exchange_diary_mutes as mute
  set muted = p_muted
  where mute.participant_id = viewer_participant_id;

  return true;
end;
$function$;

alter function public.my_diary_update_exchange_notification_preference(boolean)
  owner to postgres;
alter function public.my_diary_update_exchange_diary_mute(uuid,boolean)
  owner to postgres;
revoke all on function
  public.my_diary_update_exchange_notification_preference(boolean)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_exchange_diary_mute(uuid,boolean)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function
  public.my_diary_update_exchange_notification_preference(boolean)
  to authenticated;
grant execute on function public.my_diary_update_exchange_diary_mute(uuid,boolean)
  to authenticated;

create function my_diary_private.my_diary_create_exchange_invitation_notification(
  p_invitation_id uuid,
  p_notification_type text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  invitation_record public.exchange_invitations%rowtype;
begin
  if p_invitation_id is null
     or p_notification_type not in (
       'exchange_invitation', 'exchange_invitation_accepted'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange notification operation is unavailable.';
  end if;

  select invitation.*
  into invitation_record
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id;

  if invitation_record.id is null
     or not my_diary_private.my_diary_is_account_active(
       invitation_record.inviter_user_id
     )
     or not my_diary_private.my_diary_is_account_active(
       invitation_record.invitee_user_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange notification operation is unavailable.';
  end if;

  if p_notification_type = 'exchange_invitation' then
    if invitation_record.status <> 'pending'
       or invitation_record.diary_id is not null then
      raise exception using
        errcode = '42501',
        message = 'Exchange notification operation is unavailable.';
    end if;

    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type,
      exchange_invitation_id
    ) values (
      invitation_record.invitee_user_id,
      invitation_record.inviter_user_id,
      'exchange_invitation', invitation_record.id
    );
  else
    if invitation_record.status <> 'accepted'
       or invitation_record.diary_id is null
       or not exists (
         select 1
         from public.exchange_diary_participants as participant
         where participant.diary_id = invitation_record.diary_id
           and participant.position = 1
           and participant.user_id = invitation_record.inviter_user_id
       )
       or not exists (
         select 1
         from public.exchange_diary_participants as participant
         where participant.diary_id = invitation_record.diary_id
           and participant.position = 2
           and participant.user_id = invitation_record.invitee_user_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Exchange notification operation is unavailable.';
    end if;

    insert into public.notifications (
      recipient_user_id, actor_user_id, notification_type,
      exchange_invitation_id, exchange_diary_id
    ) values (
      invitation_record.inviter_user_id,
      invitation_record.invitee_user_id,
      'exchange_invitation_accepted', invitation_record.id,
      invitation_record.diary_id
    );
  end if;

  return true;
end;
$function$;

create function my_diary_private.my_diary_create_exchange_entry_notification(
  p_entry_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target_diary_id uuid;
  actor_user_id uuid;
  recipient_user_id uuid;
  recipient_participant_id uuid;
  participant_count integer;
  preference_enabled boolean;
  diary_muted boolean;
begin
  select
    entry.diary_id,
    author_participant.user_id,
    recipient_participant.user_id,
    recipient_participant.id,
    pg_catalog.count(*) over ()
  into
    target_diary_id,
    actor_user_id,
    recipient_user_id,
    recipient_participant_id,
    participant_count
  from public.exchange_entries as entry
  join public.exchange_diary_participants as author_participant
    on author_participant.id = entry.author_participant_id
   and author_participant.diary_id = entry.diary_id
  join public.exchange_diary_participants as recipient_participant
    on recipient_participant.diary_id = entry.diary_id
   and recipient_participant.id <> author_participant.id
  where entry.id = p_entry_id;

  if target_diary_id is null
     or actor_user_id is null
     or recipient_user_id is null
     or actor_user_id = recipient_user_id
     or participant_count <> 1
     or not exists (
       select 1
       from public.exchange_diaries as diary
       where diary.id = target_diary_id
         and diary.state = 'active'
     )
     or (
       select pg_catalog.count(*)
       from public.exchange_diary_participants as participant
       join public.accounts as account
         on account.user_id = participant.user_id
        and account.status = 'active'
       where participant.diary_id = target_diary_id
     ) <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange notification operation is unavailable.';
  end if;

  select preference.new_entry_enabled
  into preference_enabled
  from public.exchange_notification_preferences as preference
  where preference.user_id = recipient_user_id
  for update;

  if preference_enabled is distinct from true then
    return false;
  end if;

  select mute.muted
  into diary_muted
  from public.exchange_diary_mutes as mute
  where mute.participant_id = recipient_participant_id
  for update;

  if diary_muted is distinct from false then
    return false;
  end if;

  insert into public.notifications (
    recipient_user_id, actor_user_id, notification_type,
    exchange_diary_id, exchange_entry_id
  ) values (
    recipient_user_id, actor_user_id, 'exchange_entry',
    target_diary_id, p_entry_id
  );

  return true;
end;
$function$;

alter function
  my_diary_private.my_diary_create_exchange_invitation_notification(uuid,text)
  owner to postgres;
alter function
  my_diary_private.my_diary_create_exchange_entry_notification(uuid)
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_create_exchange_invitation_notification(uuid,text)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_create_exchange_entry_notification(uuid)
  from public, anon, authenticated, service_role, authenticator;

drop policy my_diary_notifications_select_recipient
on public.notifications;
drop policy my_diary_notifications_update_read_state
on public.notifications;

create policy my_diary_notifications_select_recipient
on public.notifications
for select
to authenticated
using (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    (
      notification_type in ('follow', 'reaction', 'comment', 'reply')
      and (
        target_post_id is null
        or exists (
          select 1 from public.posts
          where posts.id = notifications.target_post_id
        )
      )
    )
    or (
      notification_type = 'exchange_invitation'
      and exists (
        select 1
        from public.exchange_invitations as invitation
        where invitation.id = notifications.exchange_invitation_id
          and invitation.invitee_user_id = notifications.recipient_user_id
          and invitation.inviter_user_id = notifications.actor_user_id
      )
    )
    or (
      notification_type = 'exchange_invitation_accepted'
      and exists (
        select 1
        from public.exchange_diaries as diary
        where diary.id = notifications.exchange_diary_id
      )
      and exists (
        select 1
        from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
    or (
      notification_type = 'exchange_entry'
      and exists (
        select 1
        from public.exchange_entries as entry
        where entry.id = notifications.exchange_entry_id
          and entry.diary_id = notifications.exchange_diary_id
      )
      and exists (
        select 1
        from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
  )
);

create policy my_diary_notifications_update_read_state
on public.notifications
for update
to authenticated
using (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    (
      notification_type in ('follow', 'reaction', 'comment', 'reply')
      and (
        target_post_id is null
        or exists (
          select 1 from public.posts
          where posts.id = notifications.target_post_id
        )
      )
    )
    or (
      notification_type = 'exchange_invitation'
      and exists (
        select 1 from public.exchange_invitations as invitation
        where invitation.id = notifications.exchange_invitation_id
          and invitation.invitee_user_id = notifications.recipient_user_id
          and invitation.inviter_user_id = notifications.actor_user_id
      )
    )
    or (
      notification_type = 'exchange_invitation_accepted'
      and exists (
        select 1 from public.exchange_diaries as diary
        where diary.id = notifications.exchange_diary_id
      )
      and exists (
        select 1 from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
    or (
      notification_type = 'exchange_entry'
      and exists (
        select 1 from public.exchange_entries as entry
        where entry.id = notifications.exchange_entry_id
          and entry.diary_id = notifications.exchange_diary_id
      )
      and exists (
        select 1 from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
  )
)
with check (
  recipient_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(actor_user_id)
  and (
    (
      notification_type in ('follow', 'reaction', 'comment', 'reply')
      and (
        target_post_id is null
        or exists (
          select 1 from public.posts
          where posts.id = notifications.target_post_id
        )
      )
    )
    or (
      notification_type = 'exchange_invitation'
      and exists (
        select 1 from public.exchange_invitations as invitation
        where invitation.id = notifications.exchange_invitation_id
          and invitation.invitee_user_id = notifications.recipient_user_id
          and invitation.inviter_user_id = notifications.actor_user_id
      )
    )
    or (
      notification_type = 'exchange_invitation_accepted'
      and exists (
        select 1 from public.exchange_diaries as diary
        where diary.id = notifications.exchange_diary_id
      )
      and exists (
        select 1 from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
    or (
      notification_type = 'exchange_entry'
      and exists (
        select 1 from public.exchange_entries as entry
        where entry.id = notifications.exchange_entry_id
          and entry.diary_id = notifications.exchange_diary_id
      )
      and exists (
        select 1 from public.exchange_diary_participants as participant
        where participant.diary_id = notifications.exchange_diary_id
          and participant.user_id = notifications.recipient_user_id
      )
    )
  )
);

create or replace function public.my_diary_create_exchange_invitation(
  p_invitee_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  canonical_low_user_id uuid;
  canonical_high_user_id uuid;
  mutual_follow_count integer;
  invitation_id uuid;
begin
  if p_invitee_user_id is null
     or viewer_user_id is not null
        and viewer_user_id = p_invitee_user_id then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    viewer_user_id,
    p_invitee_user_id
  );

  if viewer_user_id < p_invitee_user_id then
    canonical_low_user_id := viewer_user_id;
    canonical_high_user_id := p_invitee_user_id;
  else
    canonical_low_user_id := p_invitee_user_id;
    canonical_high_user_id := viewer_user_id;
  end if;

  perform invitation.id
  from public.exchange_invitations as invitation
  where invitation.pair_low_user_id = canonical_low_user_id
    and invitation.pair_high_user_id = canonical_high_user_id
  order by invitation.created_at, invitation.id
  for update;

  if not exists (
    select 1
    from public.accounts as viewer_account
    where viewer_account.user_id = viewer_user_id
      and viewer_account.status = 'active'
  ) or not exists (
    select 1
    from public.accounts as invitee_account
    where invitee_account.user_id = p_invitee_user_id
      and invitee_account.status = 'active'
  ) or exists (
    select 1
    from public.exchange_invitation_blocks as invitation_block
    where invitation_block.blocker_user_id = p_invitee_user_id
      and invitation_block.blocked_inviter_user_id = viewer_user_id
  ) or exists (
    select 1
    from public.exchange_invitations as pending_invitation
    where pending_invitation.pair_low_user_id = canonical_low_user_id
      and pending_invitation.pair_high_user_id = canonical_high_user_id
      and pending_invitation.status = 'pending'
  ) or exists (
    select 1
    from public.exchange_invitations as terminal_invitation
    where terminal_invitation.pair_low_user_id = canonical_low_user_id
      and terminal_invitation.pair_high_user_id = canonical_high_user_id
      and terminal_invitation.status in ('rejected', 'cancelled')
      and terminal_invitation.processed_at > now() - interval '24 hours'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform follow_relation.follower_id
  from public.follows as follow_relation
  where (
    follow_relation.follower_id = viewer_user_id
    and follow_relation.following_id = p_invitee_user_id
  ) or (
    follow_relation.follower_id = p_invitee_user_id
    and follow_relation.following_id = viewer_user_id
  )
  order by follow_relation.follower_id, follow_relation.following_id
  for update;

  get diagnostics mutual_follow_count = row_count;

  if mutual_follow_count <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  insert into public.exchange_invitations (
    inviter_user_id,
    invitee_user_id,
    status,
    processed_at,
    diary_id
  )
  values (
    viewer_user_id,
    p_invitee_user_id,
    'pending',
    null,
    null
  )
  returning id into invitation_id;

  perform
    my_diary_private.my_diary_create_exchange_invitation_notification(
      invitation_id, 'exchange_invitation'
    );

  return invitation_id;
end;
$function$;

create or replace function public.my_diary_accept_exchange_invitation(
  p_invitation_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  inviter_user_id uuid;
  invitee_user_id uuid;
  locked_inviter_user_id uuid;
  locked_invitee_user_id uuid;
  locked_status text;
  mutual_follow_count integer;
  new_diary_id uuid;
begin
  if p_invitation_id is null then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange diary operation input.';
  end if;

  if viewer_user_id is null
     or not exists (
       select 1
       from public.accounts as viewer_account
       where viewer_account.user_id = viewer_user_id
         and viewer_account.status = 'active'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select invitation.inviter_user_id, invitation.invitee_user_id
  into inviter_user_id, invitee_user_id
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id;

  if inviter_user_id is null
     or invitee_user_id is null
     or viewer_user_id <> invitee_user_id then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform my_diary_private.my_diary_lock_exchange_pair(
    inviter_user_id,
    invitee_user_id
  );

  if not exists (
    select 1
    from public.accounts as viewer_account
    where viewer_account.user_id = viewer_user_id
      and viewer_account.status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  select
    invitation.inviter_user_id,
    invitation.invitee_user_id,
    invitation.status
  into
    locked_inviter_user_id,
    locked_invitee_user_id,
    locked_status
  from public.exchange_invitations as invitation
  where invitation.id = p_invitation_id
  for update;

  if locked_inviter_user_id is null
     or locked_inviter_user_id <> inviter_user_id
     or locked_invitee_user_id <> viewer_user_id
     or locked_status <> 'pending'
     or not exists (
       select 1
       from public.accounts as inviter_account
       where inviter_account.user_id = inviter_user_id
         and inviter_account.status = 'active'
     )
     or not exists (
       select 1
       from public.accounts as invitee_account
       where invitee_account.user_id = viewer_user_id
         and invitee_account.status = 'active'
     )
     or exists (
       select 1
       from public.exchange_invitation_blocks as invitation_block
       where invitation_block.blocker_user_id = viewer_user_id
         and invitation_block.blocked_inviter_user_id = inviter_user_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform follow_relation.follower_id
  from public.follows as follow_relation
  where (
    follow_relation.follower_id = viewer_user_id
    and follow_relation.following_id = inviter_user_id
  ) or (
    follow_relation.follower_id = inviter_user_id
    and follow_relation.following_id = viewer_user_id
  )
  order by follow_relation.follower_id, follow_relation.following_id
  for update;

  get diagnostics mutual_follow_count = row_count;

  if mutual_follow_count <> 2 then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  insert into public.exchange_diaries (
    title,
    state,
    created_by_position
  )
  values (null, 'active', 1)
  returning id into new_diary_id;

  insert into public.exchange_diary_participants (
    diary_id,
    position,
    user_id
  )
  values
    (new_diary_id, 1, inviter_user_id),
    (new_diary_id, 2, viewer_user_id);

  insert into public.exchange_diary_mutes (participant_id)
  select participant.id
  from public.exchange_diary_participants as participant
  where participant.diary_id = new_diary_id
  order by participant.position, participant.id;

  update public.exchange_invitations as invitation
  set status = 'accepted',
      processed_at = now(),
      diary_id = new_diary_id
  where invitation.id = p_invitation_id
    and invitation.status = 'pending';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Exchange diary operation is unavailable.';
  end if;

  perform
    my_diary_private.my_diary_create_exchange_invitation_notification(
      p_invitation_id, 'exchange_invitation_accepted'
    );

  return new_diary_id;
end;
$function$;

create or replace function public.my_diary_create_exchange_entry(
  p_diary_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_tags text[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  author_participant_id uuid;
  new_entry_id uuid;
  normalized_title text;
  normalized_body text;
  normalized_mood text;
  normalized_location_name text;
  raw_tags text[] := coalesce(p_tags, array[]::text[]);
  canonical_tags text[] := array[]::text[];
  raw_tag text;
  canonical_tag text;
  resolved_tag_id uuid;
begin
  normalized_title := nullif(
    pg_catalog.regexp_replace(
      p_title, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  normalized_body := pg_catalog.regexp_replace(
    p_body, '^[[:space:]]+|[[:space:]]+$', '', 'g'
  );
  normalized_mood := nullif(pg_catalog.btrim(p_mood), '');
  normalized_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );

  if p_diary_id is null
     or (
       normalized_title is not null
       and pg_catalog.char_length(normalized_title) > 120
     )
     or normalized_body is null
     or pg_catalog.char_length(normalized_body) not between 1 and 10000
     or (
       normalized_mood is not null
       and normalized_mood not in (
         'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
       )
     )
     or (
       normalized_location_name is not null
       and pg_catalog.char_length(normalized_location_name) > 100
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry input.';
  end if;

  if pg_catalog.cardinality(raw_tags) > 20
     or (
       pg_catalog.cardinality(raw_tags) > 0
       and pg_catalog.array_ndims(raw_tags) <> 1
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  foreach raw_tag in array raw_tags loop
    if raw_tag is null then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    canonical_tag :=
      my_diary_private.my_diary_normalize_tag_name(raw_tag);

    if canonical_tag is null
       or pg_catalog.char_length(canonical_tag) not between 1 and 30
       or pg_catalog.strpos(canonical_tag, ',') > 0
       or pg_catalog.strpos(canonical_tag, '#') > 0
       or canonical_tag ~ '[[:cntrl:]]' then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    if not canonical_tag = any(canonical_tags) then
      canonical_tags := pg_catalog.array_append(
        canonical_tags, canonical_tag
      );
    end if;
  end loop;

  select coalesce(
    pg_catalog.array_agg(tag_name order by tag_name),
    array[]::text[]
  )
  into canonical_tags
  from pg_catalog.unnest(canonical_tags) as canonical(tag_name);

  if pg_catalog.cardinality(canonical_tags) > 5 then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  author_participant_id :=
    my_diary_private.my_diary_lock_exchange_diary_for_entry(
      p_diary_id, viewer_user_id, false
    );

  insert into public.exchange_entries (
    diary_id,
    author_participant_id,
    title,
    body,
    mood,
    location_name
  )
  values (
    p_diary_id,
    author_participant_id,
    normalized_title,
    normalized_body,
    normalized_mood,
    normalized_location_name
  )
  returning id into new_entry_id;

  foreach canonical_tag in array canonical_tags loop
    insert into public.tags (name, normalized_name)
    values (canonical_tag, canonical_tag)
    on conflict (normalized_name) do nothing;

    select tag.id
    into resolved_tag_id
    from public.tags as tag
    where tag.normalized_name = canonical_tag;

    if resolved_tag_id is null then
      raise exception using
        errcode = '40001',
        message = 'Tag resolution must be retried.';
    end if;

    insert into public.exchange_entry_tags (entry_id, tag_id)
    values (new_entry_id, resolved_tag_id);
  end loop;

  perform
    my_diary_private.my_diary_create_exchange_entry_notification(
      new_entry_id
    );

  return new_entry_id;
end;
$function$;

create or replace function public.my_diary_create_exchange_entry_with_images(
  p_entry_id uuid,
  p_diary_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_location_name text,
  p_tags text[],
  p_image_paths text[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  viewer_user_id uuid := auth.uid();
  author_participant_id uuid;
  normalized_title text;
  normalized_body text;
  normalized_mood text;
  normalized_location_name text;
  canonical_tags text[];
  image_paths text[] := coalesce(p_image_paths, array[]::text[]);
  image_path text;
  path_pattern text;
  resolved_tag_id uuid;
  canonical_tag text;
  locked_image_count integer;
begin
  normalized_title := nullif(
    pg_catalog.regexp_replace(
      p_title, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );
  normalized_body := pg_catalog.regexp_replace(
    p_body, '^[[:space:]]+|[[:space:]]+$', '', 'g'
  );
  normalized_mood := nullif(pg_catalog.btrim(p_mood), '');
  normalized_location_name := nullif(
    pg_catalog.regexp_replace(
      p_location_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'
    ),
    ''
  );

  if p_entry_id is null
     or p_diary_id is null
     or (
       normalized_title is not null
       and pg_catalog.char_length(normalized_title) > 120
     )
     or normalized_body is null
     or pg_catalog.char_length(normalized_body) not between 1 and 10000
     or (
       normalized_mood is not null
       and normalized_mood not in (
         'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
       )
     )
     or (
       normalized_location_name is not null
       and pg_catalog.char_length(normalized_location_name) > 100
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry input.';
  end if;

  canonical_tags :=
    my_diary_private.my_diary_prepare_exchange_entry_tags(p_tags);

  if pg_catalog.cardinality(image_paths) > 10
     or (
       pg_catalog.cardinality(image_paths) > 0
       and pg_catalog.array_ndims(image_paths) <> 1
     )
     or pg_catalog.array_position(image_paths, null::text) is not null
     or (
       select pg_catalog.count(*) <> pg_catalog.count(distinct candidate_path)
       from pg_catalog.unnest(image_paths) as paths(candidate_path)
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  path_pattern :=
    '^' || viewer_user_id::text || '/' || p_diary_id::text || '/' ||
    p_entry_id::text ||
    '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  foreach image_path in array image_paths loop
    if pg_catalog.char_length(image_path) not between 1 and 1024
       or image_path !~ path_pattern then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
    end if;
  end loop;

  author_participant_id :=
    my_diary_private.my_diary_lock_exchange_diary_for_entry(
      p_diary_id, viewer_user_id, false
    );

  perform object.id
  from storage.objects as object
  where object.bucket_id = 'exchange-entry-images'
    and object.name = any(image_paths)
    and object.owner_id = viewer_user_id::text
    and object.metadata ->> 'mimetype' in (
      'image/jpeg', 'image/png', 'image/webp'
    )
    and case
      when object.metadata ->> 'size' ~ '^[0-9]+$'
      then (object.metadata ->> 'size')::numeric between 1 and 6291456
      else false
    end
  order by object.name, object.id
  for update;

  get diagnostics locked_image_count = row_count;

  if locked_image_count <> pg_catalog.cardinality(image_paths) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  if exists (
       select 1
       from public.exchange_entry_images as image
       where image.storage_path = any(image_paths)
          or image.id = any(
            select pg_catalog.split_part(candidate_path, '/', 4)::uuid
            from pg_catalog.unnest(image_paths) as paths(candidate_path)
          )
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid exchange entry image input.';
  end if;

  if exists (
       select 1
       from public.exchange_entries as entry
       where entry.id = p_entry_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Exchange entry operation is unavailable.';
  end if;

  begin
    insert into public.exchange_entries (
      id,
      diary_id,
      author_participant_id,
      title,
      body,
      mood,
      location_name
    )
    values (
      p_entry_id,
      p_diary_id,
      author_participant_id,
      normalized_title,
      normalized_body,
      normalized_mood,
      normalized_location_name
    );
  exception
    when unique_violation then
      raise exception using
        errcode = '42501',
        message = 'Exchange entry operation is unavailable.';
  end;

  foreach canonical_tag in array canonical_tags loop
    insert into public.tags (name, normalized_name)
    values (canonical_tag, canonical_tag)
    on conflict (normalized_name) do nothing;

    select tag.id
    into resolved_tag_id
    from public.tags as tag
    where tag.normalized_name = canonical_tag;

    if resolved_tag_id is null then
      raise exception using
        errcode = '40001',
        message = 'Tag resolution must be retried.';
    end if;

    insert into public.exchange_entry_tags (entry_id, tag_id)
    values (p_entry_id, resolved_tag_id);
  end loop;

  begin
    insert into public.exchange_entry_images (
      id,
      entry_id,
      storage_path,
      sort_order
    )
    select
      pg_catalog.split_part(candidate_path, '/', 4)::uuid,
      p_entry_id,
      candidate_path,
      (ordinality - 1)::smallint
    from pg_catalog.unnest(image_paths) with ordinality
      as paths(candidate_path, ordinality);
  exception
    when unique_violation then
      raise exception using
        errcode = '22023',
        message = 'Invalid exchange entry image input.';
  end;

  perform
    my_diary_private.my_diary_create_exchange_entry_notification(p_entry_id);

  return p_entry_id;
end;
$function$;

alter function public.my_diary_create_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_accept_exchange_invitation(uuid)
  owner to postgres;
alter function public.my_diary_create_exchange_entry(
  uuid,text,text,text,text,text[]
) owner to postgres;
alter function public.my_diary_create_exchange_entry_with_images(
  uuid,uuid,text,text,text,text,text[],text[]
) owner to postgres;

revoke all on function public.my_diary_create_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_accept_exchange_invitation(uuid)
  from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_create_exchange_entry(
  uuid,text,text,text,text,text[]
) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_create_exchange_entry_with_images(
  uuid,uuid,text,text,text,text,text[],text[]
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_exchange_invitation(uuid)
  to authenticated;
grant execute on function public.my_diary_accept_exchange_invitation(uuid)
  to authenticated;
grant execute on function public.my_diary_create_exchange_entry(
  uuid,text,text,text,text,text[]
) to authenticated;
grant execute on function public.my_diary_create_exchange_entry_with_images(
  uuid,uuid,text,text,text,text,text[],text[]
) to authenticated;

do $postcondition$
declare
  notifications_oid oid := 'public.notifications'::pg_catalog.regclass;
  preferences_oid oid :=
    'public.exchange_notification_preferences'::pg_catalog.regclass;
  mutes_oid oid := 'public.exchange_diary_mutes'::pg_catalog.regclass;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute
    where attrelid = notifications_oid
      and attnum > 0
      and not attisdropped
  ) <> 11
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute
    where attrelid = notifications_oid
      and attname in (
        'exchange_invitation_id', 'exchange_diary_id', 'exchange_entry_id'
      )
      and atttypid = 'uuid'::pg_catalog.regtype
      and not attnotnull
      and attnum > 0
      and not attisdropped
  ) <> 3 then
    raise exception
      'add_exchange_diary_notifications postcondition failed: notification columns differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname in (
        'my_diary_notifications_exchange_invitation_id_fkey',
        'my_diary_notifications_exchange_diary_id_fkey',
        'my_diary_notifications_exchange_entry_id_fkey'
      )
      and contype = 'f'
      and confdeltype = 'c'
  ) <> 3
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname = 'my_diary_notifications_type_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_invitation%'
      and pg_catalog.pg_get_constraintdef(oid) like
        '%exchange_invitation_accepted%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_entry%'
  )
  or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = notifications_oid
      and conname = 'my_diary_notifications_target_shape_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_invitation_id%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_diary_id%'
      and pg_catalog.pg_get_constraintdef(oid) like '%exchange_entry_id%'
  ) then
    raise exception
      'add_exchange_diary_notifications postcondition failed: notification constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'notifications'
      and indexname = 'my_diary_notifications_recipient_created_id_idx'
      and indexdef like '%(recipient_user_id, created_at DESC, id DESC)%'
  )
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname in (
        'my_diary_notifications_select_recipient',
        'my_diary_notifications_update_read_state'
      )
      and roles = array['authenticated']::name[]
      and qual like '%exchange_invitation_id%'
      and qual like '%exchange_diary_id%'
      and qual like '%exchange_entry_id%'
  ) <> 2
  or not pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'SELECT'
     )
  or not pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'is_read', 'UPDATE'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', notifications_oid, 'INSERT, DELETE'
     )
  or pg_catalog.has_column_privilege(
       'authenticated', notifications_oid, 'exchange_diary_id', 'UPDATE'
     ) then
    raise exception
      'add_exchange_diary_notifications postcondition failed: notification RLS ACL or index differs';
  end if;

  if not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class where oid = preferences_oid
  )
  or not (
    select relrowsecurity
      and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class where oid = mutes_oid
  )
  or not pg_catalog.has_table_privilege(
       'authenticated', preferences_oid, 'SELECT'
     )
  or not pg_catalog.has_table_privilege(
       'authenticated', mutes_oid, 'SELECT'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', preferences_oid, 'INSERT, UPDATE, DELETE'
     )
  or pg_catalog.has_table_privilege(
       'authenticated', mutes_oid, 'INSERT, UPDATE, DELETE'
     )
  or exists (
    select 1
    from public.accounts as account
    left join public.exchange_notification_preferences as preference
      on preference.user_id = account.user_id
    where preference.user_id is null
       or preference.new_entry_enabled is distinct from true
  )
  or exists (
    select 1
    from public.exchange_diary_participants as participant
    left join public.exchange_diary_mutes as mute
      on mute.participant_id = participant.id
    where mute.participant_id is null
       or mute.muted is distinct from false
  ) then
    raise exception
      'add_exchange_diary_notifications postcondition failed: preference mute RLS ACL or backfill differs';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_accounts_initialize_exchange_notification_preference',
      'my_diary_exchange_notification_preferences_set_updated_at',
      'my_diary_exchange_diary_mutes_set_updated_at'
    )
      and tgenabled = 'O'
      and not tgisinternal
  ) <> 3
  or (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgname in (
      'my_diary_follows_generate_notification',
      'my_diary_reactions_generate_notification',
      'my_diary_comments_generate_notification'
    )
      and tgenabled = 'O'
      and not tgisinternal
  ) <> 3 then
    raise exception
      'add_exchange_diary_notifications postcondition failed: triggers differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where (
      namespace.nspname = 'public'
      and function_definition.proname in (
        'my_diary_update_exchange_notification_preference',
        'my_diary_update_exchange_diary_mute',
        'my_diary_create_exchange_invitation',
        'my_diary_accept_exchange_invitation',
        'my_diary_create_exchange_entry',
        'my_diary_create_exchange_entry_with_images'
      )
      or namespace.nspname = 'my_diary_private'
      and function_definition.proname in (
        'my_diary_initialize_exchange_notification_preference',
        'my_diary_create_exchange_invitation_notification',
        'my_diary_create_exchange_entry_notification'
      )
    )
      and function_definition.provolatile = 'v'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ) <> 9 then
    raise exception
      'add_exchange_diary_notifications postcondition failed: function attributes differ';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(array[
      'my_diary_private.my_diary_initialize_exchange_notification_preference()',
      'my_diary_private.my_diary_create_exchange_invitation_notification(uuid,text)',
      'my_diary_private.my_diary_create_exchange_entry_notification(uuid)'
    ]) as helper(signature)
    cross join pg_catalog.unnest(array[
      'anon', 'authenticated', 'service_role', 'authenticator'
    ]) as denied(role_name)
    where pg_catalog.has_function_privilege(
      denied.role_name, helper.signature, 'EXECUTE'
    )
  )
  or exists (
    select 1
    from pg_catalog.unnest(array[
      'public.my_diary_update_exchange_notification_preference(boolean)',
      'public.my_diary_update_exchange_diary_mute(uuid,boolean)',
      'public.my_diary_create_exchange_invitation(uuid)',
      'public.my_diary_accept_exchange_invitation(uuid)',
      'public.my_diary_create_exchange_entry(uuid,text,text,text,text,text[])',
      'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'
    ]) as rpc(signature)
    where not pg_catalog.has_function_privilege(
      'authenticated', rpc.signature, 'EXECUTE'
    )
       or pg_catalog.has_function_privilege('anon', rpc.signature, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'authenticator', rpc.signature, 'EXECUTE'
       )
  ) then
    raise exception
      'add_exchange_diary_notifications postcondition failed: function ACL differs';
  end if;
end;
$postcondition$;

commit;
