begin;

create extension if not exists pgtap with schema extensions;

select plan(93);

-- Schema, constraints, indexes, RLS, ownership, triggers, and ACL.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.exchange_entries'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  11::bigint,
  'exchange_entries has exactly eleven columns'
);

select is(
  (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      ) order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.exchange_entries'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  '[
    ["id","uuid",true],
    ["diary_id","uuid",true],
    ["author_participant_id","uuid",true],
    ["title","text",false],
    ["body","text",false],
    ["mood","text",false],
    ["location_name","text",false],
    ["created_at","timestamp with time zone",true],
    ["updated_at","timestamp with time zone",true],
    ["deleted_at","timestamp with time zone",false],
    ["redaction_reason","text",false]
  ]'::jsonb,
  'exchange_entries columns and nullability are exact'
);

select is(
  (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      ) order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid =
      'public.exchange_entry_tags'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ),
  '[["entry_id","uuid",true],["tag_id","uuid",true],
    ["created_at","timestamp with time zone",true]]'::jsonb,
  'exchange_entry_tags columns are exact'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entries'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entries_author_diary_fkey'
      and pg_catalog.pg_get_constraintdef(oid) like
        'FOREIGN KEY (diary_id, author_participant_id)%exchange_diary_participants(diary_id, id)%'
  ),
  'entry author and diary use a composite foreign key'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_diary_participants'::pg_catalog.regclass
      and conname =
        'my_diary_exchange_diary_participants_diary_id_id_key'
      and contype = 'u'
  ),
  'the existing participant diary/id uniqueness is reused'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entries'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entries_redaction_shape_check'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entry_tags'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_tags_pkey'
  ),
  'redaction shape and entry-tag primary key constraints exist'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_entries_diary_created_id_idx'
      and indexdef like '%(diary_id, created_at, id)%'
      and indexdef not like '%WHERE%'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'my_diary_exchange_entry_tags_tag_entry_idx'
      and indexdef like '%(tag_id, entry_id)%'
  ),
  'stable timeline and reverse tag indexes exist'
);

select ok(
  (
    select relrowsecurity and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = 'public.exchange_entries'::pg_catalog.regclass
  )
  and (
    select relrowsecurity and not relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relowner) = 'postgres'
    from pg_catalog.pg_class
    where oid = 'public.exchange_entry_tags'::pg_catalog.regclass
  ),
  'both new tables are postgres-owned with explicit RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('exchange_entries', 'exchange_entry_tags')
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  2::bigint,
  'both new tables have authenticated participant SELECT policies'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entries', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entries', 'INSERT, UPDATE, DELETE'
  )
  and pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entry_tags', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entry_tags',
    'INSERT, UPDATE, DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'anon', 'public.exchange_entries', 'SELECT'
  ),
  'authenticated has SELECT only and anon has no table access'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgrelid = 'public.exchange_entries'::pg_catalog.regclass
      and not tgisinternal
      and tgname in (
        'my_diary_exchange_entries_reject_rewrite',
        'my_diary_exchange_entries_set_updated_at'
      )
  ),
  2::bigint,
  'entry rewrite protection and updated_at triggers exist'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.exchange_entry_tags'::pg_catalog.regclass
      and tgname = 'my_diary_exchange_entry_tags_reject_deleted_entry'
      and not tgisinternal
  ),
  'deleted entries reject new tag relations'
);

