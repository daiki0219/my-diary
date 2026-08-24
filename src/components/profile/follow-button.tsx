"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import {
  followUser,
  type FollowActionState,
  unfollowUser,
} from "@/app/(protected)/users/actions";

type FollowButtonProps = {
  targetUserId: string;
  isFollowing: boolean;
  canManageFollows: boolean;
  className?: string;
};

const initialState: FollowActionState = {
  error: null,
  success: false,
};

export function FollowButton({
  targetUserId,
  isFollowing,
  canManageFollows,
  className = "mt-6",
}: FollowButtonProps) {
  const router = useRouter();
  const [isConfirming, setIsConfirming] = useState(false);
  const [followState, followAction, isFollowingPending] = useActionState(
    followUser,
    initialState,
  );
  const [unfollowState, unfollowAction, isUnfollowingPending] = useActionState(
    unfollowUser,
    initialState,
  );

  useEffect(() => {
    if (followState.success || unfollowState.success) {
      router.refresh();
    }
  }, [followState.success, router, unfollowState.success]);

  const error = followState.error ?? unfollowState.error;
  const isPending = isFollowingPending || isUnfollowingPending;

  if (!canManageFollows) {
    return (
      <div className={className}>
        <p
          className="rounded-control bg-surface-muted px-4 py-3 text-sm leading-6 text-text-muted"
          role="status"
        >
          現在のアカウント状態ではフォローを変更できません。
        </p>
      </div>
    );
  }

  return (
    <div className={className}>
      {isFollowing ? (
        isConfirming ? (
          <div className="rounded-control bg-surface-muted/70 p-4">
            <p className="text-sm font-semibold text-text-primary">
              フォローを解除しますか？
            </p>
            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              <form action={unfollowAction}>
                <input
                  name="targetUserId"
                  type="hidden"
                  value={targetUserId}
                />
                <button
                  aria-disabled={isPending}
                  className="min-h-11 w-full rounded-control border border-danger bg-surface-elevated px-4 py-2.5 font-semibold text-danger transition hover:bg-red-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={isPending}
                  type="submit"
                >
                  {isUnfollowingPending ? "解除中…" : "解除する"}
                </button>
              </form>
              <button
                aria-disabled={isPending}
                className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-60"
                disabled={isPending}
                onClick={() => setIsConfirming(false)}
                type="button"
              >
                キャンセル
              </button>
            </div>
          </div>
        ) : (
          <button
            aria-pressed="true"
            className="min-h-11 w-full rounded-control bg-brand-soft px-5 py-2.5 font-semibold text-brand-primary-hover transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            onClick={() => setIsConfirming(true)}
            type="button"
          >
            フォロー中
          </button>
        )
      ) : (
        <form action={followAction}>
          <input name="targetUserId" type="hidden" value={targetUserId} />
          <button
            aria-disabled={isPending}
            aria-pressed="false"
            className="min-h-11 w-full rounded-control bg-brand-primary px-5 py-2.5 font-semibold text-white transition hover:bg-brand-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-control-disabled disabled:text-control-disabled-text"
            disabled={isPending}
            type="submit"
          >
            {isFollowingPending ? "フォロー中…" : "フォローする"}
          </button>
        </form>
      )}

      {error && (
        <p
          className="mt-3 rounded-control border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-danger"
          role="alert"
        >
          {error}
        </p>
      )}
    </div>
  );
}
