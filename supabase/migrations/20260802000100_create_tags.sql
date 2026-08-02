begin;

do $preflight$
begin
  if exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('tags', 'post_tags')
  ) then
    raise exception
      'create_tags preflight failed: tags or post_tags already exists';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'my_diary_private'
      and function.proname = 'my_diary_normalize_tag_name'
  ) then
    raise exception
      'create_tags preflight failed: tag normalizer already exists';
  end if;

  if to_regnamespace('my_diary_private') is null
     or to_regclass('public.posts') is null then
    raise exception
      'create_tags preflight failed: required core schema objects are missing';
  end if;

  if exists (
    select 1
    from unnest(
      array['postgres', 'anon', 'authenticated', 'service_role', 'authenticator']
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role
      where role.rolname = required.role_name
    )
  ) then
    raise exception
      'create_tags preflight failed: a required Supabase role is missing';
  end if;
end;
$preflight$;

create function my_diary_private.my_diary_normalize_tag_name(
  raw_name text
)
returns text
language sql
immutable
strict
parallel safe
security invoker
set search_path = ''
as $function$
  select pg_catalog.translate(
    pg_catalog.regexp_replace(
      pg_catalog.btrim(
        pg_catalog.regexp_replace(
          pg_catalog.btrim(pg_catalog.normalize(raw_name, 'NFKC')),
          '^#+',
          ''
        )
      ),
      ' +',
      ' ',
      'g'
    ),
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'abcdefghijklmnopqrstuvwxyz'
  );
$function$;

alter function my_diary_private.my_diary_normalize_tag_name(text)
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_normalize_tag_name(text)
  from public, anon, authenticated, service_role, authenticator;

create table public.tags (
  id uuid not null default gen_random_uuid(),
  name text not null,
  normalized_name text not null,
  created_at timestamptz not null default now(),
  constraint my_diary_tags_pkey primary key (id),
  constraint my_diary_tags_normalized_name_key unique (normalized_name),
  constraint my_diary_tags_name_normalized_match
    check (name = normalized_name),
  constraint my_diary_tags_canonical_check
    check (
      normalized_name =
        my_diary_private.my_diary_normalize_tag_name(normalized_name)
    ),
  constraint my_diary_tags_length_check
    check (char_length(normalized_name) between 1 and 30),
  constraint my_diary_tags_characters_check
    check (
      position(',' in normalized_name) = 0
      and position('#' in normalized_name) = 0
      and normalized_name !~ '[[:cntrl:]]'
    )
);

create table public.post_tags (
  post_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  constraint my_diary_post_tags_pkey primary key (post_id, tag_id),
  constraint my_diary_post_tags_post_id_fkey
    foreign key (post_id) references public.posts (id) on delete cascade,
  constraint my_diary_post_tags_tag_id_fkey
    foreign key (tag_id) references public.tags (id) on delete cascade
);

create index my_diary_post_tags_tag_post_idx
  on public.post_tags (tag_id, post_id);

alter table public.tags enable row level security;
alter table public.post_tags enable row level security;

revoke all on table public.tags from public, anon, authenticated;
revoke all on table public.post_tags from public, anon, authenticated;

grant select on table public.tags to authenticated;
grant select on table public.post_tags to authenticated;

create policy my_diary_post_tags_select_visible_post
on public.post_tags
for select
to authenticated
using (
  exists (
    select 1
    from public.posts
    where posts.id = post_tags.post_id
  )
);

create policy my_diary_tags_select_visible_post
on public.tags
for select
to authenticated
using (
  exists (
    select 1
    from public.post_tags
    where post_tags.tag_id = tags.id
  )
);

do $postcondition$
declare
  normalizer_oid oid;
