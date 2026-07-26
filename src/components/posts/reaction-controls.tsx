"use client";

import { useActionState } from "react";

import {
  toggleReaction,
  type ToggleReactionActionState,
} from "@/app/(protected)/posts/actions";
import {
  REACTION_OPTIONS,
  type ReactionSummary,
} from "@/lib/reaction-data";

export function ReactionControls({
  postId,
  summary,
}: {
  postId: string;
  summary: ReactionSummary | null;
}) {
  const initialState: ToggleReactionActionState = { error: null };
  const [state, formAction, isPending] = useActionState(
    toggleReaction,
    initialState,
  );

  if (!summary) {
    return (
      <p
        className="mt-5 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
        role="alert"
      >
        リアクションを読み込めませんでした。時間をおいてもう一度お試しください。
      </p>
    );
  }

  return (
    <form action={formAction} className="mt-5 border-t border-stone-100 pt-4">
      <input name="postId" type="hidden" value={postId} />

      <fieldset className="min-w-0">
        <legend className="text-sm font-semibold text-stone-700">
          リアクション
          <span className="ml-2 font-normal text-stone-500">
            合計 {summary.total}
          </span>
        </legend>

        <div className="mt-3 flex min-w-0 flex-wrap gap-2">
          {REACTION_OPTIONS.map((option) => {
            const isSelected =
              summary.currentUserReaction === option.value;
            const actionLabel = isSelected
              ? `${option.label}を解除`
              : summary.currentUserReaction
                ? `${option.label}に変更`
                : `${option.label}を付ける`;

            return (
              <button
                aria-disabled={isPending}
                aria-label={`${actionLabel}。現在${summary.counts[option.value]}件`}
                aria-pressed={isSelected}
                className={`min-h-11 min-w-0 flex-1 basis-28 rounded-full border px-3 py-2 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:opacity-60 ${
                  isSelected
                    ? "border-orange-500 bg-orange-100 text-orange-900"
                    : "border-stone-300 bg-white text-stone-700 hover:border-orange-300 hover:bg-orange-50"
                }`}
                disabled={isPending}
                key={option.value}
                name="reactionType"
                type="submit"
                value={option.value}
              >
                <span aria-hidden="true">{option.symbol}</span>{" "}
                {option.label} {summary.counts[option.value]}
                {isSelected && (
                  <span className="block text-xs font-medium">選択中</span>
                )}
              </button>
            );
          })}
        </div>
      </fieldset>

      {isPending && (
        <p
          aria-live="polite"
          className="mt-3 text-sm text-stone-600"
          role="status"
        >
          リアクションを更新中…
        </p>
      )}

      {state.error && (
        <p
          aria-live="polite"
          className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}
    </form>
  );
}
