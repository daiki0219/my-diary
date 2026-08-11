begin;

create extension if not exists pgtap with schema extensions;

select plan(86);

-- Bucket, metadata schema, RLS, ACL, and exact RPC catalog.
select is(
  (select pg_catalog.count(*) from storage.buckets
   where id = 'exchange-entry-images' and name = 'exchange-entry-images'),
  1::bigint,
  'the exchange entry image bucket exists exactly once'
);

select is(
  (select public from storage.buckets where id = 'exchange-entry-images'),
  false,
  'the exchange entry image bucket is private'
);

select is(
  (select file_size_limit from storage.buckets
   where id = 'exchange-entry-images'),
  6291456::bigint,
  'the bucket limit is 6 MiB'
);

select is(
  (select allowed_mime_types from storage.buckets
   where id = 'exchange-entry-images'),
  array['image/jpeg', 'image/png', 'image/webp']::text[],
  'the bucket allows only JPEG PNG and WebP'
);

select columns_are(
  'public', 'exchange_entry_images',
  array['id', 'entry_id', 'storage_path', 'sort_order', 'created_at'],
  'exchange_entry_images has the expected columns'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entry_images'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_images_entry_id_fkey'
      and confrelid = 'public.exchange_entries'::pg_catalog.regclass
      and confdeltype = 'c'
  ),
  'entry FK cascades on physical delete'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entry_images'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_images_entry_sort_key'
      and condeferrable and not condeferred
  ),
  'entry sort uniqueness is deferrable and initially immediate'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.exchange_entry_images'::pg_catalog.regclass
      and conname = 'my_diary_exchange_entry_images_identity_path_check'
      and contype = 'c'
  ),
  'the table enforces strict four-UUID path and image identity'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.exchange_entry_images'::pg_catalog.regclass),
  'exchange_entry_images has RLS enabled'
);

select ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entry_images', 'SELECT'
  ),
  'authenticated receives metadata SELECT'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.exchange_entry_images', 'INSERT, UPDATE, DELETE'
  ),
  'authenticated has no direct metadata mutation privilege'
);

select is(
  (select pg_catalog.count(*) from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'exchange_entry_images'),
  1::bigint,
  'metadata has one SELECT-only policy'
);

select is(
  (select pg_catalog.count(*) from pg_catalog.pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'my_diary_exchange_entry_images_storage_%'),
  8::bigint,
  'the bucket has eight operation-specific Storage policies'
);

select is(
  (select pg_catalog.count(*) from pg_catalog.pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'my_diary_exchange_entry_images_storage_%'
     and cmd in ('ALL', 'UPDATE')),
  0::bigint,
  'the bucket has no Storage UPDATE or ALL policy'
);

select is(
  (select pg_catalog.count(*) from pg_catalog.pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'my_diary_exchange_entry_images_storage_guard_%'
     and permissive = 'RESTRICTIVE'),
  4::bigint,
  'authenticated and anon guards are restrictive'
);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'
  ) is not null,
  'create successor exact signature exists'
);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'
  ) is not null,
  'update successor exact signature exists'
);

select is(
  (select proargnames
   from pg_catalog.pg_proc
   where oid = 'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'::pg_catalog.regprocedure),
  array['p_entry_id','p_diary_id','p_title','p_body','p_mood',
        'p_location_name','p_tags','p_image_paths']::text[],
  'create successor argument names are exact'
);

select is(
  (select proargnames
   from pg_catalog.pg_proc
   where oid = 'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure),
  array['p_entry_id','p_title','p_body','p_mood',
        'p_location_name','p_tags','p_image_manifest']::text[],
  'update successor argument names are exact'
);

select ok(
  (select prosecdef and provolatile = 'v'
          and proconfig = array['search_path=""']::text[]
          and pg_catalog.pg_get_userbyid(proowner) = 'postgres'
   from pg_catalog.pg_proc
   where oid = 'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'::pg_catalog.regprocedure),
  'create successor has hardened function attributes'
);

select ok(
  (select prosecdef and provolatile = 'v'
          and proconfig = array['search_path=""']::text[]
          and pg_catalog.pg_get_userbyid(proowner) = 'postgres'
   from pg_catalog.pg_proc
   where oid = 'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'::pg_catalog.regprocedure),
  'update successor has hardened function attributes'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  ) and pg_catalog.has_function_privilege(
    'authenticated',
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'authenticated alone can execute both successors'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])',
    'EXECUTE'
  ) and not pg_catalog.has_function_privilege(
    'anon',
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)',
    'EXECUTE'
  ),
  'anon cannot execute either successor'
);

