"use client";

import {
  useActionState,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";

import {
  acceptExchangeInvitation,
  cancelExchangeInvitation,
  type ExchangeActionState,
  rejectExchangeInvitation,
} from "@/app/(protected)/exchange/actions";

type ExchangeInvitationActionsProps = {
  invitationId: string;
  direction: "sent" | "received";
  counterpartName: string;
};

const initialState: ExchangeActionState = {
  error: null,
  completed: false,
  message: null,
  revision: 0,
};

function ActionError({ state }: { state: ExchangeActionState }) {
  if (!state.error) {
    return null;
  }

  return (
    <p
      className="mt-3 rounded-control border border-danger/20 bg-danger/5 px-4 py-3 text-sm leading-6 text-danger"
      key={state.revision}
      role="alert"
    >
      {state.error}
    </p>
  );
}

function ReceivedInvitationActions({
  invitationId,
  counterpartName,
}: Omit<ExchangeInvitationActionsProps, "direction">) {
  const confirmationId = useId();
  const rejectTriggerRef = useRef<HTMLButtonElement>(null);
  const rejectSubmitRef = useRef<HTMLButtonElement>(null);
  const [isConfirmingReject, setIsConfirmingReject] = useState(false);
  const [lastAction, setLastAction] = useState<"accept" | "reject" | null>(
    null,
  );
  const [acceptState, acceptAction, isAccepting] = useActionState(
    acceptExchangeInvitation,
    initialState,
  );
  const [rejectState, rejectAction, isRejecting] = useActionState(
    rejectExchangeInvitation,
    initialState,
  );
  const isPending = isAccepting || isRejecting;
  const actionState =
    lastAction === "accept"
      ? acceptState
      : lastAction === "reject"
        ? rejectState
        : initialState;

  useEffect(() => {
    if (isConfirmingReject) {
      rejectSubmitRef.current?.focus();
    }
  }, [isConfirmingReject]);

  function closeConfirmation() {
    setIsConfirmingReject(false);
    requestAnimationFrame(() => rejectTriggerRef.current?.focus());
  }

  return (
    <div className="mt-4">
      <p className="text-sm leading-6 text-text-secondary">
        承認すると、このユーザーとの交換日記が始まります。
      </p>

      {isConfirmingReject ? (
        <div
          className="mt-4 max-w-2xl rounded-control border border-danger/20 bg-danger/5 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
        >
          <p className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]">
            {counterpartName}さんからの招待を拒否しますか？
          </p>
          <p className="mt-1 text-xs leading-5 text-text-secondary">
            拒否後24時間は、お互いに新しい招待を送れません。
          </p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <form
              action={rejectAction}
              onSubmit={() => setLastAction("reject")}
            >
              <input
                name="invitationId"
                type="hidden"
                value={invitationId}
              />
              <button
                aria-label={`${counterpartName}さんからの招待を拒否する`}
                aria-disabled={isPending}
                className="min-h-11 w-full rounded-control border border-danger/30 bg-surface-elevated px-4 py-2.5 font-semibold text-danger transition hover:bg-danger/10 disabled:cursor-wait disabled:opacity-60"
                disabled={isPending}
                ref={rejectSubmitRef}
                type="submit"
              >
                {isRejecting ? "拒否中…" : "拒否する"}
              </button>
            </form>
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface-muted hover:text-text-primary disabled:cursor-wait disabled:opacity-60"
              disabled={isPending}
              onClick={closeConfirmation}
              type="button"
            >
              確認をやめる
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-4 flex min-w-0 flex-col gap-2 sm:flex-row sm:flex-wrap">
          <form
            action={acceptAction}
            className="w-full sm:w-auto"
            onSubmit={() => setLastAction("accept")}
          >
            <input
              name="invitationId"
              type="hidden"
              value={invitationId}
            />
            <button
              aria-label={`${counterpartName}さんからの招待を承認する`}
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-control bg-brand-primary px-5 py-2.5 font-semibold text-white transition hover:bg-brand-primary-hover disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text sm:min-w-32"
              disabled={isPending}
              type="submit"
            >
              {isAccepting ? "承認中…" : "承認する"}
            </button>
          </form>
          <button
            aria-label={`${counterpartName}さんからの招待を拒否する`}
            aria-controls={confirmationId}
            aria-disabled={isPending}
            aria-expanded={isConfirmingReject}
            className="min-h-11 w-full rounded-control border border-danger/30 bg-transparent px-4 py-2.5 font-semibold text-danger transition hover:bg-danger/5 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
            disabled={isPending}
            onClick={() => setIsConfirmingReject(true)}
            ref={rejectTriggerRef}
            type="button"
          >
            拒否
          </button>
        </div>
      )}

      <p aria-live="polite" className="sr-only">
        {isAccepting ? "招待を承認しています" : isRejecting ? "招待を拒否しています" : ""}
      </p>
      <ActionError key={lastAction ?? "none"} state={actionState} />
    </div>
  );
}