-- Exact public RPC signatures and hardening.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname in (
        'my_diary_create_exchange_entry',
        'my_diary_update_exchange_entry',
        'my_diary_soft_delete_exchange_entry',
        'my_diary_get_exchange_entry_tags'
      )
  ),
  4::bigint,
  'exactly four public exchange entry RPCs exist without overloads'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    join (
      values
        ('my_diary_create_exchange_entry',
         '2950 25 25 25 25 1009'::oidvector,
         array['p_diary_id','p_title','p_body','p_mood',
               'p_location_name','p_tags']::text[], 'uuid'::regtype, 'v'::char),
        ('my_diary_update_exchange_entry',
         '2950 25 25 25 25 1009'::oidvector,
         array['p_entry_id','p_title','p_body','p_mood',
               'p_location_name','p_tags']::text[], 'uuid'::regtype, 'v'::char),
        ('my_diary_soft_delete_exchange_entry',
         '2950'::oidvector, array['p_entry_id']::text[],
         'boolean'::regtype, 'v'::char),
        ('my_diary_get_exchange_entry_tags',
         '2951'::oidvector,
         array['p_entry_ids','entry_id','tag_id','name']::text[],
         'record'::regtype, 's'::char)
    ) as expected(name, args, arg_names, result_type, volatility)
      on expected.name = function_definition.proname
     and expected.args = function_definition.proargtypes
     and expected.arg_names = function_definition.proargnames
     and expected.result_type = function_definition.prorettype
     and expected.volatility = function_definition.provolatile
    where namespace.nspname = 'public'
      and function_definition.prosecdef
      and function_definition.proconfig = array['search_path=""']::text[]
      and function_definition.pronargdefaults = 0
      and pg_catalog.pg_get_userbyid(function_definition.proowner) = 'postgres'
  ),
  4::bigint,
  'all RPC arguments, return types, volatility, owner, security, and search_path are exact'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname =
        'my_diary_get_exchange_entry_tags'
      and function_definition.proallargtypes =
        array['uuid[]'::regtype, 'uuid'::regtype,
              'uuid'::regtype, 'text'::regtype]::oid[]
      and function_definition.proargmodes =
        array['i'::"char",'t'::"char",'t'::"char",'t'::"char"]
  ),
  'hydration TABLE output columns and types are exact'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_exchange_entry(uuid,text,text,text,text,text[])',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.my_diary_get_exchange_entry_tags(uuid[])', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticator',
    'public.my_diary_soft_delete_exchange_entry(uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_exchange_entry(uuid,text,text,text,text,text[])',
    'EXECUTE'
  ),
  'only authenticated receives exact public RPC EXECUTE'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_lock_exchange_diary_for_entry(uuid,uuid,boolean)',
    'EXECUTE'
  ),
  'the lock helper is not executable by application roles'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('tags', 'post_tags')
      and policyname in (
        'my_diary_tags_select_visible_post',
        'my_diary_post_tags_select_visible_post'
      )
  ),
  2::bigint,
  'existing tag RLS policies remain unchanged'
);

-- Account and diary fixtures.
insert into auth.users (id, email)
values
  ('a2400000-0000-4000-8000-000000000001', 'e2b-a@example.test'),
  ('b2400000-0000-4000-8000-000000000002', 'e2b-b@example.test'),
  ('c2400000-0000-4000-8000-000000000003', 'e2b-c@example.test'),
  ('d2400000-0000-4000-8000-000000000004', 'e2b-d@example.test'),
  ('e2400000-0000-4000-8000-000000000005', 'e2b-e@example.test');

insert into public.exchange_diaries (id, created_by_position)
values
  ('d2400000-0000-4000-8000-000000000001', 1),
  ('d2400000-0000-4000-8000-000000000002', 1),
  ('d2400000-0000-4000-8000-000000000003', 1),
  ('d2400000-0000-4000-8000-000000000004', 1),
  ('d2400000-0000-4000-8000-000000000005', 1);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('12400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000001', 1,
   'a2400000-0000-4000-8000-000000000001'),
  ('12400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000001', 2,
   'b2400000-0000-4000-8000-000000000002'),
  ('22400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000002', 1,
   'c2400000-0000-4000-8000-000000000003'),
  ('22400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000002', 2,
   'd2400000-0000-4000-8000-000000000004'),
  ('32400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000003', 1,
   'a2400000-0000-4000-8000-000000000001'),
  ('32400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000003', 2,
   'b2400000-0000-4000-8000-000000000002'),
  ('42400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000004', 1,
   'a2400000-0000-4000-8000-000000000001'),
  ('42400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000004', 2,
   'b2400000-0000-4000-8000-000000000002'),
  ('52400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000005', 1,
   'a2400000-0000-4000-8000-000000000001'),
  ('52400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000005', 2,
   'b2400000-0000-4000-8000-000000000002');

select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- Create and active validation boundaries.
select set_config(
  'my_diary.e2b_primary_entry',
  public.my_diary_create_exchange_entry(
    'd2400000-0000-4000-8000-000000000001',
    '  first  ', '  body  ', 'happy', '  Tokyo  ',
    array[' Exchange Secret ', '#Ｅｘｃｈａｎｇｅ   Secret', 'Beta']
  )::text,
  true
);