select is(
  (select pg_catalog.count(*)
   from pg_catalog.pg_proc as p join pg_catalog.pg_namespace as n
     on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'my_diary_create_exchange_entry_with_images',
       'my_diary_update_exchange_entry_with_images'
     )),
  2::bigint,
  'the successors have no overloads'
);

select ok(
  pg_catalog.to_regprocedure(
    'public.my_diary_create_exchange_entry(uuid,text,text,text,text,text[])'
  ) is not null
  and pg_catalog.to_regprocedure(
    'public.my_diary_update_exchange_entry(uuid,text,text,text,text,text[])'
  ) is not null
  and pg_catalog.to_regprocedure(
    'public.my_diary_soft_delete_exchange_entry(uuid)'
  ) is not null,
  'all predecessor entry RPCs remain available'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'my_diary_private.my_diary_prepare_exchange_entry_tags(text[])',
    'EXECUTE'
  ),
  'the private tag helper is not application executable'
);

-- Active participant fixtures.
insert into auth.users (id, email)
values
  ('a2500000-0000-4000-8000-000000000001', 'e2b2-a@example.test'),
  ('b2500000-0000-4000-8000-000000000002', 'e2b2-b@example.test'),
  ('c2500000-0000-4000-8000-000000000003', 'e2b2-c@example.test');

insert into public.exchange_diaries (id, created_by_position)
values
  ('d2500000-0000-4000-8000-000000000001', 1),
  ('d2500000-0000-4000-8000-000000000002', 1);

insert into public.exchange_diary_participants
  (id, diary_id, position, user_id)
values
  ('12500000-0000-4000-8000-000000000001',
   'd2500000-0000-4000-8000-000000000001', 1,
   'a2500000-0000-4000-8000-000000000001'),
  ('12500000-0000-4000-8000-000000000002',
   'd2500000-0000-4000-8000-000000000001', 2,
   'b2500000-0000-4000-8000-000000000002'),
  ('22500000-0000-4000-8000-000000000001',
   'd2500000-0000-4000-8000-000000000002', 1,
   'b2500000-0000-4000-8000-000000000002'),
  ('22500000-0000-4000-8000-000000000002',
   'd2500000-0000-4000-8000-000000000002', 2,
   'c2500000-0000-4000-8000-000000000003');

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
select
  ('f2510000-0000-4000-8000-' || pg_catalog.lpad(g::text, 12, '0'))::uuid,
  'exchange-entry-images',
  'a2500000-0000-4000-8000-000000000001/' ||
  'd2500000-0000-4000-8000-000000000001/' ||
  'e2500000-0000-4000-8000-000000000010/' ||
  ('f2500000-0000-4000-8000-' || pg_catalog.lpad(g::text, 12, '0')),
  'a2500000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'::jsonb
from pg_catalog.generate_series(1, 10) as fixture(g);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  ('f2520000-0000-4000-8000-000000000001', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000101',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/jpeg","size":1}'),
  ('f2520000-0000-4000-8000-000000000002', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000002/f2500000-0000-4000-8000-000000000102',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/gif","size":68}'),
  ('f2520000-0000-4000-8000-000000000003', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000003/f2500000-0000-4000-8000-000000000103',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":0}'),
  ('f2520000-0000-4000-8000-000000000004', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000004/f2500000-0000-4000-8000-000000000104',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/webp","size":6291456}'),
  ('f2520000-0000-4000-8000-000000000005', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000005/f2500000-0000-4000-8000-000000000105',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":6291457}'),
  ('f2520000-0000-4000-8000-000000000006', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000006/f2500000-0000-4000-8000-000000000106',
   'b2500000-0000-4000-8000-000000000002',
   '{"mimetype":"image/png","size":68}');

select set_config(
  'request.jwt.claim.sub',
  'a2500000-0000-4000-8000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000000',
      'd2500000-0000-4000-8000-000000000001',
      null, 'no images', null, null, null, null
    )$$,
  'create accepts a NULL image array as no images'
);

select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000000'),
  0::bigint,
  'NULL image create stores no metadata'
);

