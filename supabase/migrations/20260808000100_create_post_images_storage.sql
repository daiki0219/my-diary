begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('storage.buckets') is null
     or pg_catalog.to_regclass('storage.objects') is null then
    raise exception
      'create_post_images_storage preflight failed: required objects are missing';
  end if;

  if pg_catalog.to_regclass('public.post_images') is not null then
    raise exception
      'create_post_images_storage preflight failed: post_images already exists';
  end if;

  if exists (
    select 1
    from storage.buckets
    where id = 'post-images'
       or name = 'post-images'
  ) then
    raise exception
      'create_post_images_storage preflight failed: post-images bucket collides';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'my_diary_post_images_storage_select_visible_post',
        'my_diary_post_images_storage_guard_authenticated',
        'my_diary_post_images_storage_guard_anon'
      )
  ) then
    raise exception
      'create_post_images_storage preflight failed: Storage policy collides';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(
      array[
        'postgres',
        'anon',
        'authenticated',
        'service_role',
        'authenticator',
        'supabase_storage_admin'
      ]
    ) as required(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role
      where role.rolname = required.role_name
    )
  ) then
    raise exception
      'create_post_images_storage preflight failed: a required role is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'buckets'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) or not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'create_post_images_storage preflight failed: Storage ownership or RLS differs';
  end if;
end;
$preflight$;

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', false);

create table public.post_images (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  storage_path text not null,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  constraint my_diary_post_images_pkey primary key (id),
  constraint my_diary_post_images_post_id_fkey
    foreign key (post_id) references public.posts (id) on delete cascade,
  constraint my_diary_post_images_post_sort_key
    unique (post_id, sort_order) deferrable initially immediate,
  constraint my_diary_post_images_storage_path_key unique (storage_path),
  constraint my_diary_post_images_sort_order_check
    check (sort_order between 0 and 9),
  constraint my_diary_post_images_storage_path_length_check
    check (char_length(storage_path) between 1 and 1024)
);

alter table public.post_images enable row level security;

revoke all on table public.post_images
  from public, anon, authenticated, service_role, authenticator;
grant select on table public.post_images to authenticated;

create policy my_diary_post_images_select_visible_post
on public.post_images
for select
to authenticated
using (
  exists (
    select 1
    from public.posts
    where posts.id = post_images.post_id
  )
);

create policy my_diary_post_images_storage_select_visible_post
on storage.objects
for select
to authenticated
using (
  bucket_id = 'post-images'
  and exists (
    select 1
    from public.post_images
    where post_images.storage_path = objects.name
  )
);

create policy my_diary_post_images_storage_guard_authenticated
on storage.objects
as restrictive
for select
to authenticated
using (
  bucket_id <> 'post-images'
  or exists (
    select 1
    from public.post_images
    where post_images.storage_path = objects.name
  )
);

create policy my_diary_post_images_storage_guard_anon
on storage.objects
as restrictive
for select
to anon
using (bucket_id <> 'post-images');

do $postcondition$
begin
  if (
    select count(*)
    from storage.buckets
    where id = 'post-images'
      and name = 'post-images'
      and public is false
  ) <> 1 then
    raise exception
      'create_post_images_storage postcondition failed: bucket differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'post_images'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and not relation.relforcerowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) = 'postgres'
  ) then
    raise exception
      'create_post_images_storage postcondition failed: table ownership or RLS differs';
  end if;

  if (
    select pg_catalog.array_agg(
      pg_catalog.format(
        '%s:%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        attribute.attnotnull
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'public.post_images'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) <> array[
    'id:uuid:t',
    'post_id:uuid:t',
    'storage_path:text:t',
    'sort_order:integer:t',
    'created_at:timestamp with time zone:t'
  ]::text[] then
    raise exception
      'create_post_images_storage postcondition failed: columns differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_pkey'
      and contype = 'p'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_post_id_fkey'
      and contype = 'f'
      and confrelid = 'public.posts'::pg_catalog.regclass
      and confdeltype = 'c'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_post_sort_key'
      and contype = 'u'
      and condeferrable
      and not condeferred
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname = 'my_diary_post_images_storage_path_key'
      and contype = 'u'
      and not condeferrable
  ) or (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.post_images'::pg_catalog.regclass
      and conname in (
        'my_diary_post_images_sort_order_check',
        'my_diary_post_images_storage_path_length_check'
      )
      and contype = 'c'
  ) <> 2 then
    raise exception
      'create_post_images_storage postcondition failed: constraints differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    where index_definition.indexrelid =
        'public.my_diary_post_images_post_sort_key'::pg_catalog.regclass
      and index_definition.indrelid =
        'public.post_images'::pg_catalog.regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indisready
      and index_definition.indpred is null
  ) or not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    where index_definition.indexrelid =
        'public.my_diary_post_images_storage_path_key'::pg_catalog.regclass
      and index_definition.indrelid =
        'public.post_images'::pg_catalog.regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indisready
      and index_definition.indpred is null
  ) then
    raise exception
      'create_post_images_storage postcondition failed: indexes differ';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_images'
      and policyname = 'my_diary_post_images_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'post_images'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_post_images_storage_select_visible_post'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'PERMISSIVE'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname =
        'my_diary_post_images_storage_guard_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and permissive = 'RESTRICTIVE'
  ) <> 1 or (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'my_diary_post_images_storage_guard_anon'
      and cmd = 'SELECT'
      and roles = array['anon']::name[]
      and permissive = 'RESTRICTIVE'
  ) <> 1 or exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'my_diary_post_images_storage_%'
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception
      'create_post_images_storage postcondition failed: RLS policies differ';
  end if;

  if not pg_catalog.has_table_privilege(
       'authenticated', 'public.post_images', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.post_images', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'public.post_images', 'SELECT, INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'service_role',
       'public.post_images',
       'SELECT, INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticator',
       'public.post_images',
       'SELECT, INSERT, UPDATE, DELETE'
     )
     or exists (
       select 1
       from pg_catalog.pg_class as relation
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           relation.relacl,
           pg_catalog.acldefault('r', relation.relowner)
         )
       ) as privilege
       where relation.oid = 'public.post_images'::pg_catalog.regclass
         and privilege.grantee = 0
     ) then
    raise exception
      'create_post_images_storage postcondition failed: table privileges differ';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'buckets'
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) or not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'create_post_images_storage postcondition failed: Storage owner changed';
  end if;
end;
$postcondition$;

commit;
