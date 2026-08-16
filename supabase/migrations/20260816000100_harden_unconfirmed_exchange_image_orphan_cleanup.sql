begin;

do $preflight$
declare
  maintenance_function_oid oid := pg_catalog.to_regprocedure(
    'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'
  );
  create_function_oid oid := pg_catalog.to_regprocedure(
    'public.my_diary_create_exchange_entry_with_images(uuid,uuid,text,text,text,text,text[],text[])'
  );
  update_function_oid oid := pg_catalog.to_regprocedure(
    'public.my_diary_update_exchange_entry_with_images(uuid,text,text,text,text,text[],jsonb)'
  );
begin
  if pg_catalog.to_regrole('anon') is null
     or pg_catalog.to_regrole('authenticated') is null
     or pg_catalog.to_regrole('service_role') is null
     or pg_catalog.to_regrole('authenticator') is null
     or pg_catalog.to_regclass('public.exchange_entry_images') is null
     or pg_catalog.to_regclass(
       'my_diary_private.exchange_entry_image_cleanup_candidates'
     ) is null
     or pg_catalog.to_regclass('public.report_snapshot_images') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_is_active_admin()'
     ) is null
     or maintenance_function_oid is null
     or create_function_oid is null
     or update_function_oid is null then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup preflight failed: required dependency missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function_definition.pronamespace
    where namespace.nspname = 'public'
      and function_definition.proname =
        'my_diary_list_due_unconfirmed_exchange_image_orphans'
  ) then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup preflight failed: object collision';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'storage.objects'::pg_catalog.regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (
        (attribute.attname = 'id'
         and attribute.atttypid = 'uuid'::pg_catalog.regtype)
        or (attribute.attname = 'bucket_id'
            and attribute.atttypid = 'text'::pg_catalog.regtype)
        or (attribute.attname = 'name'
            and attribute.atttypid = 'text'::pg_catalog.regtype)
        or (attribute.attname = 'owner_id'
            and attribute.atttypid = 'text'::pg_catalog.regtype)
        or (attribute.attname = 'created_at'
            and attribute.atttypid =
              'timestamp with time zone'::pg_catalog.regtype)
      )
  ) <> 5
  or not exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    join pg_catalog.pg_attrdef as attribute_default
      on attribute_default.adrelid = attribute.attrelid
     and attribute_default.adnum = attribute.attnum
    where attribute.attrelid = 'storage.objects'::pg_catalog.regclass
      and attribute.attname = 'created_at'
      and pg_catalog.pg_get_expr(
        attribute_default.adbin, attribute_default.adrelid
      ) = 'now()'
  ) then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup preflight failed: Storage creation clock or identity differs';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_class as relation
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = relation.relnamespace
       where namespace.nspname = 'storage'
         and relation.relname = 'objects'
         and relation.relrowsecurity
         and pg_catalog.pg_get_userbyid(relation.relowner) =
           'supabase_storage_admin'
     )
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like 'my_diary_exchange_entry_images_storage_%'
     ) <> 11
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like
           'my_diary_exchange_entry_images_storage_guard_%'
         and permissive = 'RESTRICTIVE'
     ) <> 4 then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup preflight failed: Storage owner or policy composition differs';
  end if;

  if pg_catalog.pg_get_functiondef(create_function_oid)
       not like '%from storage.objects%for update%'
     or pg_catalog.pg_get_functiondef(update_function_oid)
       not like '%from storage.objects%for update%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%exchange_entry_image_cleanup_candidates%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%report_snapshot_images%' then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup preflight failed: effective locking or retention differs';
  end if;
end;
$preflight$;

-- Keep the existing trusted Storage policy boundary. Its first branch retains
-- the confirmed-image candidate contract; the second, disjoint branch covers
-- only old objects that were never entered into any confirmed lifecycle.
create or replace function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    p_storage_object_id uuid,
    p_storage_path text
  )
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  locked_owner_id text;
  locked_created_at timestamptz;
  due_confirmed_candidate boolean := false;