select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000099',
      'd2500000-0000-4000-8000-000000000001',
      null, 'empty images', null, null, array[]::text[], array[]::text[]
    )$$,
  'create accepts an empty image array'
);

reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values
  ('f2520000-0000-4000-8000-000000000011', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000111',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}'),
  ('f2520000-0000-4000-8000-000000000012', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000107',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/webp","size":6291456}'),
  ('f2520000-0000-4000-8000-000000000013', 'exchange-entry-images',
   'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000777/f2500000-0000-4000-8000-000000000777',
   'a2500000-0000-4000-8000-000000000001',
   '{"mimetype":"image/png","size":68}');
set local role authenticated;

select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      'd2500000-0000-4000-8000-000000000001',
      ' image entry ', ' body ', 'calm', ' Tokyo ',
      array[' Secret ', 'secret', 'Beta'],
      array[
        'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000101',
        'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000111'
      ]
    )$$,
  'create atomically claims ordered images and canonical tags'
);

reset role;
select results_eq(
  $$select id, sort_order from public.exchange_entry_images
    where entry_id = 'e2500000-0000-4000-8000-000000000001'
    order by sort_order$$,
  $$values
      ('f2500000-0000-4000-8000-000000000101'::uuid, 0::smallint),
      ('f2500000-0000-4000-8000-000000000111'::uuid, 1::smallint)$$,
  'image id equals path segment four and input order is preserved'
);

select results_eq(
  $$select title, body, mood, location_name from public.exchange_entries
    where id = 'e2500000-0000-4000-8000-000000000001'$$,
  $$values ('image entry'::text, 'body'::text, 'calm'::text, 'Tokyo'::text)$$,
  'create preserves predecessor text normalization'
);

select is(
  (select pg_catalog.count(*) from public.exchange_entry_tags
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'create preserves canonical tag deduplication'
);

insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2520000-0000-4000-8000-000000000080',
  'exchange-entry-images',
  'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000080/f2500000-0000-4000-8000-000000000180',
  'a2500000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'
);

create function pg_temp.my_diary_force_exchange_image_failure()
returns trigger
language plpgsql
as $function$
begin
  raise exception 'Forced exchange image metadata failure.';
end;
$function$;

create trigger my_diary_test_force_exchange_image_failure
before insert on public.exchange_entry_images
for each row execute function pg_temp.my_diary_force_exchange_image_failure();

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000080',
      'd2500000-0000-4000-8000-000000000001',
      null, 'must roll back', null, null, array['AtomicRollback'],
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000080/f2500000-0000-4000-8000-000000000180']
    )$$,
  'P0001', 'Forced exchange image metadata failure.',
  'a late image failure aborts create after entry and tag work'
);

reset role;
drop trigger my_diary_test_force_exchange_image_failure
  on public.exchange_entry_images;

select is(
  (select pg_catalog.count(*) from public.exchange_entries
   where id = 'e2500000-0000-4000-8000-000000000080'),
  0::bigint,
  'late create failure rolls back the entry'
);

select is(
  (select pg_catalog.count(*) from public.tags
   where normalized_name = 'atomicrollback'),
  0::bigint,
  'late create failure rolls back the tag master insert'
);

select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000080'),
  0::bigint,
  'late create failure rolls back image metadata'
);

set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000010',
      'd2500000-0000-4000-8000-000000000001',
      null, 'ten images', null, null, null,
      (select pg_catalog.array_agg(
         'a2500000-0000-4000-8000-000000000001/' ||
         'd2500000-0000-4000-8000-000000000001/' ||
         'e2500000-0000-4000-8000-000000000010/' ||
         ('f2500000-0000-4000-8000-' || pg_catalog.lpad(g::text,12,'0'))
         order by g
       ) from pg_catalog.generate_series(1,10) as fixture(g))
    )$$,
  'create accepts ten images'
);

reset role;
select results_eq(
  $$select pg_catalog.count(*), pg_catalog.min(sort_order),
           pg_catalog.max(sort_order)
    from public.exchange_entry_images
    where entry_id = 'e2500000-0000-4000-8000-000000000010'$$,
  $$values (10::bigint, 0::smallint, 9::smallint)$$,
  'ten images occupy the complete zero-based DB range'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000011',
      'd2500000-0000-4000-8000-000000000001',
      null, 'eleven', null, null, null,
      (select pg_catalog.array_agg(
         'a2500000-0000-4000-8000-000000000001/' ||
         'd2500000-0000-4000-8000-000000000001/' ||
         'e2500000-0000-4000-8000-000000000011/' ||
         ('f2500000-0000-4000-8000-' || pg_catalog.lpad(g::text,12,'0'))
       ) from pg_catalog.generate_series(1,11) as fixture(g))
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects eleven images'
);

