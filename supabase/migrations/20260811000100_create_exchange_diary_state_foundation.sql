begin;

do $preflight$
begin
  if pg_catalog.to_regnamespace('my_diary_private') is null
     or pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regprocedure(
       'public.my_diary_set_updated_at()'
     ) is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_account_active(uuid)'
     ) is null then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: required core objects are missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where (
      namespace.nspname = 'public'
      and relation.relname in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
    ) or (
      namespace.nspname = 'my_diary_private'
      and relation.relname = 'my_diary_exchange_pair_locks'
    )
  ) then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: a target relation already exists';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname in (
        'my_diary_reject_exchange_diary_reactivation',
        'my_diary_enforce_exchange_diary_exact_two',
        'my_diary_enforce_exchange_invitation_transition',
        'my_diary_can_view_exchange_diary'
      )
  ) then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: a target function already exists';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname in ('public', 'my_diary_private')
      and relation.relname in (
        'my_diary_exchange_diary_participants_diary_user_key',
        'my_diary_exchange_diary_participants_user_diary_idx',
        'my_diary_exchange_invitations_pending_pair_key'
      )
  ) then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: a target index already exists';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role
      where role.rolname = required.role_name
    )
  ) then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: a required Supabase role is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.accounts'::pg_catalog.regclass
      and conname = 'my_diary_accounts_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.accounts'::pg_catalog.regclass
      and conname = 'my_diary_accounts_status_check'
      and contype = 'c'
      and convalidated
  ) then
    raise exception
      'create_exchange_diary_state_foundation preflight failed: accounts definition differs';
  end if;
end;
$preflight$;

create table public.exchange_diaries (
  id uuid not null default gen_random_uuid(),
  title text,
  state text not null default 'active',
  created_by_position smallint not null,
  started_at timestamptz not null default now(),
  archived_at timestamptz,
  archive_cause text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint my_diary_exchange_diaries_pkey primary key (id),
  constraint my_diary_exchange_diaries_title_check
    check (
      title is null
      or (
        char_length(btrim(title)) between 1 and 120
        and title = btrim(title)
      )
    ),
  constraint my_diary_exchange_diaries_state_check
    check (state in ('active', 'archived')),
  constraint my_diary_exchange_diaries_created_by_position_check
    check (created_by_position in (1, 2)),
  constraint my_diary_exchange_diaries_archive_shape_check
    check (
      (
        state = 'active'
        and archived_at is null
        and archive_cause is null
      )
      or (
        state = 'archived'
        and archived_at is not null
        and archive_cause is not null
        and char_length(btrim(archive_cause)) between 1 and 64
        and archive_cause = btrim(archive_cause)
      )
    )
);

create table public.exchange_diary_participants (
  id uuid not null default gen_random_uuid(),
  diary_id uuid not null,
  position smallint not null,
  user_id uuid,
  joined_at timestamptz not null default now(),
  account_deleted_at timestamptz,
  constraint my_diary_exchange_diary_participants_pkey primary key (id),
  constraint my_diary_exchange_diary_participants_diary_id_fkey
    foreign key (diary_id)
    references public.exchange_diaries (id)
    on delete cascade,
  constraint my_diary_exchange_diary_participants_user_id_fkey
    foreign key (user_id)
    references public.accounts (user_id)
    on delete set null,
  constraint my_diary_exchange_diary_participants_position_check
    check (position in (1, 2)),
  constraint my_diary_exchange_diary_participants_diary_position_key
    unique (diary_id, position),
  constraint my_diary_exchange_diary_participants_diary_id_id_key
    unique (diary_id, id)
);

create unique index my_diary_exchange_diary_participants_diary_user_key
  on public.exchange_diary_participants (diary_id, user_id)
  where user_id is not null;

create index my_diary_exchange_diary_participants_user_diary_idx
  on public.exchange_diary_participants (user_id, diary_id)
  where user_id is not null;

