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
  variant = "default",
}: {
  postId: string;
  summary: ReactionSummary | null;
  variant?: "default" | "timeline";
}) {
  const initialState: ToggleReactionActionState = { error: null };
  const [state, formAction, isPending] = useActionState(
    toggleReaction,
    initialState,
  );

  if (!summary) {
    return (
      <p
        className={`rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700 ${
          variant === "timeline" ? "mt-1" : "mt-5"
        }`}
        role="alert"
      >
        リアクションを読み込めませんでした。時間をおいてもう一度お試しください。
      </p>
    );
  }

  return (
    <form
      action={formAction}
      className={
        variant === "timeline"
          ? "min-w-0"
          : "mt-5 border-t border-stone-100 pt-4"
      }
    >
      <input name="postId" type="hidden" value={postId} />

      <fieldset className="min-w-0">
        <legend
          className={
            variant === "timeline"
              ? "text-[11px] font-medium text-text-muted"
              : "text-sm font-semibold text-stone-700"
          }
        >
          リアクション
          <span
            className={
              variant === "timeline"
                ? "ml-1 font-normal tabular-nums"
                : "ml-2 font-normal text-stone-500"
            }
          >
            {variant === "timeline" ? "· 合計 " : "合計 "}
            {summary.total}
          </span>
        </legend>

        <div
          className={
            variant === "timeline"
              ? "mt-1.5 grid min-w-0 grid-cols-3 gap-1"
              : "mt-3 flex min-w-0 flex-wrap gap-2"
          }
        >
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
                className={`min-h-11 min-w-0 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:opacity-60 ${
                  variant === "timeline"
                    ? `relative inline-flex items-center justify-center gap-1 rounded-xl border px-1 py-1 text-xs font-medium ${
                        isSelected
                          ? "border-brand-primary bg-brand-soft text-brand-primary-hover"
                          : "border-transparent bg-surface-muted/65 text-text-secondary hover:border-border-subtle hover:bg-brand-soft/60"
                      }`
                    : `flex-1 basis-28 rounded-full border px-3 py-2 text-sm font-semibold ${
                        isSelected
                          ? "border-orange-500 bg-orange-100 text-orange-900"
                          : "border-stone-300 bg-white text-stone-700 hover:border-orange-300 hover:bg-orange-50"
                      }`
                }`}
                disabled={isPending}
                key={option.value}
                name="reactionType"
                type="submit"
                value={option.value}
              >
                {variant === "timeline" ? (
                  <>
                    <span aria-hidden="true">{option.symbol}</span>
                    <span className="min-w-0 text-center leading-4 [overflow-wrap:anywhere]">
                      {option.label}{" "}
                      <span className="tabular-nums">
                        {summary.counts[option.value]}
                      </span>
                    </span>
                    {isSelected && (
                      <span
                        aria-hidden="true"
                        className="absolute right-1 top-0.5 text-[9px]"
                      >
                        ✓
                      </span>
                    )}
                  </>
                ) : (
                  <>
                    <span aria-hidden="true">{option.symbol}</span>{" "}
                    {option.label} {summary.counts[option.value]}
                    {isSelected && (
                      <span className="block text-xs font-medium">
                        選択中
                      </span>
                    )}
                  </>
                )}
              </button>
            );
          })}
        </div>
      </fieldset>

      {isPending && (
        <p
          aria-live="polite"
          className={
            variant === "timeline"
              ? "mt-2 text-xs text-text-muted"
              : "mt-3 text-sm text-stone-600"
          }
          role="status"
        >
          リアクションを更新中…
        </p>
      )}

      {state.error && (
        <p
          aria-live="polite"
          className={`rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700 ${
            variant === "timeline" ? "mt-2" : "mt-3"
          }`}
          role="alert"
        >
          {state.error}
        </p>
      )}
    </form>
  );
}