select ok(
  current_setting('my_diary.e2b_primary_entry')::uuid is not null,
  'participant 1 creates an entry'
);

reset role;
select results_eq(
  $$select title, body, mood, location_name,
           author_participant_id, deleted_at, redaction_reason
    from public.exchange_entries
    where id = current_setting('my_diary.e2b_primary_entry')::uuid$$,
  $$values (
      'first'::text, 'body'::text, 'happy'::text, 'Tokyo'::text,
      '12400000-0000-4000-8000-000000000001'::uuid,
      null::timestamptz, null::text
    )$$,
  'create trims values and derives the author participant in DB'
);

select set_config(
  'request.jwt.claim.sub',
  'b2400000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'participant two', null, null, null
    )$$,
  'participant 2 creates an entry'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e2400000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'third party', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a third party receives the generic unavailable error'
);

reset role;
update public.accounts set status = 'deactivated'
where user_id = 'e2400000-0000-4000-8000-000000000005';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'deactivated viewer', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a deactivated viewer cannot create an entry'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'e2400000-0000-4000-8000-000000000005';
update public.accounts set status = 'suspended'
where user_id = 'b2400000-0000-4000-8000-000000000002';
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
set local role authenticated;

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'suspended counterpart', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'create fails while the other participant is suspended'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2b_primary_entry')::uuid,
      null, 'suspended counterpart', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'update fails while the other participant is suspended'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2400000-0000-4000-8000-000000000002';
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      'x', 'x', null, null, array[]::text[]
    )$$,
  'title 1, body 1, empty tags, and NULL optionals are accepted'
);

select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      repeat('題', 120), repeat('本', 10000), 'neutral',
      repeat('場', 100), null
    )$$,
  'Unicode title 120, body 10000, and location 100 are accepted'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      repeat('題', 121), 'body', null, null, null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'title 121 codepoints is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, '', null, null, null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'empty body is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, E' \t\n ', null, null, null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'whitespace-only body is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, repeat('本', 10001), null, null, null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'body 10001 codepoints is rejected'
);

select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'moods', mood_name, null, null
    )
    from unnest(array[
      'happy','sad','tired','irritated','calm','neutral'
    ]) as moods(mood_name)$$,
  'all six existing mood values are accepted'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'bad mood', 'excited', null, null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'an unknown mood is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'location', null, repeat('場', 101), null
    )$$,
  '22023', 'Invalid exchange entry input.',
  'location 101 codepoints is rejected'
);

-- Tag canonicalization, input bounds, and shared master.
select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entry_tags
    where entry_id = current_setting('my_diary.e2b_primary_entry')::uuid
  ),
  2::bigint,
  'canonical duplicate tags collapse and one additional tag remains'
);

reset role;
select results_eq(
  $$select tag.normalized_name
    from public.exchange_entry_tags as entry_tag
    join public.tags as tag on tag.id = entry_tag.tag_id
    where entry_tag.entry_id =
      current_setting('my_diary.e2b_primary_entry')::uuid
    order by tag.normalized_name$$,
  $$values ('beta'::text), ('exchange secret'::text)$$,
  'NFKC, leading hash, spaces, and ASCII case use existing canonicalization'
);

set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'five tags', null, null,
      array['one','two','three','four','five']
    )$$,
  'five distinct canonical tags are accepted'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'six tags', null, null,
      array['one','two','three','four','five','six']
    )$$,
  '22023', 'Invalid tag input.',
  'six distinct canonical tags are rejected'
);

select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'raw twenty', null, null,
      array_fill('same'::text, array[20])
    )$$,
  'raw tag maximum twenty is accepted when canonical distinct is one'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'raw twenty one', null, null,
      array_fill('same'::text, array[21])
    )$$,
  '22023', 'Invalid tag input.',
  'raw tag count twenty one is rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'null tag', null, null, array['valid', null]
    )$$,
  '22023', 'Invalid tag input.',
  'NULL tag elements are rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'multidimensional tags', null, null,
      array[array['one','two'],array['three','four']]
    )$$,
  '22023', 'Invalid tag input.',
  'multidimensional tag arrays are rejected'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'invalid tag', null, null, array['bad,tag']
    )$$,
  '22023', 'Invalid tag input.',
  'invalid canonical tag characters are rejected'
);

