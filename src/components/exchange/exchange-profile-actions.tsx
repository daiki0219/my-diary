"use client";

import {
  useActionState,
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import {
  blockExchangeInvitationsFromUser,
  createExchangeInvitation,
  type ExchangeActionState,
  unblockExchangeInvitationsFromUser,
} from "@/app/(protected)/exchange/actions";
import { ActionLink, Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";

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
  const displayUsername = targetUsername.trim() || "このユーザー";
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
      className="rounded-card border border-border-subtle bg-surface-muted/45 p-5 sm:p-6"
    >
      <div className="min-w-0">
        <p className="text-xs font-semibold tracking-wide text-brand-primary-hover">
          ふたりの日記
        </p>
        <h2
          className="mt-1 font-brand text-xl font-medium tracking-wide text-text-primary"
          id="exchange-profile-heading"
        >
          交換日記
        </h2>
      </div>

      {!canManageExchange ? (
        <FeedbackPanel className="mt-4" role="alert" variant="error">
          交換日記の操作を現在読み込めません。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      ) : (
        <>
          <div className="mt-4">
            {pendingDirection === "sent" ? (
              <div className="rounded-control bg-surface-elevated/80 px-4 py-4">
                <p className="text-xs font-semibold text-text-muted">
                  現在の招待
                </p>
                <p className="mt-1 text-sm font-semibold leading-6 text-text-primary">
                  招待を送りました。
                </p>
                <p className="mt-1 text-sm leading-6 text-text-muted">
                  相手からの返事を待っています。
                </p>
                <ActionLink
                  className="mt-3 w-full sm:w-auto"
                  href="/exchange?view=invitations"
                  variant="secondary"
                >
                  招待を確認する
                </ActionLink>
              </div>
            ) : pendingDirection === "received" ? (
              <div className="rounded-control bg-brand-soft/70 px-4 py-4">
                <p className="text-xs font-semibold text-brand-primary-hover">
                  招待が届いています
                </p>
                <p className="mt-1 text-sm font-semibold leading-6 text-text-primary">
                  この人から交換日記の招待が届いています。
                </p>
                <p className="mt-1 text-sm leading-6 text-text-muted">
                  招待一覧で内容を確認できます。
                </p>
                <ActionLink
                  className="mt-3 w-full sm:w-auto"
                  href="/exchange?view=invitations"
                  variant="primary"
                >
                  招待を見る
                </ActionLink>
              </div>
            ) : isMutualFollowing ? (
              <div>
                <p className="text-sm font-semibold leading-6 text-text-primary">
                  この人と2人で交換日記を始められます。
                </p>
                <p className="mt-1 text-sm leading-6 text-text-muted">
                  招待が承認されると、2人だけの日記が始まります。
                </p>
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
                  <Button
                    aria-disabled={isPending}
                    className="w-full sm:w-auto"
                    disabled={isPending}
                    type="submit"
                    variant="primary"
                  >
                    {isCreating ? "招待中…" : "交換日記に招待する"}
                  </Button>
                </form>
              </div>
            ) : (
              <p className="text-sm leading-6 text-text-muted">
                交換日記は相互フォローの相手と始められます。
              </p>
            )}
          </div>

          <div className="mt-6 border-t border-border-subtle pt-5">
            <p className="text-xs font-semibold tracking-wide text-text-muted">
              招待の受け取り設定
            </p>

            {isBlockingInvitations ? (
              <div className="mt-2">
                <p className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]">
                  この人からの交換日記の招待は受け取らない設定です。
                </p>
                <p className="mt-1 text-xs leading-5 text-text-muted">
                  交換日記の招待だけに影響します。フォローやプロフィール、通常の日記には影響しません。
                </p>
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
                  <Button
                    aria-disabled={isPending}
                    className="w-full sm:w-auto"
                    disabled={isPending}
                    type="submit"
                    variant="neutral"
                  >
                    {isUnblocking
                      ? "設定中…"
                      : "交換日記の招待を受け取れるようにする"}
                  </Button>
                </form>
              </div>
            ) : isConfirmingBlock ? (
              <div
                aria-labelledby={`${confirmationId}-title`}
                className="mt-3 rounded-control border border-danger/20 bg-danger/5 p-4"
                id={confirmationId}
                onKeyDown={(event) => {
                  if (event.key === "Escape" && !isPending) {
                    closeBlockConfirmation();
                  }
                }}
                role="group"
              >
                <p
                  className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]"
                  id={`${confirmationId}-title`}
                >
                  {displayUsername}さんからの交換日記の招待を受け取らない設定にしますか？
                </p>
                <p className="mt-2 text-xs leading-5 text-text-secondary">
                  この設定は交換日記の招待だけに影響し、フォローやプロフィール、通常の日記には影響しません。設定はあとから解除できます。
                </p>
                <p className="mt-2 text-xs leading-5 text-text-secondary">
                  この人から届いている招待がある場合は拒否されます。その場合、設定を解除しても、お互いに24時間は新しい招待を送れません。
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
                      className="min-h-11 w-full rounded-control bg-danger px-4 py-2.5 font-semibold text-white transition hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
                      disabled={isPending}
                      ref={blockSubmitRef}
                      type="submit"
                    >
                      {isBlocking ? "設定中…" : "受け取らない設定にする"}
                    </button>
                  </form>
                  <button
                    aria-disabled={isPending}
                    className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:opacity-60"
                    disabled={isPending}
                    onClick={closeBlockConfirmation}
                    type="button"
                  >
                    キャンセル
                  </button>
                </div>
              </div>
            ) : (
              <div className="mt-2">
                <p className="text-sm leading-6 text-text-muted">
                  必要なときは、この人からの交換日記の招待だけを受け取らないようにできます。
                </p>
                <button
                  aria-controls={confirmationId}
                  aria-disabled={isPending}
                  aria-expanded={isConfirmingBlock}
                  className="-ml-3 mt-2 inline-flex min-h-11 max-w-full items-center rounded-control px-3 py-2.5 text-left text-sm font-semibold leading-6 text-danger transition hover:bg-danger/5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:opacity-60"
                  disabled={isPending}
                  onClick={() => setIsConfirmingBlock(true)}
                  ref={blockTriggerRef}
                  type="button"
                >
                  この人からの交換日記の招待を受け取らない
                </button>
              </div>
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
        <FeedbackPanel
          className="mt-4"
          key={`${lastAction}:${actionState.revision}`}
          role="alert"
          variant="error"
        >
          {actionState.error}
        </FeedbackPanel>
      )}
      {actionState.completed && actionState.message && (
        <FeedbackPanel
          aria-live="polite"
          className="mt-4"
          key={`${lastAction}:${actionState.revision}`}
          role="status"
          variant="success"
        >
          {actionState.message}
        </FeedbackPanel>
      )}
    </section>
  );
}
