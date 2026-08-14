"use client";

import {
  useActionState,
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import {
  blockExchangeInvitationsFromUser,
  createExchangeInvitation,
  type ExchangeActionState,
  unblockExchangeInvitationsFromUser,
} from "@/app/(protected)/exchange/actions";

type ExchangeProfileActionsProps = {
  targetUserId: string;
  targetUsername: string;
  canManageExchange: boolean;
  isMutualFollowing: boolean;
  pendingDirection: "sent" | "received" | null;
  isBlockingInvitations: boolean;
};

const initialState: ExchangeActionState = {
  error: null,
  completed: false,
  message: null,
  revision: 0,
};

export function ExchangeProfileActions({
  targetUserId,
  targetUsername,
  canManageExchange,
  isMutualFollowing,
  pendingDirection,
  isBlockingInvitations,
}: ExchangeProfileActionsProps) {
  const router = useRouter();
  const confirmationId = useId();
  const blockTriggerRef = useRef<HTMLButtonElement>(null);
  const blockSubmitRef = useRef<HTMLButtonElement>(null);
  const [isConfirmingBlock, setIsConfirmingBlock] = useState(false);
  const [lastAction, setLastAction] = useState<
    "create" | "block" | "unblock" | null
  >(null);
  const runBlockAction = useCallback(
    async (
      previousState: ExchangeActionState,
      formData: FormData,
    ) => {
      const nextState = await blockExchangeInvitationsFromUser(
        previousState,
        formData,
      );

      if (nextState.completed) {
        setIsConfirmingBlock(false);
      }

      return nextState;
    },
    [],
  );
  const [createState, createAction, isCreating] = useActionState(
    createExchangeInvitation,
    initialState,
  );
  const [blockState, blockAction, isBlocking] = useActionState(
    runBlockAction,
    initialState,
  );
  const [unblockState, unblockAction, isUnblocking] = useActionState(
    unblockExchangeInvitationsFromUser,
    initialState,
  );
  const isPending = isCreating || isBlocking || isUnblocking;
  const actionState =
    lastAction === "create"
      ? createState
      : lastAction === "block"
        ? blockState
        : lastAction === "unblock"
          ? unblockState
          : initialState;

  useEffect(() => {
    if (blockState.completed || unblockState.completed) {
      router.refresh();
    }
  }, [
    blockState.completed,
    blockState.revision,
    router,
    unblockState.completed,
    unblockState.revision,
  ]);

  useEffect(() => {
    if (isConfirmingBlock) {
      blockSubmitRef.current?.focus();
    }
  }, [isConfirmingBlock]);

  function closeBlockConfirmation() {
    setIsConfirmingBlock(false);
    requestAnimationFrame(() => blockTriggerRef.current?.focus());
  }

  return (
    <section
      aria-labelledby="exchange-profile-heading"
      className="mt-6 rounded-2xl border border-orange-200 bg-orange-50/60 p-4"
    >
      <h2
        className="text-lg font-bold text-stone-800"
        id="exchange-profile-heading"
      >
        交換日記
      </h2>

      {!canManageExchange ? (
        <p
          className="mt-3 rounded-xl border border-stone-200 bg-white px-3 py-2 text-sm leading-6 text-stone-600"
          role="alert"
        >
          交換日記の操作を現在読み込めません。時間をおいてもう一度お試しください。
        </p>
      ) : (
        <>
          {pendingDirection === "sent" ? (
            <div className="mt-3">
              <p className="text-sm font-semibold leading-6 text-stone-800">
                承認待ちです。
              </p>
              <Link
                className="mt-2 inline-flex min-h-10 items-center rounded-lg text-sm font-semibold text-orange-800 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
                href="/exchange?view=invitations"
              >
                交換日記の招待一覧を見る
              </Link>
            </div>
          ) : pendingDirection === "received" ? (
            <div className="mt-3">
              <p className="text-sm font-semibold leading-6 text-stone-800">
                交換日記の招待が届いています。
              </p>
              <Link
                className="mt-2 inline-flex min-h-10 items-center rounded-lg text-sm font-semibold text-orange-800 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
                href="/exchange?view=invitations"
              >
                交換日記の招待一覧を見る
              </Link>
            </div>
          ) : isMutualFollowing ? (
            <form
              action={createAction}
              className="mt-4"
              onSubmit={() => setLastAction("create")}
            >
              <input
                name="targetUserId"
                type="hidden"
                value={targetUserId}
              />
              <button
                aria-disabled={isPending}
                className="min-h-11 w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400"
                disabled={isPending}
                type="submit"
              >
                {isCreating ? "招待中…" : "交換日記に招待"}
              </button>
            </form>
          ) : (
            <p className="mt-3 text-sm leading-6 text-stone-600">
              お互いにフォローすると、交換日記へ招待できます。
            </p>
          )}

          <div className="mt-5 border-t border-orange-200 pt-4">
            <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <p className="break-words text-sm font-semibold leading-6 text-stone-800 [overflow-wrap:anywhere]">
                  このユーザーから交換日記の招待を受け取らない
                </p>
                <p className="mt-1 text-xs leading-5 text-stone-600">
                  交換日記の招待だけの設定です。フォローなどSNS全体には影響しません。
                </p>
              </div>
              <span className="w-fit shrink-0 rounded-full bg-white px-3 py-1 text-xs font-bold text-stone-700">
                {isBlockingInvitations ? "ON" : "OFF"}
              </span>
            </div>

            {isBlockingInvitations ? (
              <form
                action={unblockAction}
                className="mt-3"
                onSubmit={() => setLastAction("unblock")}
              >
                <input
                  name="targetUserId"
                  type="hidden"
                  value={targetUserId}
                />
                <button
                  aria-disabled={isPending}
                  className="min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                  disabled={isPending}
                  type="submit"
                >
                  {isUnblocking ? "設定中…" : "OFFにする"}
                </button>
              </form>
            ) : isConfirmingBlock ? (
              <div
                className="mt-3 rounded-2xl border border-red-200 bg-red-50 p-4"
                id={confirmationId}
                onKeyDown={(event) => {
                  if (event.key === "Escape" && !isPending) {
                    closeBlockConfirmation();
                  }
                }}
              >
                <p className="break-words text-sm font-semibold leading-6 text-stone-800 [overflow-wrap:anywhere]">
                  {targetUsername}さんからの交換日記の招待を受け取らない設定にしますか？
                </p>
                <p className="mt-1 text-xs leading-5 text-stone-600">
                  このユーザーから届いている招待がある場合、招待一覧から表示されなくなります。
                </p>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  <form
                    action={blockAction}
                    onSubmit={() => setLastAction("block")}
                  >
                    <input
                      name="targetUserId"
                      type="hidden"
                      value={targetUserId}
                    />
                    <button
                      aria-disabled={isPending}
                      className="min-h-11 w-full rounded-full border border-red-300 bg-white px-4 py-2.5 font-semibold text-red-700 transition hover:bg-red-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 disabled:cursor-wait disabled:opacity-60"
                      disabled={isPending}
                      ref={blockSubmitRef}
                      type="submit"
                    >
                      {isBlocking ? "設定中…" : "ONにする"}
                    </button>
                  </form>
                  <button
                    aria-disabled={isPending}
                    className="min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60"
                    disabled={isPending}
                    onClick={closeBlockConfirmation}
                    type="button"
                  >
                    確認をやめる
                  </button>
                </div>
              </div>
            ) : (
              <button
                aria-controls={confirmationId}
                aria-disabled={isPending}
                aria-expanded={isConfirmingBlock}
                className="mt-3 min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                disabled={isPending}
                onClick={() => setIsConfirmingBlock(true)}
                ref={blockTriggerRef}
                type="button"
              >
                ONにする
              </button>
            )}
          </div>
        </>
      )}

      <p aria-live="polite" className="sr-only">
        {isCreating
          ? "交換日記へ招待しています"
          : isBlocking || isUnblocking
            ? "招待の受信設定を更新しています"
            : ""}
      </p>

      {actionState.error && (
        <p
          className="mt-3 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          key={`${lastAction}:${actionState.revision}`}
          role="alert"
        >
          {actionState.error}
        </p>
      )}
      {actionState.completed && actionState.message && (
        <p
          aria-live="polite"
          className="mt-3 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm leading-6 text-green-800"
          key={`${lastAction}:${actionState.revision}`}
          role="status"
        >
          {actionState.message}
        </p>
      )}
    </section>
  );
}