-- Update ownership and NULL/empty/differential tag semantics.
create temporary table e2b_tag_snapshot as
select entry_tag.tag_id, entry_tag.created_at
from public.exchange_entry_tags as entry_tag
where entry_tag.entry_id =
  current_setting('my_diary.e2b_primary_entry')::uuid;

select is(
  public.my_diary_update_exchange_entry(
    current_setting('my_diary.e2b_primary_entry')::uuid,
    'updated', 'updated body', 'calm', 'Kyoto', null
  ),
  current_setting('my_diary.e2b_primary_entry')::uuid,
  'the author updates their active entry'
);

reset role;
select results_eq(
  $$select entry_tag.tag_id, entry_tag.created_at
    from public.exchange_entry_tags as entry_tag
    where entry_tag.entry_id =
      current_setting('my_diary.e2b_primary_entry')::uuid
    order by entry_tag.tag_id$$,
  $$select tag_id, created_at from e2b_tag_snapshot order by tag_id$$,
  'NULL tags preserve the complete relation snapshot'
);

set local role authenticated;
select is(
  public.my_diary_update_exchange_entry(
    current_setting('my_diary.e2b_primary_entry')::uuid,
    null, 'no tags', null, null, array[]::text[]
  ),
  current_setting('my_diary.e2b_primary_entry')::uuid,
  'empty tags update succeeds'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entry_tags
    where entry_id = current_setting('my_diary.e2b_primary_entry')::uuid
  ),
  0::bigint,
  'empty tags remove all relations'
);

set local role authenticated;
select is(
  public.my_diary_update_exchange_entry(
    current_setting('my_diary.e2b_primary_entry')::uuid,
    null, 'differential one', null, null, array['beta','gamma']
  ),
  current_setting('my_diary.e2b_primary_entry')::uuid,
  'nonempty tags establish a desired set'
);

reset role;
create temporary table e2b_beta_snapshot as
select entry_tag.created_at
from public.exchange_entry_tags as entry_tag
join public.tags as tag on tag.id = entry_tag.tag_id
where entry_tag.entry_id =
  current_setting('my_diary.e2b_primary_entry')::uuid
  and tag.normalized_name = 'beta';

set local role authenticated;
select is(
  public.my_diary_update_exchange_entry(
    current_setting('my_diary.e2b_primary_entry')::uuid,
    null, 'differential two', null, null, array['beta','delta']
  ),
  current_setting('my_diary.e2b_primary_entry')::uuid,
  'a second nonempty update applies a differential set'
);

reset role;
select results_eq(
  $$select entry_tag.created_at
    from public.exchange_entry_tags as entry_tag
    join public.tags as tag on tag.id = entry_tag.tag_id
    where entry_tag.entry_id =
      current_setting('my_diary.e2b_primary_entry')::uuid
      and tag.normalized_name = 'beta'$$,
  $$select created_at from e2b_beta_snapshot$$,
  'unchanged tag relations preserve created_at'
);

select set_config(
  'request.jwt.claim.sub',
  'b2400000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2b_primary_entry')::uuid,
      null, 'other edit', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'the other participant cannot edit the author entry'
);

-- RLS and participant/account status boundaries.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select ok(
  exists (
    select 1 from public.exchange_entries
    where id = current_setting('my_diary.e2b_primary_entry')::uuid
  )
  and exists (
    select 1 from public.exchange_entry_tags
    where entry_id = current_setting('my_diary.e2b_primary_entry')::uuid
  ),
  'an active participant reads entries and entry tags'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e2400000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*) from public.exchange_entries
    where diary_id = 'd2400000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'a third party sees no entries'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'b2400000-0000-4000-8000-000000000002';
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*) from public.exchange_entries
    where diary_id = 'd2400000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'one suspended active participant closes entry RLS for both'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'blocked', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'create fails while the other participant is suspended'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2b_primary_entry')::uuid,
      null, 'blocked update', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'update fails while the other participant is suspended'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2400000-0000-4000-8000-000000000002';
