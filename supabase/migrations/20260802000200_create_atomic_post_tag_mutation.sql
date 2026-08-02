begin;

do $preflight$
begin
  if exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_tags',
        'my_diary_update_post_with_tags'
      )
  ) then
    raise exception
      'atomic post/tag mutation preflight failed: an RPC name already exists';
  end if;

  if pg_catalog.to_regclass('public.accounts') is null
     or pg_catalog.to_regclass('public.posts') is null
     or pg_catalog.to_regclass('public.tags') is null
     or pg_catalog.to_regclass('public.post_tags') is null
     or pg_catalog.to_regprocedure(
       'my_diary_private.my_diary_normalize_tag_name(text)'
     ) is null then
    raise exception
      'atomic post/tag mutation preflight failed: a required object is missing';
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
      'atomic post/tag mutation preflight failed: a required role is missing';
  end if;

  if not (
    pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'user_id', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'title', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'body', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'mood', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'location_name', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'visibility', 'INSERT'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'title', 'UPDATE'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'body', 'UPDATE'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'mood', 'UPDATE'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'location_name', 'UPDATE'
    )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.posts', 'visibility', 'UPDATE'
    )
  ) then
    raise exception
      'atomic post/tag mutation preflight failed: posts grants differ';
  end if;
end;
$preflight$;