begin
  if not my_diary_private.my_diary_is_active_admin()
     or not storage.allow_only_operation('storage.object.delete_many')
     or p_storage_object_id is null
     or p_storage_path is null
     or p_storage_path !~
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  -- Successor create/update RPCs lock this same row before confirming metadata.
  select storage_object.owner_id, storage_object.created_at
  into locked_owner_id, locked_created_at
  from storage.objects as storage_object
  where storage_object.bucket_id = 'exchange-entry-images'
    and storage_object.id = p_storage_object_id
    and storage_object.name = p_storage_path
  for update;

  if not found then
    return false;
  end if;

  select true
  into due_confirmed_candidate
  from my_diary_private.exchange_entry_image_cleanup_candidates as candidate
  where candidate.storage_object_id = p_storage_object_id
    and candidate.storage_path = p_storage_path
    and candidate.owner_user_id::text = locked_owner_id
    and candidate.delete_after <= pg_catalog.statement_timestamp()
  for update;

  if due_confirmed_candidate then
    return not exists (
      select 1
      from public.exchange_entry_images as image
      where image.storage_path = p_storage_path
    )
    and not exists (
      select 1
      from public.report_snapshot_images as snapshot_image
      where snapshot_image.storage_path = p_storage_path
    );
  end if;

  return locked_owner_id = pg_catalog.split_part(p_storage_path, '/', 1)
    and locked_created_at <=
      pg_catalog.statement_timestamp() - interval '24 hours'
    and not exists (
      select 1
      from public.exchange_entry_images as image
      where image.storage_path = p_storage_path
    )
    and not exists (
      select 1
      from my_diary_private.exchange_entry_image_cleanup_candidates
        as candidate
      where candidate.storage_object_id = p_storage_object_id
         or candidate.storage_path = p_storage_path
    )
    and not exists (
      select 1
      from public.report_snapshot_images as snapshot_image
      where snapshot_image.storage_path = p_storage_path
    );
end;
$function$;

create function public.my_diary_list_due_unconfirmed_exchange_image_orphans(
  p_limit integer
)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_limit is null
     or p_limit not between 1 and 100
     or not my_diary_private.my_diary_is_active_admin() then
    raise exception using
      errcode = '42501',
      message = 'Exchange image maintenance is unavailable.';
  end if;

  return array(
    select storage_object.name
    from storage.objects as storage_object
    where storage_object.bucket_id = 'exchange-entry-images'
      and storage_object.name ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and storage_object.owner_id =
        pg_catalog.split_part(storage_object.name, '/', 1)
      and storage_object.created_at <=
        pg_catalog.statement_timestamp() - interval '24 hours'
      and not exists (
        select 1
        from public.exchange_entry_images as image
        where image.storage_path = storage_object.name
      )
      and not exists (
        select 1
        from my_diary_private.exchange_entry_image_cleanup_candidates
          as candidate
        where candidate.storage_object_id = storage_object.id
           or candidate.storage_path = storage_object.name
      )
      and not exists (
        select 1
        from public.report_snapshot_images as snapshot_image
        where snapshot_image.storage_path = storage_object.name
      )
    order by storage_object.created_at, storage_object.name, storage_object.id
    limit p_limit
  );
end;
$function$;

alter function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    uuid, text
  ) owner to postgres;
alter function
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)
  owner to postgres;

revoke all on function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    uuid, text
  ) from public, anon, authenticated, service_role, authenticator;
revoke all on function
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)
  from public, anon, authenticated, service_role, authenticator;

grant execute on function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    uuid, text
  ) to authenticated;
grant execute on function
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)
  to authenticated;

comment on function
  my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(
    uuid, text
  ) is 'Authorizes active-admin deletion of a locked due confirmed candidate or a 24-hour-old never-confirmed Exchange image orphan.';
comment on function
  public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)
is 'Lists 24-hour-old never-confirmed Exchange image orphans for active-admin maintenance.';

