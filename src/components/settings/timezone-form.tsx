"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";

import {
  updateTimeZone,
  type TimeZoneActionState,
} from "@/app/(protected)/settings/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormSelect } from "@/components/ui/form-controls";

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
    <Button
      aria-disabled={pending}
      className="w-full sm:w-auto sm:min-w-36"
      disabled={pending}
      type="submit"
      variant="primary"
    >
      {pending ? "保存中…" : "保存する"}
    </Button>
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
      <div>
        <label
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor="account-timezone"
        >
          タイムゾーン
        </label>
        <FormSelect
          aria-describedby="account-timezone-help"
          className="min-w-0"
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
        </FormSelect>
        <p
          className="mt-2 break-words text-xs leading-5 text-text-muted [overflow-wrap:anywhere]"
          id="account-timezone-help"
        >
          カレンダーなどの日付表示に使用します。現在の設定: {currentTimeZone}
        </p>
      </div>

      <div className="flex justify-end">
        <SaveButton />
      </div>

      {state.message && (
        <FeedbackPanel
          aria-live="polite"
          role={state.status === "success" ? "status" : "alert"}
          variant={state.status === "success" ? "success" : "error"}
        >
          {state.message}
        </FeedbackPanel>
      )}
    </form>
  );
}