begin
  select function.oid
  into normalizer_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'my_diary_private'
    and function.proname = 'my_diary_normalize_tag_name'
    and function.pronargs = 1
    and function.proargtypes = '25'::oidvector
    and function.prorettype = 'text'::pg_catalog.regtype
    and function.prokind = 'f'
    and language.lanname = 'sql'
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and not function.prosecdef
    and function.provolatile = 'i'
    and function.proisstrict
    and function.proparallel = 's'
    and function.proconfig = array['search_path=""']::text[]
    and not exists (
      select 1
      from pg_catalog.pg_depend as dependency
      where dependency.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
        and dependency.objid = function.oid
        and dependency.deptype = 'e'
    );

  if normalizer_oid is null then
    raise exception
      'create_tags postcondition failed: normalizer attributes differ';
  end if;

  if exists (
    select 1
    from pg_catalog.aclexplode(
      coalesce(
        (
          select function.proacl
          from pg_catalog.pg_proc as function
          where function.oid = normalizer_oid
        ),
        pg_catalog.acldefault(
          'f',
          (
            select function.proowner
            from pg_catalog.pg_proc as function
            where function.oid = normalizer_oid
          )
        )
      )
    ) as privilege
    where privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'create_tags postcondition failed: PUBLIC can execute normalizer';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', normalizer_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', normalizer_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', normalizer_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticator', normalizer_oid, 'EXECUTE'
     ) then
    raise exception
      'create_tags postcondition failed: an application role can execute normalizer';
  end if;

  if not pg_catalog.has_function_privilege(
    'postgres', normalizer_oid, 'EXECUTE'
  ) then
    raise exception
      'create_tags postcondition failed: postgres cannot execute normalizer';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'tags'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) or not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'post_tags'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) then
    raise exception
      'create_tags postcondition failed: table ownership or RLS differs';
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
    where attribute.attrelid = 'public.tags'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'id:uuid:t',
    'name:text:t',
    'normalized_name:text:t',
    'created_at:timestamp with time zone:t'
  ]::text[] then
    raise exception
      'create_tags postcondition failed: tags columns differ';
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
    where attribute.attrelid = 'public.post_tags'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'post_id:uuid:t',
    'tag_id:uuid:t',
    'created_at:timestamp with time zone:t'
  ]::text[] then
    raise exception
      'create_tags postcondition failed: post_tags columns differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.tags'::pg_catalog.regclass
      and conname = 'my_diary_tags_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.tags'::pg_catalog.regclass
      and conname = 'my_diary_tags_normalized_name_key'
      and contype = 'u'
  ) or (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.tags'::pg_catalog.regclass
      and conname in (
        'my_diary_tags_name_normalized_match',
        'my_diary_tags_canonical_check',
        'my_diary_tags_length_check',
        'my_diary_tags_characters_check'
      )
      and contype = 'c'
  ) <> 4 then
    raise exception
      'create_tags postcondition failed: tags constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_post_id_fkey'
      and confrelid = 'public.posts'::pg_catalog.regclass
      and confdeltype = 'c'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_tags'::pg_catalog.regclass
      and conname = 'my_diary_post_tags_tag_id_fkey'
      and confrelid = 'public.tags'::pg_catalog.regclass
      and confdeltype = 'c'
  ) then
    raise exception
      'create_tags postcondition failed: post_tags constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as index_relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = index_relation.relnamespace
    join pg_catalog.pg_index as index_definition
      on index_definition.indexrelid = index_relation.oid
    where namespace.nspname = 'public'
      and index_relation.relname = 'my_diary_post_tags_tag_post_idx'
      and index_definition.indrelid = 'public.post_tags'::pg_catalog.regclass
      and index_definition.indisvalid
      and index_definition.indisready
      and not index_definition.indisunique
      and index_definition.indpred is null
      and index_definition.indnkeyatts = 2
      and index_definition.indkey[0] = (
        select attnum
        from pg_catalog.pg_attribute
        where attrelid = 'public.post_tags'::pg_catalog.regclass
          and attname = 'tag_id'
      )
      and index_definition.indkey[1] = (
        select attnum
        from pg_catalog.pg_attribute
        where attrelid = 'public.post_tags'::pg_catalog.regclass
          and attname = 'post_id'
      )
  ) then
    raise exception
      'create_tags postcondition failed: reverse lookup index is missing';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'tags'
      and policyname = 'my_diary_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_tags'
      and policyname = 'my_diary_post_tags_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('tags', 'post_tags')
  ) <> 2 then
    raise exception
      'create_tags postcondition failed: RLS policies differ';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'INSERT, UPDATE, DELETE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege('anon', 'public.tags', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.post_tags', 'SELECT') then
    raise exception
      'create_tags postcondition failed: table privileges differ';
  end if;
end;
$postcondition$;

commit;