create function public.my_diary_create_post_with_tags(
  p_title text,
  p_body text,
  p_mood text,
  p_visibility text,
  p_tags text[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_post_id uuid;
  v_title text;
  v_body text;
  v_mood text;
  v_visibility text;
  v_raw_tags text[] := coalesce(p_tags, array[]::text[]);
  v_canonical_tags text[] := array[]::text[];
  v_raw_tag text;
  v_canonical_tag text;
  v_tag_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null or not exists (
    select 1
    from public.accounts
    where user_id = v_user_id
      and status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  v_title := nullif(
    pg_catalog.regexp_replace(
      p_title,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );
  v_body := pg_catalog.regexp_replace(
    p_body,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  v_mood := nullif(pg_catalog.btrim(p_mood), '');
  v_visibility := pg_catalog.btrim(p_visibility);

  if (v_title is not null and pg_catalog.char_length(v_title) > 120)
     or v_body is null
     or pg_catalog.char_length(v_body) not between 1 and 10000
     or (v_mood is not null and v_mood not in (
       'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
     ))
     or v_visibility is null
     or v_visibility not in ('private', 'followers', 'public') then
    raise exception using
      errcode = '22023',
      message = 'Invalid post input.';
  end if;

  if pg_catalog.cardinality(v_raw_tags) > 20
     or (
       pg_catalog.cardinality(v_raw_tags) > 0
       and pg_catalog.array_ndims(v_raw_tags) <> 1
     ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  foreach v_raw_tag in array v_raw_tags loop
    if v_raw_tag is null then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    v_canonical_tag :=
      my_diary_private.my_diary_normalize_tag_name(v_raw_tag);

    if v_canonical_tag is null
       or pg_catalog.char_length(v_canonical_tag) not between 1 and 30
       or pg_catalog.strpos(v_canonical_tag, ',') > 0
       or pg_catalog.strpos(v_canonical_tag, '#') > 0
       or v_canonical_tag ~ '[[:cntrl:]]' then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    if not (v_canonical_tag = any(v_canonical_tags)) then
      v_canonical_tags := pg_catalog.array_append(
        v_canonical_tags,
        v_canonical_tag
      );
    end if;
  end loop;

  select coalesce(
    pg_catalog.array_agg(tag_name order by tag_name),
    array[]::text[]
  )
  into v_canonical_tags
  from pg_catalog.unnest(v_canonical_tags) as canonical(tag_name);

  if pg_catalog.cardinality(v_canonical_tags) > 5 then
    raise exception using
      errcode = '22023',
      message = 'Invalid tag input.';
  end if;

  insert into public.posts (
    user_id,
    title,
    body,
    mood,
    visibility
  )
  values (
    v_user_id,
    v_title,
    v_body,
    v_mood,
    v_visibility
  )
  returning id into v_post_id;

  foreach v_canonical_tag in array v_canonical_tags loop
    insert into public.tags (name, normalized_name)
    values (v_canonical_tag, v_canonical_tag)
    on conflict (normalized_name) do nothing;

    select id
    into v_tag_id
    from public.tags
    where normalized_name = v_canonical_tag;

    if v_tag_id is null then
      raise exception using
        errcode = '40001',
        message = 'Tag resolution must be retried.';
    end if;

    insert into public.post_tags (post_id, tag_id)
    values (v_post_id, v_tag_id);
  end loop;

  return v_post_id;
end;
$function$;

create function public.my_diary_update_post_with_tags(
  p_post_id uuid,
  p_title text,
  p_body text,
  p_mood text,
  p_visibility text,
  p_tags text[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_locked_post_id uuid;
  v_title text;
  v_body text;
  v_mood text;
  v_visibility text;
  v_canonical_tags text[] := array[]::text[];
  v_tag_ids uuid[] := array[]::uuid[];
  v_raw_tag text;
  v_canonical_tag text;
  v_tag_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null or not exists (
    select 1
    from public.accounts
    where user_id = v_user_id
      and status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  v_title := nullif(
    pg_catalog.regexp_replace(
      p_title,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );
  v_body := pg_catalog.regexp_replace(
    p_body,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  v_mood := nullif(pg_catalog.btrim(p_mood), '');
  v_visibility := pg_catalog.btrim(p_visibility);

  if p_post_id is null
     or (v_title is not null and pg_catalog.char_length(v_title) > 120)
     or v_body is null
     or pg_catalog.char_length(v_body) not between 1 and 10000
     or (v_mood is not null and v_mood not in (
       'happy', 'sad', 'tired', 'irritated', 'calm', 'neutral'
     ))
     or v_visibility is null
     or v_visibility not in ('private', 'followers', 'public') then
    raise exception using
      errcode = '22023',
      message = 'Invalid post input.';
  end if;

  if p_tags is not null then
    if pg_catalog.cardinality(p_tags) > 20
       or (
         pg_catalog.cardinality(p_tags) > 0
         and pg_catalog.array_ndims(p_tags) <> 1
       ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;

    foreach v_raw_tag in array p_tags loop
      if v_raw_tag is null then
        raise exception using
          errcode = '22023',
          message = 'Invalid tag input.';
      end if;

      v_canonical_tag :=
        my_diary_private.my_diary_normalize_tag_name(v_raw_tag);

      if v_canonical_tag is null
         or pg_catalog.char_length(v_canonical_tag) not between 1 and 30
         or pg_catalog.strpos(v_canonical_tag, ',') > 0
         or pg_catalog.strpos(v_canonical_tag, '#') > 0
         or v_canonical_tag ~ '[[:cntrl:]]' then
        raise exception using
          errcode = '22023',
          message = 'Invalid tag input.';
      end if;

      if not (v_canonical_tag = any(v_canonical_tags)) then
        v_canonical_tags := pg_catalog.array_append(
          v_canonical_tags,
          v_canonical_tag
        );
      end if;
    end loop;

    select coalesce(
      pg_catalog.array_agg(tag_name order by tag_name),
      array[]::text[]
    )
    into v_canonical_tags
    from pg_catalog.unnest(v_canonical_tags) as canonical(tag_name);

    if pg_catalog.cardinality(v_canonical_tags) > 5 then
      raise exception using
        errcode = '22023',
        message = 'Invalid tag input.';
    end if;
  end if;

  select id
  into v_locked_post_id
  from public.posts
  where id = p_post_id
    and user_id = v_user_id
    and deleted_at is null
  for update;

  if v_locked_post_id is null then
    raise exception using
      errcode = '42501',
      message = 'Post mutation is not permitted.';
  end if;

  update public.posts
  set title = v_title,
      body = v_body,
      mood = v_mood,
      visibility = v_visibility
  where id = v_locked_post_id;

  if p_tags is not null then
    foreach v_canonical_tag in array v_canonical_tags loop
      insert into public.tags (name, normalized_name)
      values (v_canonical_tag, v_canonical_tag)
      on conflict (normalized_name) do nothing;

      select id
      into v_tag_id
      from public.tags
      where normalized_name = v_canonical_tag;

      if v_tag_id is null then
        raise exception using
          errcode = '40001',
          message = 'Tag resolution must be retried.';
      end if;

      v_tag_ids := pg_catalog.array_append(v_tag_ids, v_tag_id);
    end loop;

    delete from public.post_tags as existing
    where existing.post_id = v_locked_post_id
      and not (existing.tag_id = any(v_tag_ids));

    insert into public.post_tags (post_id, tag_id)
    select v_locked_post_id, desired.tag_id
    from pg_catalog.unnest(v_tag_ids) as desired(tag_id)
    where not exists (
      select 1
      from public.post_tags as existing
      where existing.post_id = v_locked_post_id
        and existing.tag_id = desired.tag_id
    );
  end if;

  return v_locked_post_id;
end;
$function$;

alter function public.my_diary_create_post_with_tags(
  text,
  text,
  text,
  text,
  text[]
) owner to postgres;
alter function public.my_diary_update_post_with_tags(
  uuid,
  text,
  text,
  text,
  text,
  text[]
) owner to postgres;

comment on function public.my_diary_create_post_with_tags(
  text,
  text,
  text,
  text,
  text[]
) is 'Atomically creates an owned post and its canonical tag relations.';
comment on function public.my_diary_update_post_with_tags(
  uuid,
  text,
  text,
  text,
  text,
  text[]
) is 'Atomically updates an owned post and optionally replaces its canonical tag relations.';

revoke all on function public.my_diary_create_post_with_tags(
  text,
  text,
  text,
  text,
  text[]
) from public, anon, authenticated, service_role, authenticator;
revoke all on function public.my_diary_update_post_with_tags(
  uuid,
  text,
  text,
  text,
  text,
  text[]
) from public, anon, authenticated, service_role, authenticator;

grant execute on function public.my_diary_create_post_with_tags(
  text,
  text,
  text,
  text,
  text[]
) to authenticated;
grant execute on function public.my_diary_update_post_with_tags(
  uuid,
  text,
  text,
  text,
  text,
  text[]
) to authenticated;

revoke insert (user_id, title, body, mood, location_name, visibility)
  on table public.posts from authenticated;
revoke update (title, body, mood, location_name, visibility)
  on table public.posts from authenticated;

do $postcondition$
declare
  create_oid oid;
  update_oid oid;
begin
  select function.oid
  into create_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_create_post_with_tags'
    and function.proargtypes = '25 25 25 25 1009'::oidvector
    and function.proargnames = array[
      'p_title', 'p_body', 'p_mood', 'p_visibility', 'p_tags'
    ]::text[]
    and function.prorettype = 'uuid'::pg_catalog.regtype
    and function.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function.provolatile = 'v'
    and function.prosecdef
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.proconfig = array['search_path=""']::text[];

  select function.oid
  into update_oid
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = function.pronamespace
  join pg_catalog.pg_language as language
    on language.oid = function.prolang
  where namespace.nspname = 'public'
    and function.proname = 'my_diary_update_post_with_tags'
    and function.proargtypes = '2950 25 25 25 25 1009'::oidvector
    and function.proargnames = array[
      'p_post_id', 'p_title', 'p_body', 'p_mood', 'p_visibility', 'p_tags'
    ]::text[]
    and function.prorettype = 'uuid'::pg_catalog.regtype
    and function.prokind = 'f'
    and language.lanname = 'plpgsql'
    and function.provolatile = 'v'
    and function.prosecdef
    and pg_catalog.pg_get_userbyid(function.proowner) = 'postgres'
    and function.proconfig = array['search_path=""']::text[];

  if create_oid is null or update_oid is null then
    raise exception
      'atomic post/tag mutation postcondition failed: function attributes differ';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname in (
        'my_diary_create_post_with_tags',
        'my_diary_update_post_with_tags'
      )
  ) <> 2 then
    raise exception
      'atomic post/tag mutation postcondition failed: unexpected overload exists';
  end if;

  if pg_catalog.obj_description(create_oid, 'pg_proc') is null
     or pg_catalog.obj_description(update_oid, 'pg_proc') is null then
    raise exception
      'atomic post/tag mutation postcondition failed: function comment is missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as function
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function.proacl,
        pg_catalog.acldefault('f', function.proowner)
      )
    ) as privilege
    where function.oid in (create_oid, update_oid)
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'atomic post/tag mutation postcondition failed: PUBLIC can execute an RPC';
  end if;

  if pg_catalog.has_function_privilege('anon', create_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       'authenticated', create_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege('service_role', create_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticator', create_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', update_oid, 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       'authenticated', update_oid, 'EXECUTE'
     )
     or pg_catalog.has_function_privilege('service_role', update_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticator', update_oid, 'EXECUTE') then
    raise exception
      'atomic post/tag mutation postcondition failed: RPC ACL differs';
  end if;

  if pg_catalog.has_any_column_privilege(
       'authenticated', 'public.posts', 'INSERT'
     )
     or pg_catalog.has_any_column_privilege(
       'authenticated', 'public.posts', 'UPDATE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.posts', 'SELECT'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'SELECT'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.tags', 'INSERT, UPDATE, DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.post_tags', 'INSERT, UPDATE, DELETE'
     ) then
    raise exception
      'atomic post/tag mutation postcondition failed: table privileges differ';
  end if;
end;
$postcondition$;

commit;
