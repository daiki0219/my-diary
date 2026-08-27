"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useRef } from "react";

import {
  updateExchangeNotificationPreference,
  type ExchangeNotificationPreferenceActionState,
} from "@/app/(protected)/settings/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";

export function ExchangeNotificationPreferenceForm({
  currentNewEntryEnabled,
  currentUpdatedAt,
}: {
  currentNewEntryEnabled: boolean;
  currentUpdatedAt: string;
}) {
  const router = useRouter();
  const submissionInFlight = useRef(false);
  const checkboxRef = useRef<HTMLInputElement>(null);
  const hiddenInputRef = useRef<HTMLInputElement>(null);
  const lastServerVersionRef = useRef(currentUpdatedAt);
  const refreshedRevisionRef = useRef(0);
  const initialState: ExchangeNotificationPreferenceActionState = {
    status: "idle",
    message: null,
    confirmedNewEntryEnabled: currentNewEntryEnabled,
    revision: 0,
  };
  const [state, formAction, isPending] = useActionState(
    updateExchangeNotificationPreference,
    initialState,
  );

  useEffect(() => {
    const serverVersionChanged =
      lastServerVersionRef.current !== currentUpdatedAt;
    lastServerVersionRef.current = currentUpdatedAt;
    const confirmedValue =
      !serverVersionChanged &&
      state.revision > 0 &&
      state.confirmedNewEntryEnabled !== null
        ? state.confirmedNewEntryEnabled
        : currentNewEntryEnabled;

    if (checkboxRef.current) {
      checkboxRef.current.checked = confirmedValue;
    }

    if (hiddenInputRef.current) {
      hiddenInputRef.current.value = String(confirmedValue);
    }
  }, [
    currentNewEntryEnabled,
    currentUpdatedAt,
    state.confirmedNewEntryEnabled,
    state.revision,
  ]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }

    if (
      !isPending &&
      state.revision > refreshedRevisionRef.current
    ) {
      refreshedRevisionRef.current = state.revision;
      router.refresh();
    }
  }, [isPending, router, state.revision]);

  return (
    <form
      action={formAction}
      className="space-y-6"
      onSubmit={(event) => {
        if (submissionInFlight.current) {
          event.preventDefault();
          return;
        }

        submissionInFlight.current = true;
      }}
    >
      <fieldset className="space-y-6" disabled={isPending}>
        <input
          defaultValue={String(currentNewEntryEnabled)}
          name="newEntryEnabled"
          ref={hiddenInputRef}
          type="hidden"
        />

        <div className="min-w-0">
          <label
            className="flex min-h-11 min-w-0 cursor-pointer items-start gap-3 rounded-control focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus"
            htmlFor="exchange-new-entry-notifications"
          >
            <input
              aria-describedby="exchange-new-entry-notifications-help"
              aria-disabled={isPending}
              className="mt-1 size-5 shrink-0 accent-brand-primary disabled:cursor-wait"
              defaultChecked={currentNewEntryEnabled}
              id="exchange-new-entry-notifications"
              onChange={(event) => {
                if (hiddenInputRef.current) {
                  hiddenInputRef.current.value = String(
                    event.currentTarget.checked,
                  );
                }
              }}
              ref={checkboxRef}
              type="checkbox"
            />
            <span className="min-w-0 break-words text-sm font-medium leading-6 text-text-primary [overflow-wrap:anywhere]">
              交換日記に新しい日記が追加されたとき、アプリ内で通知する
            </span>
          </label>
          <p
            className="mt-2 break-words text-xs leading-5 text-text-muted [overflow-wrap:anywhere]"
            id="exchange-new-entry-notifications-help"
          >
            招待・承認の通知はこの設定の対象外です。すでに届いた通知は残ります。
          </p>
        </div>

        <div className="flex justify-end">
          <Button
            aria-disabled={isPending}
            className="w-full sm:w-auto sm:min-w-36"
            disabled={isPending}
            type="submit"
            variant="primary"
          >
            {isPending ? "保存中…" : "保存する"}
          </Button>
        </div>
      </fieldset>

      <p aria-live="polite" className="sr-only">
        {isPending ? "交換日記の通知設定を保存しています" : ""}
      </p>

      {state.message && (
        <FeedbackPanel
          aria-live="polite"
          key={state.revision}
          role={state.status === "success" ? "status" : "alert"}
          variant={state.status === "success" ? "success" : "error"}
        >
          {state.message}
        </FeedbackPanel>
      )}
    </form>
  );
}