reset role;
select is(
  (select pg_catalog.count(*) from public.exchange_entries
   where id = 'e2500000-0000-4000-8000-000000000011'),
  0::bigint,
  'failed eleven-image create leaves no entry'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000012',
      'd2500000-0000-4000-8000-000000000001',
      null, 'duplicate', null, null, null,
      array[
        'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000012/f2500000-0000-4000-8000-000000000120',
        'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000012/f2500000-0000-4000-8000-000000000120'
      ]
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects duplicate paths'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000013',
      'd2500000-0000-4000-8000-000000000001',
      null, 'missing', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000013/f2500000-0000-4000-8000-000000000130']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects a missing Storage object'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000002',
      'd2500000-0000-4000-8000-000000000001',
      null, 'bad mime', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000002/f2500000-0000-4000-8000-000000000102']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects an invalid MIME type'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000003',
      'd2500000-0000-4000-8000-000000000001',
      null, 'zero', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000003/f2500000-0000-4000-8000-000000000103']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects a zero-byte object'
);

select lives_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000004',
      'd2500000-0000-4000-8000-000000000001',
      null, 'six mib', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000004/f2500000-0000-4000-8000-000000000104']
    )$$,
  'create accepts exactly 6 MiB'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000005',
      'd2500000-0000-4000-8000-000000000001',
      null, 'oversize', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000005/f2500000-0000-4000-8000-000000000105']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects over 6 MiB'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000006',
      'd2500000-0000-4000-8000-000000000001',
      null, 'foreign owner', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000006/f2500000-0000-4000-8000-000000000106']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects a foreign-owner object'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000014',
      'd2500000-0000-4000-8000-000000000001',
      null, 'wrong diary path', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000002/e2500000-0000-4000-8000-000000000014/f2500000-0000-4000-8000-000000000140']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects a wrong diary path'
);

select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000015',
      'd2500000-0000-4000-8000-000000000001',
      null, 'wrong entry path', null, null, null,
      array['a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000099/f2500000-0000-4000-8000-000000000150']
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'create rejects a wrong entry path'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2500000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select throws_ok(
  $$select public.my_diary_create_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000016',
      'd2500000-0000-4000-8000-000000000001',
      null, 'third party', null, null, null, null
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a nonparticipant receives the generic unavailable error'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      null, 'oracle probe', null, null, null, '[{}]'::jsonb
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a nonparticipant cannot distinguish an existing entry with invalid manifest'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000999',
      null, 'oracle probe', null, null, null, '[{}]'::jsonb
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'a nonparticipant receives the same error for a missing entry'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'a2500000-0000-4000-8000-000000000001', true
);
select set_config(
  'my_diary.e2b2_retained_created_at',
  (select created_at::text from public.exchange_entry_images
   where id = 'f2500000-0000-4000-8000-000000000111'),
  true
);
set local role authenticated;

select is(
  public.my_diary_update_exchange_entry_with_images(
    'e2500000-0000-4000-8000-000000000001',
    ' updated ', ' updated body ', 'happy', ' Kyoto ',
    array['Gamma'],
    '[
      {"existingId":"f2500000-0000-4000-8000-000000000111"},
      {"newPath":"a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000107"}
    ]'::jsonb
  ),
  pg_catalog.jsonb_build_object(
    'entryId', 'e2500000-0000-4000-8000-000000000001'::uuid,
    'removedImagePaths', pg_catalog.to_jsonb(array[
      'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000101'
    ]::text[])
  ),
  'update returns the exact entryId and DB-derived removed paths shape'
);

reset role;
select results_eq(
  $$select id, sort_order from public.exchange_entry_images
    where entry_id = 'e2500000-0000-4000-8000-000000000001'
    order by sort_order$$,
  $$values
      ('f2500000-0000-4000-8000-000000000111'::uuid, 0::smallint),
      ('f2500000-0000-4000-8000-000000000107'::uuid, 1::smallint)$$,
  'update retains adds deletes and reorders in one final manifest'
);