delete from public.follows
where follower_id in (
  'a2400000-0000-4000-8000-000000000001',
  'b2400000-0000-4000-8000-000000000002'
)
and following_id in (
  'a2400000-0000-4000-8000-000000000001',
  'b2400000-0000-4000-8000-000000000002'
);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000001',
      null, 'follow independent', null, null, null
    )$$,
  'active diary entry creation does not depend on follows'
);

-- Hydration, privacy, batch validation, and existence-oracle resistance.
select set_config(
  'my_diary.e2b_hydration_entry',
  public.my_diary_create_exchange_entry(
    'd2400000-0000-4000-8000-000000000001',
    null, 'hydration', null, null, array['exchange-only-private']
  )::text,
  true
);

select results_eq(
  $$select name
    from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_hydration_entry')::uuid
    ])$$,
  $$values ('exchange-only-private'::text)$$,
  'participant hydration returns an exchange-only tag'
);

select is(
  (
    select pg_catalog.count(*)
    from public.tags
    where normalized_name = 'exchange-only-private'
  ),
  0::bigint,
  'exchange-only tag does not leak through existing tags SELECT RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_search_tags('exchange-only-private', null)
  ),
  0::bigint,
  'exchange-only tag does not leak through existing tag search RPC'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2400000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_hydration_entry')::uuid,
      'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
    ])
  ),
  0::bigint,
  'third-party and nonexistent IDs are silently omitted by hydration'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_hydration_entry')::uuid,
      'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
    ])
  ),
  1::bigint,
  'mixed visible and nonexistent hydration returns only visible tags'
);

select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_primary_entry')::uuid,
      current_setting('my_diary.e2b_hydration_entry')::uuid
    ])
  ),
  3::bigint,
  'hydration returns tags for multiple visible entries in one batch'
);

select throws_ok(
  $$select * from public.my_diary_get_exchange_entry_tags(
      array_fill(
        'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
        array[51]
      )
    )$$,
  '22023', 'Invalid exchange entry batch input.',
  'hydration rejects arrays larger than fifty'
);

select throws_ok(
  $$select * from public.my_diary_get_exchange_entry_tags(
      array['ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid, null]
    )$$,
  '22023', 'Invalid exchange entry batch input.',
  'hydration rejects NULL elements'
);

select throws_ok(
  $$select * from public.my_diary_get_exchange_entry_tags(
      array[
        array['ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid],
        array['eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid]
      ]
    )$$,
  '22023', 'Invalid exchange entry batch input.',
  'hydration rejects multidimensional arrays'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'a2400000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  $$select * from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_hydration_entry')::uuid
    ])$$,
  '42501', 'Exchange entry operation is unavailable.',
  'hydration rejects a suspended viewer without returning tag names'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'a2400000-0000-4000-8000-000000000001';
set local role authenticated;

-- Reusing the same tag master from a normal post makes it visible normally.
reset role;
insert into public.posts (
  id, user_id, body, visibility
)
values (
  'f2400000-0000-4000-8000-000000000001',
  'a2400000-0000-4000-8000-000000000001',
  'normal post sharing an exchange tag', 'public'
);
insert into public.post_tags (post_id, tag_id)
select
  'f2400000-0000-4000-8000-000000000001', tag.id
from public.tags as tag
where tag.normalized_name = 'exchange-only-private';

set local role authenticated;
select is(
  (
    select pg_catalog.count(*) from public.tags
    where normalized_name = 'exchange-only-private'
  ),
  1::bigint,
  'the shared master becomes visible when a normal visible post uses it'
);

select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_search_tags('exchange-only-private', null)
  ),
  1::bigint,
  'existing tag search sees the master only through normal post RLS'
);

