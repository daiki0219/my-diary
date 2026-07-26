begin;

create function my_diary_private.my_diary_can_view_post(
  post_user_id uuid,
  post_visibility text,
  post_deleted_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    post_deleted_at is null
    and (
      post_user_id = auth.uid()
      or (
        my_diary_private.my_diary_is_account_active(auth.uid())
        and my_diary_private.my_diary_is_account_active(post_user_id)
        and (
          post_visibility = 'public'
          or (
            post_visibility = 'followers'
            and exists (
              select 1
              from public.follows
              where follows.follower_id = auth.uid()
                and follows.following_id = post_user_id
            )
          )
        )
      )
    );
$$;

alter function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  owner to postgres;
revoke all on function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  from public, anon, authenticated;
grant execute on function my_diary_private.my_diary_can_view_post(
  uuid,
  text,
  timestamptz
)
  to authenticated;

drop policy my_diary_posts_select_visible on public.posts;

create policy my_diary_posts_select_visible
on public.posts
for select
to authenticated
using (
  my_diary_private.my_diary_can_view_post(
    posts.user_id,
    posts.visibility,
    posts.deleted_at
  )
);

create or replace function public.my_diary_soft_delete_comment(
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
  update public.comments as comments
  set deleted_at = now()
  from public.posts as posts
  where comments.id = target_comment_id
    and comments.user_id = auth.uid()
    and comments.deleted_at is null
    and my_diary_private.my_diary_is_account_active(auth.uid())
    and posts.id = comments.post_id
    and my_diary_private.my_diary_can_view_post(
      posts.user_id,
      posts.visibility,
      posts.deleted_at
    );

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

drop function my_diary_private.my_diary_can_view_post(uuid);

commit;