create table public.exchange_invitations (
  id uuid not null default gen_random_uuid(),
  inviter_user_id uuid not null,
  invitee_user_id uuid not null,
  pair_low_user_id uuid generated always as (
    case
      when inviter_user_id < invitee_user_id then inviter_user_id
      else invitee_user_id
    end
  ) stored,
  pair_high_user_id uuid generated always as (
    case
      when inviter_user_id < invitee_user_id then invitee_user_id
      else inviter_user_id
    end
  ) stored,
  status text not null default 'pending',
  diary_id uuid,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  constraint my_diary_exchange_invitations_pkey primary key (id),
  constraint my_diary_exchange_invitations_inviter_user_id_fkey
    foreign key (inviter_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_invitations_invitee_user_id_fkey
    foreign key (invitee_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_invitations_diary_id_fkey
    foreign key (diary_id)
    references public.exchange_diaries (id)
    on delete cascade,
  constraint my_diary_exchange_invitations_not_self_check
    check (inviter_user_id <> invitee_user_id),
  constraint my_diary_exchange_invitations_status_check
    check (
      status in (
        'pending', 'accepted', 'rejected', 'cancelled', 'invalidated'
      )
    ),
  constraint my_diary_exchange_invitations_shape_check
    check (
      (
        status = 'pending'
        and processed_at is null
        and diary_id is null
      )
      or (
        status = 'accepted'
        and processed_at is not null
        and diary_id is not null
      )
      or (
        status in ('rejected', 'cancelled', 'invalidated')
        and processed_at is not null
        and diary_id is null
      )
    )
);

create unique index my_diary_exchange_invitations_pending_pair_key
  on public.exchange_invitations (pair_low_user_id, pair_high_user_id)
  where status = 'pending';

create table my_diary_private.my_diary_exchange_pair_locks (
  pair_low_user_id uuid not null,
  pair_high_user_id uuid not null,
  constraint my_diary_exchange_pair_locks_pkey
    primary key (pair_low_user_id, pair_high_user_id),
  constraint my_diary_exchange_pair_locks_low_user_id_fkey
    foreign key (pair_low_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_pair_locks_high_user_id_fkey
    foreign key (pair_high_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_pair_locks_canonical_check
    check (pair_low_user_id < pair_high_user_id)
);

create table public.exchange_invitation_blocks (
  blocker_user_id uuid not null,
  blocked_inviter_user_id uuid not null,
  created_at timestamptz not null default now(),
  constraint my_diary_exchange_invitation_blocks_pkey
    primary key (blocker_user_id, blocked_inviter_user_id),
  constraint my_diary_exchange_invitation_blocks_blocker_user_id_fkey
    foreign key (blocker_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_invitation_blocks_blocked_user_id_fkey
    foreign key (blocked_inviter_user_id)
    references public.accounts (user_id)
    on delete cascade,
  constraint my_diary_exchange_invitation_blocks_not_self_check
    check (blocker_user_id <> blocked_inviter_user_id)
);

alter table public.exchange_diaries owner to postgres;
alter table public.exchange_diary_participants owner to postgres;
alter table public.exchange_invitations owner to postgres;
alter table my_diary_private.my_diary_exchange_pair_locks owner to postgres;
alter table public.exchange_invitation_blocks owner to postgres;

create function my_diary_private.my_diary_reject_exchange_diary_reactivation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if old.state = 'archived' and new.state <> 'archived' then
    raise exception using
      errcode = '23514',
      message = 'Archived exchange diaries cannot be reactivated.';
  end if;

  return new;
end;
$function$;

create function my_diary_private.my_diary_enforce_exchange_diary_exact_two()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target_diary_id uuid;
  target_diary_ids uuid[];
  participant_count integer;
  position_one_count integer;
  position_two_count integer;
begin
  if tg_table_name = 'exchange_diaries' then
    target_diary_ids := array[
      (pg_catalog.to_jsonb(new) ->> 'id')::uuid
    ];
  elsif tg_op = 'INSERT' then
    target_diary_ids := array[
      (pg_catalog.to_jsonb(new) ->> 'diary_id')::uuid
    ];
  elsif tg_op = 'DELETE' then
    target_diary_ids := array[
      (pg_catalog.to_jsonb(old) ->> 'diary_id')::uuid
    ];
  else
    target_diary_ids := array[
      (pg_catalog.to_jsonb(old) ->> 'diary_id')::uuid,
      (pg_catalog.to_jsonb(new) ->> 'diary_id')::uuid
    ];
  end if;

  for target_diary_id in
    select distinct candidate.diary_id
    from pg_catalog.unnest(target_diary_ids) as candidate(diary_id)
    where candidate.diary_id is not null
  loop
    if exists (
      select 1
      from public.exchange_diaries
      where id = target_diary_id
    ) then
      select
        pg_catalog.count(*),
        pg_catalog.count(*) filter (where position = 1),
        pg_catalog.count(*) filter (where position = 2)
      into participant_count, position_one_count, position_two_count
      from public.exchange_diary_participants
      where diary_id = target_diary_id;

      if participant_count <> 2
         or position_one_count <> 1
         or position_two_count <> 1 then
        raise exception using
          errcode = '23514',
          message = 'An exchange diary must have exactly two participant rows.';
      end if;
    end if;
  end loop;

  return null;
end;
$function$;

create function my_diary_private.my_diary_enforce_exchange_invitation_transition()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.status <> old.status and old.status <> 'pending' then
    raise exception using
      errcode = '23514',
      message = 'A terminal exchange invitation cannot change state.';
  end if;

  return new;
end;
$function$;

create function my_diary_private.my_diary_can_view_exchange_diary(
  target_diary_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.exchange_diaries as diary
    join public.exchange_diary_participants as viewer_participant
      on viewer_participant.diary_id = diary.id
     and viewer_participant.user_id = auth.uid()
    join public.accounts as viewer_account
      on viewer_account.user_id = viewer_participant.user_id
     and viewer_account.status = 'active'
    where diary.id = target_diary_id
      and (
        (
          diary.state = 'active'
          and (
            select pg_catalog.count(*)
            from public.exchange_diary_participants as participant
            where participant.diary_id = diary.id
          ) = 2
          and not exists (
            select 1
            from public.exchange_diary_participants as participant
            left join public.accounts as participant_account
              on participant_account.user_id = participant.user_id
            where participant.diary_id = diary.id
              and (
                participant.user_id is null
                or participant_account.user_id is null
                or participant_account.status <> 'active'
              )
          )
        )
        or (
          diary.state = 'archived'
          and (
            select pg_catalog.count(*)
            from public.exchange_diary_participants as participant
            where participant.diary_id = diary.id
          ) = 2
          and not exists (
            select 1
            from public.exchange_diary_participants as participant
            left join public.accounts as participant_account
              on participant_account.user_id = participant.user_id
            where participant.diary_id = diary.id
              and participant.user_id is not null
              and (
                participant_account.user_id is null
                or participant_account.status not in ('active', 'deactivated')
              )
          )
        )
      )
  );
$function$;

alter function my_diary_private.my_diary_reject_exchange_diary_reactivation()
  owner to postgres;
alter function my_diary_private.my_diary_enforce_exchange_diary_exact_two()
  owner to postgres;
alter function my_diary_private.my_diary_enforce_exchange_invitation_transition()
  owner to postgres;
alter function my_diary_private.my_diary_can_view_exchange_diary(uuid)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_reject_exchange_diary_reactivation()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_enforce_exchange_diary_exact_two()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_enforce_exchange_invitation_transition()
  from public, anon, authenticated, service_role, authenticator;
revoke all on function
  my_diary_private.my_diary_can_view_exchange_diary(uuid)
  from public, anon, authenticated, service_role, authenticator;
grant execute on function
  my_diary_private.my_diary_can_view_exchange_diary(uuid)
  to authenticated;

create trigger my_diary_exchange_diaries_set_updated_at
before update on public.exchange_diaries
for each row execute function public.my_diary_set_updated_at();

create trigger my_diary_exchange_diaries_reject_reactivation
before update of state on public.exchange_diaries
for each row execute function
  my_diary_private.my_diary_reject_exchange_diary_reactivation();

create constraint trigger my_diary_exchange_diaries_exact_two
after insert on public.exchange_diaries
deferrable initially deferred
for each row execute function
  my_diary_private.my_diary_enforce_exchange_diary_exact_two();

create constraint trigger my_diary_exchange_diary_participants_exact_two
after insert or update or delete on public.exchange_diary_participants
deferrable initially deferred
for each row execute function
  my_diary_private.my_diary_enforce_exchange_diary_exact_two();

create trigger my_diary_exchange_invitations_state_transition
before update of status on public.exchange_invitations
for each row execute function
  my_diary_private.my_diary_enforce_exchange_invitation_transition();

alter table public.exchange_diaries enable row level security;
alter table public.exchange_diary_participants enable row level security;
alter table public.exchange_invitations enable row level security;
alter table public.exchange_invitation_blocks enable row level security;

revoke all on table public.exchange_diaries
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.exchange_diary_participants
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.exchange_invitations
  from public, anon, authenticated, service_role, authenticator;
revoke all on table public.exchange_invitation_blocks
  from public, anon, authenticated, service_role, authenticator;
revoke all on table my_diary_private.my_diary_exchange_pair_locks
  from public, anon, authenticated, service_role, authenticator;

grant select on table public.exchange_diaries to authenticated;
grant select on table public.exchange_diary_participants to authenticated;
grant select on table public.exchange_invitations to authenticated;
grant select on table public.exchange_invitation_blocks to authenticated;

create policy my_diary_exchange_diaries_select_participant
on public.exchange_diaries
for select
to authenticated
using (
  my_diary_private.my_diary_can_view_exchange_diary(exchange_diaries.id)
);

create policy my_diary_exchange_diary_participants_select_visible_diary
on public.exchange_diary_participants
for select
to authenticated
using (
  my_diary_private.my_diary_can_view_exchange_diary(
    exchange_diary_participants.diary_id
  )
);

create policy my_diary_exchange_invitations_select_pending_party
on public.exchange_invitations
for select
to authenticated
using (
  status = 'pending'
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and (select auth.uid()) in (inviter_user_id, invitee_user_id)
);

create policy my_diary_exchange_invitation_blocks_select_blocker
on public.exchange_invitation_blocks
for select
to authenticated
using (
  blocker_user_id = (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
);

do $postcondition$
declare
  function_count integer;
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) <> 4 then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: public table ownership or RLS differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'my_diary_private'
      and relation.relname = 'my_diary_exchange_pair_locks'
      and relation.relkind = 'r'
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: pair lock table differs';
  end if;

  if (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.exchange_diaries'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'id:uuid:t',
    'title:text:f',
    'state:text:t',
    'created_by_position:smallint:t',
    'started_at:timestamp with time zone:t',
    'archived_at:timestamp with time zone:f',
    'archive_cause:text:f',
    'created_at:timestamp with time zone:t',
    'updated_at:timestamp with time zone:t'
  ]::text[] then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: exchange diary columns differ';
  end if;

  if (
    select array_agg(
      pg_catalog.format(
        '%s:%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull,
        attribute.attgenerated
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.exchange_invitations'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'id:uuid:t:',
    'inviter_user_id:uuid:t:',
    'invitee_user_id:uuid:t:',
    'pair_low_user_id:uuid:f:s',
    'pair_high_user_id:uuid:f:s',
    'status:text:t:',
    'diary_id:uuid:f:',
    'created_at:timestamp with time zone:t:',
    'processed_at:timestamp with time zone:f:'
  ]::text[] then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: invitation columns differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where (
      conrelid = 'public.exchange_diaries'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_diaries_pkey',
        'my_diary_exchange_diaries_title_check',
        'my_diary_exchange_diaries_state_check',
        'my_diary_exchange_diaries_created_by_position_check',
        'my_diary_exchange_diaries_archive_shape_check'
      )
    ) or (
      conrelid = 'public.exchange_diary_participants'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_diary_participants_pkey',
        'my_diary_exchange_diary_participants_diary_id_fkey',
        'my_diary_exchange_diary_participants_user_id_fkey',
        'my_diary_exchange_diary_participants_position_check',
        'my_diary_exchange_diary_participants_diary_position_key',
        'my_diary_exchange_diary_participants_diary_id_id_key'
      )
    ) or (
      conrelid = 'public.exchange_invitations'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_invitations_pkey',
        'my_diary_exchange_invitations_inviter_user_id_fkey',
        'my_diary_exchange_invitations_invitee_user_id_fkey',
        'my_diary_exchange_invitations_diary_id_fkey',
        'my_diary_exchange_invitations_not_self_check',
        'my_diary_exchange_invitations_status_check',
        'my_diary_exchange_invitations_shape_check'
      )
    ) or (
      conrelid = 'my_diary_private.my_diary_exchange_pair_locks'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_pair_locks_pkey',
        'my_diary_exchange_pair_locks_low_user_id_fkey',
        'my_diary_exchange_pair_locks_high_user_id_fkey',
        'my_diary_exchange_pair_locks_canonical_check'
      )
    ) or (
      conrelid = 'public.exchange_invitation_blocks'::pg_catalog.regclass
      and conname in (
        'my_diary_exchange_invitation_blocks_pkey',
        'my_diary_exchange_invitation_blocks_blocker_user_id_fkey',
        'my_diary_exchange_invitation_blocks_blocked_user_id_fkey',
        'my_diary_exchange_invitation_blocks_not_self_check'
      )
    )
  ) <> 26 then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: table constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_diary_participants'::pg_catalog.regclass
      and conname = 'my_diary_exchange_diary_participants_user_id_fkey'
      and contype = 'f'
      and confrelid = 'public.accounts'::pg_catalog.regclass
      and confdeltype = 'n'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_diary_participants'::pg_catalog.regclass
      and conname = 'my_diary_exchange_diary_participants_diary_id_fkey'
      and contype = 'f'
      and confrelid = 'public.exchange_diaries'::pg_catalog.regclass
      and confdeltype = 'c'
  ) then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: participant foreign keys differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_diary_participants_diary_user_key'
      and indexdef like '%UNIQUE INDEX%'
      and indexdef like '%WHERE (user_id IS NOT NULL)%'
  ) or not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_invitations_pending_pair_key'
      and indexdef like '%UNIQUE INDEX%'
      and indexdef like '%WHERE (status = ''pending''::text)%'
  ) then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: partial unique indexes differ';
  end if;

  select pg_catalog.count(*)
  into function_count
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'my_diary_private'
    and (
      (
        function.proname in (
          'my_diary_reject_exchange_diary_reactivation',
          'my_diary_enforce_exchange_diary_exact_two',
          'my_diary_enforce_exchange_invitation_transition'
        )
        and function.proargtypes = ''::oidvector
        and function.prorettype = 'trigger'::pg_catalog.regtype
        and language.lanname = 'plpgsql'
        and function.provolatile = 'v'
      )
      or (
        function.proname = 'my_diary_can_view_exchange_diary'
        and function.proargtypes = '2950'::oidvector
        and function.prorettype = 'boolean'::pg_catalog.regtype
        and language.lanname = 'sql'
        and function.provolatile = 's'
      )
    )
    and function.prosecdef
    and function.proconfig = array['search_path=""']::text[]
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres';

  if function_count <> 4 then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: function attributes differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger
    where trigger.tgname in (
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two'
    )
      and trigger.tgdeferrable
      and trigger.tginitdeferred
      and not trigger.tgisinternal
  ) <> 2 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger
    where trigger.tgname in (
      'my_diary_exchange_diaries_set_updated_at',
      'my_diary_exchange_diaries_reject_reactivation',
      'my_diary_exchange_diaries_exact_two',
      'my_diary_exchange_diary_participants_exact_two',
      'my_diary_exchange_invitations_state_transition'
    )
      and not trigger.tgisinternal
  ) <> 5 then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: triggers differ';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 4 or (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'exchange_diaries',
        'exchange_diary_participants',
        'exchange_invitations',
        'exchange_invitation_blocks'
      )
  ) <> 4 then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: RLS policies differ';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array[
        'public.exchange_diaries',
        'public.exchange_diary_participants',
        'public.exchange_invitations',
        'public.exchange_invitation_blocks'
      ]
    ) as target(table_name)
    where not pg_catalog.has_table_privilege(
      'authenticated', target.table_name, 'SELECT'
    )
      or pg_catalog.has_table_privilege(
        'authenticated', target.table_name, 'INSERT, UPDATE, DELETE'
      )
      or pg_catalog.has_table_privilege(
        'anon', target.table_name, 'SELECT, INSERT, UPDATE, DELETE'
      )
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'my_diary_private.my_diary_exchange_pair_locks',
    'SELECT, INSERT, UPDATE, DELETE'
  ) then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: table ACL differs';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where namespace.nspname = 'my_diary_private'
      and function.proname in (
        'my_diary_reject_exchange_diary_reactivation',
        'my_diary_enforce_exchange_diary_exact_two',
        'my_diary_enforce_exchange_invitation_transition',
        'my_diary_can_view_exchange_diary'
      )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_can_view_exchange_diary(uuid)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon',
    'my_diary_private.my_diary_can_view_exchange_diary(uuid)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_enforce_exchange_diary_exact_two()',
    'EXECUTE'
  ) then
    raise exception
      'create_exchange_diary_state_foundation postcondition failed: function ACL differs';
  end if;
end;
$postcondition$;

commit;