-- Atomic irreversible soft delete and deleted-entry operation closure.
select set_config(
  'my_diary.e2b_delete_entry',
  public.my_diary_create_exchange_entry(
    'd2400000-0000-4000-8000-000000000003',
    'delete me', 'sensitive body', 'sad', 'Secret',
    array['redact-me']
  )::text,
  true
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2400000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      current_setting('my_diary.e2b_delete_entry')::uuid
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'the other participant cannot delete the author entry'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'e2400000-0000-4000-8000-000000000005', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      current_setting('my_diary.e2b_delete_entry')::uuid
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a third party cannot delete an entry'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
create temporary table e2b_delete_identity as
select diary_id, author_participant_id, created_at
from public.exchange_entries
where id = current_setting('my_diary.e2b_delete_entry')::uuid;

set local role authenticated;
select is(
  public.my_diary_soft_delete_exchange_entry(
    current_setting('my_diary.e2b_delete_entry')::uuid
  ),
  true,
  'the author soft deletes an active entry'
);

reset role;
select ok(
  exists (
    select 1
    from public.exchange_entries as entry
    where entry.id = current_setting('my_diary.e2b_delete_entry')::uuid
      and entry.title is null
      and entry.body is null
      and entry.mood is null
      and entry.location_name is null
      and entry.deleted_at is not null
      and entry.redaction_reason = 'user_deleted'
  ),
  'soft delete leaves a row with all sensitive content irreversibly redacted'
);

select results_eq(
  $$select diary_id, author_participant_id, created_at
    from public.exchange_entries
    where id = current_setting('my_diary.e2b_delete_entry')::uuid$$,
  $$select diary_id, author_participant_id, created_at
    from e2b_delete_identity$$,
  'soft delete preserves diary, author participant, and created_at'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entry_tags
    where entry_id = current_setting('my_diary.e2b_delete_entry')::uuid
  ),
  0::bigint,
  'soft delete atomically removes all entry-tag relations'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      current_setting('my_diary.e2b_delete_entry')::uuid
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a deleted entry cannot be soft deleted again'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2b_delete_entry')::uuid,
      null, 'restore', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a deleted entry cannot be edited'
);

reset role;
select throws_ok(
  $$update public.exchange_entries
    set deleted_at = null, redaction_reason = null, body = 'restore'
    where id = current_setting('my_diary.e2b_delete_entry')::uuid$$,
  '23514', 'A redacted exchange entry cannot be changed.',
  'the trigger rejects undelete and content restoration even for direct SQL'
);

select throws_ok(
  $$insert into public.exchange_entry_tags (entry_id, tag_id)
    select current_setting('my_diary.e2b_delete_entry')::uuid, tag.id
    from public.tags as tag where tag.normalized_name = 'redact-me'$$,
  '23514', 'A redacted exchange entry cannot have tags.',
  'a deleted entry cannot receive tag relations'
);

set local role authenticated;
select is(
  (
    select pg_catalog.count(*)
    from public.my_diary_get_exchange_entry_tags(array[
      current_setting('my_diary.e2b_delete_entry')::uuid
    ])
  ),
  0::bigint,
  'deleted entry hydration returns zero tags'
);