function SentInvitationActions({
  invitationId,
  counterpartName,
}: Omit<ExchangeInvitationActionsProps, "direction">) {
  const confirmationId = useId();
  const cancelTriggerRef = useRef<HTMLButtonElement>(null);
  const cancelSubmitRef = useRef<HTMLButtonElement>(null);
  const [isConfirmingCancel, setIsConfirmingCancel] = useState(false);
  const [cancelState, cancelAction, isCancelling] = useActionState(
    cancelExchangeInvitation,
    initialState,
  );

  useEffect(() => {
    if (isConfirmingCancel) {
      cancelSubmitRef.current?.focus();
    }
  }, [isConfirmingCancel]);

  function closeConfirmation() {
    setIsConfirmingCancel(false);
    requestAnimationFrame(() => cancelTriggerRef.current?.focus());
  }

  return (
    <div className="mt-4">
      {isConfirmingCancel ? (
        <div
          className="max-w-2xl rounded-control border border-danger/20 bg-danger/5 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isCancelling) {
              closeConfirmation();
            }
          }}
        >
          <p className="break-words text-sm font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]">
            {counterpartName}さんへの招待を取り消しますか？
          </p>
          <p className="mt-1 text-xs leading-5 text-text-secondary">
            取消後24時間は、お互いに新しい招待を送れません。
          </p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <form action={cancelAction}>
              <input
                name="invitationId"
                type="hidden"
                value={invitationId}
              />
              <button
                aria-label={`${counterpartName}さんへの招待を取り消す`}
                aria-disabled={isCancelling}
                className="min-h-11 w-full rounded-control border border-danger/30 bg-surface-elevated px-4 py-2.5 font-semibold text-danger transition hover:bg-danger/10 disabled:cursor-wait disabled:opacity-60"
                disabled={isCancelling}
                ref={cancelSubmitRef}
                type="submit"
              >
                {isCancelling ? "取消中…" : "取り消す"}
              </button>
            </form>
            <button
              aria-disabled={isCancelling}
              className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface-muted hover:text-text-primary disabled:cursor-wait disabled:opacity-60"
              disabled={isCancelling}
              onClick={closeConfirmation}
              type="button"
            >
              確認をやめる
            </button>
          </div>
        </div>
      ) : (
        <button
          aria-label={`${counterpartName}さんへの招待を取り消す`}
          aria-controls={confirmationId}
          aria-disabled={isCancelling}
          aria-expanded={isConfirmingCancel}
          className="min-h-11 w-full rounded-control border border-danger/30 bg-transparent px-4 py-2.5 font-semibold text-danger transition hover:bg-danger/5 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
          disabled={isCancelling}
          onClick={() => setIsConfirmingCancel(true)}
          ref={cancelTriggerRef}
          type="button"
        >
          招待を取り消す
        </button>
      )}

      <p aria-live="polite" className="sr-only">
        {isCancelling ? "招待を取り消しています" : ""}
      </p>
      <ActionError state={cancelState} />
    </div>
  );
}

export function ExchangeInvitationActions(
  props: ExchangeInvitationActionsProps,
) {
  return props.direction === "received" ? (
    <ReceivedInvitationActions
      counterpartName={props.counterpartName}
      invitationId={props.invitationId}
    />
  ) : (
    <SentInvitationActions
      counterpartName={props.counterpartName}
      invitationId={props.invitationId}
    />
  );
}
