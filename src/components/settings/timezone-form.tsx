"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";

import {
  updateTimeZone,
  type TimeZoneActionState,
} from "@/app/(protected)/settings/actions";

type TimeZoneFormProps = {
  currentTimeZone: string;
  timeZoneOptions: string[];
};

const initialState: TimeZoneActionState = {
  status: "idle",
  message: null,
  revision: 0,
};

function SaveButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400 sm:w-auto sm:min-w-36"
      disabled={pending}
      type="submit"
    >
      {pending ? "保存中…" : "保存する"}
    </button>
  );
}

export function TimeZoneForm({
  currentTimeZone,
  timeZoneOptions,
}: TimeZoneFormProps) {
  const router = useRouter();
  const [state, formAction] = useActionState(updateTimeZone, initialState);

  useEffect(() => {
    if (state.status === "success") {
      router.refresh();
    }
  }, [router, state.revision, state.status]);

  return (
    <form action={formAction} className="space-y-6">
      {state.message && (
        <p
          aria-live="polite"
          className={`rounded-2xl border px-4 py-3 text-sm leading-6 ${
            state.status === "success"
              ? "border-green-200 bg-green-50 text-green-800"
              : "border-red-200 bg-red-50 text-red-700"
          }`}
          role={state.status === "success" ? "status" : "alert"}
        >
          {state.message}
        </p>
      )}

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="account-timezone"
        >
          タイムゾーン
        </label>
        <select
          aria-describedby="account-timezone-help"
          className="w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          defaultValue={currentTimeZone}
          id="account-timezone"
          key={currentTimeZone}
          name="timezone"
          required
        >
          {timeZoneOptions.map((timezone) => (
            <option key={timezone} value={timezone}>
              {timezone}
            </option>
          ))}
        </select>
        <p
          className="mt-2 break-words text-xs leading-5 text-stone-500 [overflow-wrap:anywhere]"
          id="account-timezone-help"
        >
          カレンダーなどの日付表示に使用します。現在の設定: {currentTimeZone}
        </p>
      </div>

      <div className="flex justify-end">
        <SaveButton />
      </div>
    </form>
  );
}