-- Archived delete boundaries: active, deactivated, tombstone allowed; suspended denied.
select set_config(
  'request.jwt.claim.sub',
  'a2400000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select set_config(
  'my_diary.e2b_archived_entry',
  public.my_diary_create_exchange_entry(
    'd2400000-0000-4000-8000-000000000004',
    null, 'archive then delete', null, null, null
  )::text,
  true
);
select is(
  public.my_diary_archive_exchange_diary(
    'd2400000-0000-4000-8000-000000000004'
  ),
  'd2400000-0000-4000-8000-000000000004'::uuid,
  'existing archive RPC archives the diary before entry deletion'
);
select throws_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2400000-0000-4000-8000-000000000004',
      null, 'archived create', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'an archived diary rejects new entries'
);
select throws_ok(
  $$select public.my_diary_update_exchange_entry(
      current_setting('my_diary.e2b_archived_entry')::uuid,
      null, 'archived edit', null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'an archived diary rejects entry edits'
);
select is(
  public.my_diary_soft_delete_exchange_entry(
    current_setting('my_diary.e2b_archived_entry')::uuid
  ),
  true,
  'the author can delete from an archived diary with active counterpart'
);

reset role;
update public.exchange_diaries
set state = 'archived', archived_at = now(),
    archive_cause = 'ended_by_participant'
where id = 'd2400000-0000-4000-8000-000000000005';
insert into public.exchange_entries (
  id, diary_id, author_participant_id, body
)
values (
  'e2400000-0000-4000-8000-000000000005',
  'd2400000-0000-4000-8000-000000000005',
  '52400000-0000-4000-8000-000000000001', 'deactivated counterpart'
);
update public.accounts set status = 'deactivated'
where user_id = 'b2400000-0000-4000-8000-000000000002';
set local role authenticated;
select is(
  public.my_diary_soft_delete_exchange_entry(
    'e2400000-0000-4000-8000-000000000005'
  ),
  true,
  'archived delete allows a deactivated counterpart'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entries
    where diary_id = 'd2400000-0000-4000-8000-000000000005'
  ),
  1::bigint,
  'active viewer retains archived entry visibility with deactivated counterpart'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2400000-0000-4000-8000-000000000002';
insert into public.exchange_diaries (
  id, created_by_position, state, archived_at, archive_cause
)
values (
  'd2400000-0000-4000-8000-000000000006', 1,
  'archived', now(), 'account_deleted'
);
insert into public.exchange_diary_participants
  (id, diary_id, position, user_id, account_deleted_at)
values
  ('62400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000006', 1,
   'a2400000-0000-4000-8000-000000000001', null),
  ('62400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000006', 2, null, now());
insert into public.exchange_entries (
  id, diary_id, author_participant_id, body
)
values (
  'e2400000-0000-4000-8000-000000000006',
  'd2400000-0000-4000-8000-000000000006',
  '62400000-0000-4000-8000-000000000001', 'tombstone counterpart'
);
set local role authenticated;
select is(
  public.my_diary_soft_delete_exchange_entry(
    'e2400000-0000-4000-8000-000000000006'
  ),
  true,
  'archived delete allows an account tombstone counterpart'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entries
    where diary_id = 'd2400000-0000-4000-8000-000000000006'
  ),
  1::bigint,
  'active viewer retains archived entry visibility with tombstone counterpart'
);

reset role;
insert into public.exchange_diaries (
  id, created_by_position, state, archived_at, archive_cause
)
values (
  'd2400000-0000-4000-8000-000000000007', 1,
  'archived', now(), 'ended_by_participant'
);
insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('72400000-0000-4000-8000-000000000001',
   'd2400000-0000-4000-8000-000000000007', 1,
   'a2400000-0000-4000-8000-000000000001'),
  ('72400000-0000-4000-8000-000000000002',
   'd2400000-0000-4000-8000-000000000007', 2,
   'b2400000-0000-4000-8000-000000000002');
insert into public.exchange_entries (
  id, diary_id, author_participant_id, body
)
values (
  'e2400000-0000-4000-8000-000000000007',
  'd2400000-0000-4000-8000-000000000007',
  '72400000-0000-4000-8000-000000000001', 'suspended counterpart'
);
update public.accounts set status = 'suspended'
where user_id = 'b2400000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      'e2400000-0000-4000-8000-000000000007'
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'archived delete rejects a suspended counterpart'
);

select is(
  (
    select pg_catalog.count(*)
    from public.exchange_entries
    where diary_id = 'd2400000-0000-4000-8000-000000000007'
  ),
  0::bigint,
  'archived suspended diary is hidden by participant-only RLS'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2400000-0000-4000-8000-000000000002';

-- Direct table shape checks reject malformed active/deleted rows.
select throws_ok(
  $$insert into public.exchange_entries (
      diary_id, author_participant_id, title, body
    ) values (
      'd2400000-0000-4000-8000-000000000001',
      '12400000-0000-4000-8000-000000000001', E'\tbad', 'body'
    )$$,
  '23514', null,
  'DB CHECK rejects untrimmed active title independently of RPC'
);

select throws_ok(
  $$insert into public.exchange_entries (
      diary_id, author_participant_id, body,
      deleted_at, redaction_reason
    ) values (
      'd2400000-0000-4000-8000-000000000001',
      '12400000-0000-4000-8000-000000000001', 'leaked body',
      now(), 'user_deleted'
    )$$,
  '23514', null,
  'DB CHECK forbids content remaining in a deleted row'
);

select throws_ok(
  $$insert into public.exchange_entries (
      diary_id, author_participant_id, body
    ) values (
      'd2400000-0000-4000-8000-000000000002',
      '12400000-0000-4000-8000-000000000001', 'wrong diary author'
    )$$,
  '23503', null,
  'composite FK rejects an author participant from another diary'
);

reset role;

select * from finish();

rollback;
