import type { SupabaseClient } from "@supabase/supabase-js";

import type { AuthenticatedViewerId } from "@/lib/account-data";
import type { PostMood, PostVisibility } from "@/lib/post-data";

export type CalendarPostQueryRow = {
  id: string;
  title: string | null;
  body: string;
  mood: PostMood | null;
  visibility: PostVisibility;
  created_at: string;
};

export type CalendarSummaryPostQueryRow = Pick<
  CalendarPostQueryRow,
  "id" | "mood" | "created_at"
>;

export function queryCalendarPosts(
  supabase: SupabaseClient,
  viewerUserId: AuthenticatedViewerId,
  range: { start: string; end: string },
) {
  return supabase
    .from("posts")
    .select("id, title, body, mood, visibility, created_at")
    .eq("user_id", viewerUserId)
    .gte("created_at", range.start)
    .lt("created_at", range.end)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .returns<CalendarPostQueryRow[]>();
}

export function queryCalendarSummaryPosts(
  supabase: SupabaseClient,
  viewerUserId: AuthenticatedViewerId,
  range: { start: string; end: string },
) {
  return supabase
    .from("posts")
    .select("id, mood, created_at")
    .eq("user_id", viewerUserId)
    .gte("created_at", range.start)
    .lt("created_at", range.end)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .returns<CalendarSummaryPostQueryRow[]>();
}