do $postcondition$
declare
  maintenance_function_oid oid :=
    'my_diary_private.my_diary_exchange_entry_image_maintenance_delete_is_allowed(uuid,text)'::pg_catalog.regprocedure;
  list_function_oid oid :=
    'public.my_diary_list_due_unconfirmed_exchange_image_orphans(integer)'::pg_catalog.regprocedure;
begin
  if not (
       select function_definition.prosecdef
         and function_definition.provolatile = 'v'
         and function_definition.proconfig = array['search_path=""']::text[]
         and function_definition.pronargdefaults = 0
         and pg_catalog.pg_get_userbyid(function_definition.proowner) =
           'postgres'
       from pg_catalog.pg_proc as function_definition
       where function_definition.oid = maintenance_function_oid
     )
     or not (
       select function_definition.prosecdef
         and function_definition.provolatile = 's'
         and function_definition.proconfig = array['search_path=""']::text[]
         and function_definition.pronargdefaults = 0
         and pg_catalog.pg_get_userbyid(function_definition.proowner) =
           'postgres'
       from pg_catalog.pg_proc as function_definition
       where function_definition.oid = list_function_oid
     )
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_proc as function_definition
       where function_definition.pronamespace =
         'public'::pg_catalog.regnamespace
         and function_definition.proname =
           'my_diary_list_due_unconfirmed_exchange_image_orphans'
     ) <> 1 then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: function hardening differs';
  end if;

  if exists (
       select 1
       from pg_catalog.unnest(
         array[maintenance_function_oid, list_function_oid]
       ) as target(function_oid)
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           (select function_definition.proacl
            from pg_catalog.pg_proc as function_definition
            where function_definition.oid = target.function_oid),
           pg_catalog.acldefault(
             'f',
             (select function_definition.proowner
              from pg_catalog.pg_proc as function_definition
              where function_definition.oid = target.function_oid)
           )
         )
       ) as privilege
       where privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['anon', 'service_role', 'authenticator']
       ) as denied(role_name)
       cross join pg_catalog.unnest(
         array[maintenance_function_oid, list_function_oid]
       ) as target(function_oid)
       where pg_catalog.has_function_privilege(
         denied.role_name, target.function_oid, 'EXECUTE'
       )
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', maintenance_function_oid, 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', list_function_oid, 'EXECUTE'
     ) then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: function ACL differs';
  end if;

  if pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%for update%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%interval ''24 hours''%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%exchange_entry_images%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%exchange_entry_image_cleanup_candidates%'
     or pg_catalog.pg_get_functiondef(maintenance_function_oid)
       not like '%report_snapshot_images%' then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: locked eligibility differs';
  end if;

  if (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like 'my_diary_exchange_entry_images_storage_%'
     ) <> 11
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like
           'my_diary_exchange_entry_images_storage_guard_%'
         and permissive = 'RESTRICTIVE'
     ) <> 4
     or exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname like 'my_diary_exchange_entry_images_storage_%'
         and cmd in ('ALL', 'UPDATE')
     )
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and coalesce(qual, '') like
           '%my_diary_exchange_entry_image_maintenance_delete_is_allowed%'
     ) <> 4 then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: Storage policy differs';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_constraint
       where conrelid =
         'my_diary_private.exchange_entry_image_cleanup_candidates'::pg_catalog.regclass
         and conname =
           'my_diary_exchange_image_cleanup_candidates_retention_check'
         and pg_catalog.pg_get_constraintdef(oid) like
           '%removed_at + ''7 days''::interval%'
     )
     or not exists (
       select 1
       from pg_catalog.pg_constraint
       where conrelid = 'public.reports'::pg_catalog.regclass
         and conname = 'my_diary_reports_evidence_retention_shape_check'
         and pg_catalog.pg_get_constraintdef(oid) like
           '%resolved_at + ''30 days''::interval%'
     ) then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: existing retention differs';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
      and relation.relrowsecurity
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'supabase_storage_admin'
  ) then
    raise exception
      'harden_unconfirmed_exchange_image_orphan_cleanup postcondition failed: Storage owner or RLS differs';
  end if;
end;
$postcondition$;

commit;