select is(
  (select created_at::text from public.exchange_entry_images
   where id = 'f2500000-0000-4000-8000-000000000111'),
  current_setting('my_diary.e2b2_retained_created_at'),
  'a retained image preserves created_at'
);

select results_eq(
  $$select title, body, mood, location_name from public.exchange_entries
    where id = 'e2500000-0000-4000-8000-000000000001'$$,
  $$values ('updated'::text, 'updated body'::text,
            'happy'::text, 'Kyoto'::text)$$,
  'image update atomically updates entry text'
);

select is(
  (select pg_catalog.count(*) from public.exchange_entry_tags
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  1::bigint,
  'image update atomically updates tags'
);

set local role authenticated;
select lives_ok(
  $$select public.my_diary_update_exchange_entry(
      'e2500000-0000-4000-8000-000000000001',
      'legacy update', 'legacy body', null, null, null
    )$$,
  'the predecessor update still accepts an image-bearing entry'
);

reset role;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'the predecessor update leaves image metadata unchanged'
);

set local role authenticated;
select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      null, 'bad duplicate', null, null, null,
      '[
        {"existingId":"f2500000-0000-4000-8000-000000000111"},
        {"existingId":"f2500000-0000-4000-8000-000000000111"}
      ]'::jsonb
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'update rejects duplicate existing image IDs'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      null, 'missing existing', null, null, null,
      '[{"existingId":"f2500000-0000-4000-8000-000000000999"}]'::jsonb
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'update rejects a missing existing image'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      null, 'foreign existing', null, null, null,
      '[{"existingId":"f2500000-0000-4000-8000-000000000104"}]'::jsonb
    )$$,
  '22023', 'Invalid exchange entry image input.',
  'update rejects an image from another entry'
);

reset role;
insert into storage.objects (id, bucket_id, name, owner_id, metadata)
values (
  'f2520000-0000-4000-8000-000000000098',
  'exchange-entry-images',
  'a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000998',
  'a2500000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":68}'
);
create trigger my_diary_test_force_exchange_image_failure
before insert on public.exchange_entry_images
for each row execute function pg_temp.my_diary_force_exchange_image_failure();
set local role authenticated;

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      'must rollback', 'must rollback', null, null, array['RollbackTag'],
      '[
        {"existingId":"f2500000-0000-4000-8000-000000000111"},
        {"newPath":"a2500000-0000-4000-8000-000000000001/d2500000-0000-4000-8000-000000000001/e2500000-0000-4000-8000-000000000001/f2500000-0000-4000-8000-000000000998"}
      ]'::jsonb
    )$$,
  'P0001', 'Forced exchange image metadata failure.',
  'a late image failure aborts update after entry and tag work'
);

reset role;
drop trigger my_diary_test_force_exchange_image_failure
  on public.exchange_entry_images;
select results_eq(
  $$select title, body from public.exchange_entries
    where id = 'e2500000-0000-4000-8000-000000000001'$$,
  $$values ('legacy update'::text, 'legacy body'::text)$$,
  'failed update rolls back entry text'
);

select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'failed update rolls back image metadata'
);

select is(
  (select pg_catalog.count(*)
   from public.exchange_entry_tags as et
   join public.tags as tag on tag.id = et.tag_id
   where et.entry_id = 'e2500000-0000-4000-8000-000000000001'
     and tag.normalized_name = 'rollbacktag'),
  0::bigint,
  'failed update rolls back tags'
);

-- Participant-only metadata and object reads.
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'the author can read live image metadata'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2500000-0000-4000-8000-000000000002', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'the other participant can read live image metadata'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where bucket_id = 'exchange-entry-images'
     and name like '%/e2500000-0000-4000-8000-000000000001/%'),
  2::bigint,
  'the other participant can read referenced Storage objects'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2500000-0000-4000-8000-000000000003', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  0::bigint,
  'a nonparticipant cannot read image metadata'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where bucket_id = 'exchange-entry-images'
     and name like '%/e2500000-0000-4000-8000-000000000001/%'),
  0::bigint,
  'a nonparticipant cannot read referenced Storage objects'
);

