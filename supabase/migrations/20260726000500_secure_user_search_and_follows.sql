begin;

drop policy my_diary_follows_insert_own on public.follows;

create policy my_diary_follows_insert_own
on public.follows
for insert
to authenticated
with check (
  follower_id = (select auth.uid())
  and following_id <> (select auth.uid())
  and my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(following_id)
);

create function public.my_diary_search_profiles(search_query text)
returns table (
  user_id uuid,
  username text,
  bio text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_query text;
  escaped_query text;
begin
  if auth.uid() is null then
    raise insufficient_privilege;
  end if;

  normalized_query := btrim(search_query);

  if normalized_query is null
    or char_length(normalized_query) not between 1 and 50
  then
    raise invalid_parameter_value;
  end if;

  escaped_query := replace(normalized_query, E'\\', E'\\\\');
  escaped_query := replace(escaped_query, '%', E'\\%');
  escaped_query := replace(escaped_query, '_', E'\\_');

  return query
  select
    profiles.user_id,
    profiles.username,
    profiles.bio
  from public.profiles
  join public.accounts
    on accounts.user_id = profiles.user_id
  where (
      accounts.status = 'active'
      or profiles.user_id = auth.uid()
    )
    and profiles.username ilike ('%' || escaped_query || '%') escape E'\\'
  order by
    lower(profiles.username) asc,
    profiles.username asc,
    profiles.user_id asc
  limit 20;
end;
$$;

alter function public.my_diary_search_profiles(text) owner to postgres;
revoke all on function public.my_diary_search_profiles(text)
  from public, anon, authenticated;
grant execute on function public.my_diary_search_profiles(text)
  to authenticated;

commit;
