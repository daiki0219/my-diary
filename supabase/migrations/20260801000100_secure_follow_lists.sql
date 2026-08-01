begin;

drop policy my_diary_follows_select_authenticated on public.follows;

create policy my_diary_follows_select_authenticated
on public.follows
for select
to authenticated
using (
  my_diary_private.my_diary_is_account_active((select auth.uid()))
  and my_diary_private.my_diary_is_account_active(follower_id)
  and my_diary_private.my_diary_is_account_active(following_id)
);

create index my_diary_follows_follower_created_following_idx
  on public.follows (follower_id, created_at desc, following_id desc);

create index my_diary_follows_following_created_follower_idx
  on public.follows (following_id, created_at desc, follower_id desc);

commit;
