"use client";

import { useRouter } from "next/navigation";
import {
  startTransition,
  useActionState,
  useEffect,
  useRef,
} from "react";

import {
  updateExchangeDiaryNotificationSetting,
  type ExchangeDiaryNotificationActionState,
} from "@/app/(protected)/exchange/actions";

export function ExchangeDiaryNotificationForm({
  diaryId,
  initialReceiveNewEntryNotifications,
  initialUpdatedAt,
}: {
  diaryId: string;
  initialReceiveNewEntryNotifications: boolean;
  initialUpdatedAt: string;
}) {
  const router = useRouter();
  const submissionInFlight = useRef(false);
  const checkboxRef = useRef<HTMLInputElement>(null);
  const lastServerVersionRef = useRef(initialUpdatedAt);
  const refreshedRevisionRef = useRef(0);
  const initialState: ExchangeDiaryNotificationActionState = {
    status: "idle",
    message: null,
    confirmedReceiveNewEntryNotifications:
      initialReceiveNewEntryNotifications,
    revision: 0,
  };
  const [state, formAction, isPending] = useActionState(
    updateExchangeDiaryNotificationSetting,
    initialState,
  );

  useEffect(() => {
    const serverVersionChanged =
      lastServerVersionRef.current !== initialUpdatedAt;
    lastServerVersionRef.current = initialUpdatedAt;
    const confirmedValue =
      !serverVersionChanged &&
      state.revision > 0 &&
      state.confirmedReceiveNewEntryNotifications !== null
        ? state.confirmedReceiveNewEntryNotifications
        : initialReceiveNewEntryNotifications;

    if (checkboxRef.current) {
      checkboxRef.current.checked = confirmedValue;
    }
  }, [
    initialReceiveNewEntryNotifications,
    initialUpdatedAt,
    state.confirmedReceiveNewEntryNotifications,
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
  }, [
    isPending,
    router,
    state.revision,
  ]);

  return (
    <form
      className="min-w-0"
      onSubmit={(event) => event.preventDefault()}
    >
      <label
        className="flex min-h-11 min-w-0 cursor-pointer items-start gap-3 rounded-2xl focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-orange-600"
        htmlFor="exchange-diary-new-entry-notifications"
      >
        <input
          aria-describedby="exchange-diary-new-entry-notifications-help"
          aria-disabled={isPending}
          className="mt-1 size-5 shrink-0 accent-orange-600 disabled:cursor-wait"
          defaultChecked={initialReceiveNewEntryNotifications}
          disabled={isPending}
          id="exchange-diary-new-entry-notifications"
          onChange={(event) => {
            if (submissionInFlight.current) {
              event.preventDefault();
              return;
            }

            const nextValue = event.currentTarget.checked;
            const formData = new FormData();
            formData.set("diaryId", diaryId);
            formData.set(
              "receiveNewEntryNotifications",
              String(nextValue),
            );
            submissionInFlight.current = true;
            startTransition(() => formAction(formData));
          }}
          ref={checkboxRef}
          type="checkbox"
        />
        <span className="min-w-0 break-words text-sm font-semibold leading-6 text-stone-800 [overflow-wrap:anywhere]">
          この交換日記に新しい日記が追加されたとき、アプリ内で通知する
        </span>
      </label>

      <p
        className="mt-2 break-words text-xs leading-5 text-stone-500 [overflow-wrap:anywhere]"
        id="exchange-diary-new-entry-notifications-help"
      >
        この交換日記だけに反映されます。全体設定がOFFの場合は通知されません。
      </p>

      <p aria-live="polite" className="sr-only">
        {isPending ? "この交換日記の通知設定を保存しています" : ""}
      </p>

      {state.message && (
        <p
          className={`mt-3 rounded-xl border px-3 py-2 text-sm leading-6 ${
            state.status === "success"
              ? "border-emerald-200 bg-emerald-50 text-emerald-700"
              : "border-red-200 bg-red-50 text-red-700"
          }`}
          key={state.revision}
          role={state.status === "success" ? "status" : "alert"}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
