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
      className="rounded-card bg-surface-muted/55 p-5 sm:p-6"
    >
      <h2
        className="font-brand text-xl font-medium tracking-wide text-text-primary"
        id="exchange-profile-heading"
      >
        交換日記
      </h2>

      {!canManageExchange ? (
        <p
          className="mt-3 rounded-control border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-danger"
          role="alert"
        >
          交換日記の操作を現在読み込めません。時間をおいてもう一度お試しください。
        </p>
      ) : (
        <>
          {pendingDirection === "sent" ? (
            <div className="mt-3">
              <p className="text-sm font-semibold leading-6 text-text-primary">
                承認待ちです。
              </p>
              <Link
                className="mt-2 inline-flex min-h-11 items-center rounded-control text-sm font-semibold text-brand-primary-hover underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-focus"
                href="/exchange?view=invitations"
              >
                交換日記の招待一覧を見る
              </Link>
            </div>
          ) : pendingDirection === "received" ? (
            <div className="mt-3">
              <p className="text-sm font-semibold leading-6 text-text-primary">
                交換日記の招待が届いています。
              </p>
              <Link
                className="mt-2 inline-flex min-h-11 items-center rounded-control text-sm font-semibold text-brand-primary-hover underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-focus"
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
                className="min-h-11 w-full rounded-control bg-brand-primary px-5 py-2.5 font-semibold text-white transition hover:bg-brand-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text sm:w-auto"
                disabled={isPending}
                type="submit"
              >
                {isCreating ? "招待中…" : "交換日記に招待"}
              </button>
            </form>
          ) : (
            <p className="mt-3 text-sm leading-6 text-text-muted">
              お互いにフォローすると、交換日記へ招待できます。
            </p>
          )}

          <div className="mt-5 border-t border-border-subtle pt-4">
            <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <p className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]">
                  このユーザーから交換日記の招待を受け取らない
                </p>
                <p className="mt-1 text-xs leading-5 text-text-muted">
                  交換日記の招待だけの設定です。フォローなどSNS全体には影響しません。
                </p>
              </div>
              <span className="w-fit shrink-0 rounded-full bg-surface-elevated px-3 py-1 text-xs font-semibold text-text-secondary">
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
                  className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                  disabled={isPending}
                  type="submit"
                >
                  {isUnblocking ? "設定中…" : "OFFにする"}
                </button>
              </form>
            ) : isConfirmingBlock ? (
              <div
                className="mt-3 rounded-control border border-red-200 bg-red-50 p-4"
                id={confirmationId}
                onKeyDown={(event) => {
                  if (event.key === "Escape" && !isPending) {
                    closeBlockConfirmation();
                  }
                }}
              >
                <p className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]">
                  {targetUsername}さんからの交換日記の招待を受け取らない設定にしますか？
                </p>
                <p className="mt-1 text-xs leading-5 text-text-muted">
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
                      className="min-h-11 w-full rounded-control border border-danger bg-surface-elevated px-4 py-2.5 font-semibold text-danger transition hover:bg-red-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:opacity-60"
                      disabled={isPending}
                      ref={blockSubmitRef}
                      type="submit"
                    >
                      {isBlocking ? "設定中…" : "ONにする"}
                    </button>
                  </form>
                  <button
                    aria-disabled={isPending}
                    className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:opacity-60"
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
                className="mt-3 min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:opacity-60 sm:w-auto"
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
          className="mt-3 rounded-control border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-danger"
          key={`${lastAction}:${actionState.revision}`}
          role="alert"
        >
          {actionState.error}
        </p>
      )}
      {actionState.completed && actionState.message && (
        <p
          aria-live="polite"
          className="mt-3 rounded-control border border-green-200 bg-green-50 px-4 py-3 text-sm leading-6 text-success"
          key={`${lastAction}:${actionState.revision}`}
          role="status"
        >
          {actionState.message}
        </p>
      )}
    </section>
  );
}
