import type { SupabaseClient } from "@supabase/supabase-js";

export const REACTION_TYPES = ["empathy", "support", "relatable"] as const;

export type ReactionType = (typeof REACTION_TYPES)[number];

export const REACTION_OPTIONS: ReadonlyArray<{
  value: ReactionType;
  label: string;
  symbol: string;
}> = [
  { value: "empathy", label: "共感", symbol: "❤️" },
  { value: "support", label: "応援", symbol: "🤝" },
  { value: "relatable", label: "わかる", symbol: "😊" },
];

export type ReactionSummary = {
  counts: Record<ReactionType, number>;
  total: number;
  currentUserReaction: ReactionType | null;
};

type ReactionRow = {
  post_id: string;
  user_id: string;
  reaction_type: ReactionType;
};

export function isReactionType(value: string): value is ReactionType {
  return REACTION_TYPES.some((reactionType) => reactionType === value);
}

function createEmptySummary(): ReactionSummary {
  return {
    counts: {
      empathy: 0,
      support: 0,
      relatable: 0,
    },
    total: 0,
    currentUserReaction: null,
  };
}

export async function getReactionSummaries(
  supabase: SupabaseClient,
  postIds: string[],
  currentUserId: string,
) {
  const summaries = new Map<string, ReactionSummary>(
    postIds.map((postId) => [postId, createEmptySummary()]),
  );

  if (postIds.length === 0) {
    return { data: summaries, error: null };
  }

  const result = await supabase
    .from("reactions")
    .select("post_id, user_id, reaction_type")
    .in("post_id", postIds)
    .returns<ReactionRow[]>();

  if (result.error || !result.data) {
    return { data: null, error: result.error };
  }

  for (const reaction of result.data) {
    const summary = summaries.get(reaction.post_id);

    if (!summary || !isReactionType(reaction.reaction_type)) {
      continue;
    }

    summary.counts[reaction.reaction_type] += 1;
    summary.total += 1;

    if (reaction.user_id === currentUserId) {
      summary.currentUserReaction = reaction.reaction_type;
    }
  }

  return { data: summaries, error: null };
}
