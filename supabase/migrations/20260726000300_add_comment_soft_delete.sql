begin;

create function my_diary_private.my_diary_can_view_post(
  target_post_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.posts
    where posts.id = target_post_id
      and posts.deleted_at is null
      and (
        posts.user_id = auth.uid()
        or (
          my_diary_private.my_diary_is_account_active(auth.uid())
          and my_diary_private.my_diary_is_account_active(posts.user_id)
          and (
            posts.visibility = 'public'
            or (
              posts.visibility = 'followers'
              and exists (
                select 1
                from public.follows
                where follows.follower_id = auth.uid()
                  and follows.following_id = posts.user_id
              )
            )
          )
        )
      )
  );
$$;

alter function my_diary_private.my_diary_can_view_post(uuid)
  owner to postgres;
revoke all on function
  my_diary_private.my_diary_can_view_post(uuid)
  from public, anon, authenticated;
grant execute on function
  my_diary_private.my_diary_can_view_post(uuid)
  to authenticated;

drop policy my_diary_posts_select_visible on public.posts;

create policy my_diary_posts_select_visible
on public.posts
for select
to authenticated
using (
  my_diary_private.my_diary_can_view_post(posts.id)
);

revoke update (deleted_at) on table public.comments from authenticated;
drop policy my_diary_comments_soft_delete_own on public.comments;

create function public.my_diary_soft_delete_comment(
  target_comment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_rows integer;
begin
  update public.comments
  set deleted_at = now()
  where id = target_comment_id
    and user_id = auth.uid()
    and deleted_at is null
    and my_diary_private.my_diary_is_account_active(auth.uid())
    and my_diary_private.my_diary_can_view_post(post_id);

  get diagnostics affected_rows = row_count;
  return affected_rows = 1;
end;
$$;

alter function public.my_diary_soft_delete_comment(uuid)
  owner to postgres;
revoke all on function public.my_diary_soft_delete_comment(uuid)
  from public, anon, authenticated;
grant execute on function public.my_diary_soft_delete_comment(uuid)
  to authenticated;

commit;
