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
      <p
        className="mt-6 rounded-2xl bg-stone-100 px-4 py-3 text-sm leading-6 text-stone-600"
        role="status"
      >
        現在のアカウント状態ではフォローを変更できません。
      </p>
    );
  }

  return (
    <div className={className}>
      {isFollowing ? (
        isConfirming ? (
          <div className="rounded-2xl border border-stone-200 bg-stone-50 p-4">
            <p className="text-sm font-semibold text-stone-800">
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
                  className="w-full rounded-full border border-red-300 bg-white px-4 py-2.5 font-semibold text-red-700 transition hover:bg-red-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={isPending}
                  type="submit"
                >
                  {isUnfollowingPending ? "解除中…" : "解除する"}
                </button>
              </form>
              <button
                aria-disabled={isPending}
                className="w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-not-allowed disabled:opacity-60"
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
            className="w-full rounded-full border border-orange-300 bg-orange-50 px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
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
            className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-not-allowed disabled:opacity-60"
            disabled={isPending}
            type="submit"
          >
            {isFollowingPending ? "フォロー中…" : "フォローする"}
          </button>
        </form>
      )}

      {error && (
        <p
          className="mt-3 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          {error}
        </p>
      )}
    </div>
  );
}