reset role;
update public.accounts set status = 'suspended'
where user_id = 'b2500000-0000-4000-8000-000000000002';
select set_config(
  'request.jwt.claim.sub',
  'a2500000-0000-4000-8000-000000000001', true
);
set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  0::bigint,
  'a suspended counterpart makes metadata fail closed for both'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where bucket_id = 'exchange-entry-images'
     and name like '%/e2500000-0000-4000-8000-000000000001/%'),
  0::bigint,
  'a suspended counterpart makes Storage fail closed for both'
);

reset role;
update public.accounts set status = 'active'
where user_id = 'b2500000-0000-4000-8000-000000000002';
set local role authenticated;
select lives_ok(
  $$select public.my_diary_archive_exchange_diary(
      'd2500000-0000-4000-8000-000000000001'
    )$$,
  'an active participant archives the diary'
);

select throws_ok(
  $$select public.my_diary_update_exchange_entry_with_images(
      'e2500000-0000-4000-8000-000000000001',
      null, 'archived edit', null, null, null, '[]'::jsonb
    )$$,
  '42501', 'Exchange entry operation is unavailable.',
  'image edit is rejected after archive'
);

select lives_ok(
  $$select public.my_diary_soft_delete_exchange_entry(
      'e2500000-0000-4000-8000-000000000001'
    )$$,
  'the predecessor soft delete still handles an image-bearing archived entry'
);

reset role;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  2::bigint,
  'soft delete retains image metadata physically'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where bucket_id = 'exchange-entry-images'
     and name like '%/e2500000-0000-4000-8000-000000000001/%'),
  4::bigint,
  'soft delete retains referenced and removed Storage objects physically'
);

set local role authenticated;
select is(
  (select pg_catalog.count(*) from public.exchange_entry_images
   where entry_id = 'e2500000-0000-4000-8000-000000000001'),
  0::bigint,
  'soft-deleted entry image metadata is hidden from participants'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where bucket_id = 'exchange-entry-images'
     and name like '%/e2500000-0000-4000-8000-000000000001/%'),
  0::bigint,
  'soft-deleted entry image bytes are hidden from participants'
);

-- Operation-aware orphan upload and cleanup boundary on the other active diary.
reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2500000-0000-4000-8000-000000000002', true
);
select set_config('storage.operation', 'storage.object.upload', true);
set local role authenticated;
select lives_ok(
  $$insert into storage.objects (id, bucket_id, name, owner_id, metadata)
    values (
      'f2520000-0000-4000-8000-000000000020',
      'exchange-entry-images',
      'b2500000-0000-4000-8000-000000000002/d2500000-0000-4000-8000-000000000002/e2500000-0000-4000-8000-000000000020/f2500000-0000-4000-8000-000000000020',
      'b2500000-0000-4000-8000-000000000002',
      '{"mimetype":"image/png","size":68}'::jsonb
    )$$,
  'an active participant can upload into a strict four-UUID namespace'
);

select is(
  (select pg_catalog.count(*) from storage.objects
   where name = 'b2500000-0000-4000-8000-000000000002/d2500000-0000-4000-8000-000000000002/e2500000-0000-4000-8000-000000000020/f2500000-0000-4000-8000-000000000020'),
  1::bigint,
  'the owner can read its unreferenced upload response'
);

select throws_ok(
  $$insert into storage.objects (id, bucket_id, name, owner_id, metadata)
    values (
      'f2520000-0000-4000-8000-000000000021',
      'exchange-entry-images',
      'b2500000-0000-4000-8000-000000000002/not-a-uuid',
      'b2500000-0000-4000-8000-000000000002',
      '{"mimetype":"image/png","size":68}'::jsonb
    )$$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'Storage INSERT rejects a malformed path'
);

select set_config('storage.operation', '', true);
select is(
  (select pg_catalog.count(*) from storage.objects
   where name = 'b2500000-0000-4000-8000-000000000002/d2500000-0000-4000-8000-000000000002/e2500000-0000-4000-8000-000000000020/f2500000-0000-4000-8000-000000000020'),
  0::bigint,
  'an orphan path is hidden outside Storage operation context'
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b2500000-0000-4000-8000-000000000002', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select lives_ok(
  $$select public.my_diary_create_exchange_entry(
      'd2500000-0000-4000-8000-000000000002',
      null, 'legacy create after image migration', null, null, null
    )$$,
  'the predecessor create RPC remains callable'
);

select * from finish();
rollback;
