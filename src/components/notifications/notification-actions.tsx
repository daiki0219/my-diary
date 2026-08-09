"use client";

import { useActionState, useEffect } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";

import {
  markAllNotificationsRead,
  markNotificationRead,
  openNotification,
  type NotificationActionState,
} from "@/app/(protected)/notifications/actions";

const initialState: NotificationActionState = {
  error: null,
  completed: false,
  unavailable: false,
  revision: 0,
};

function OpenButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="min-h-10 rounded-full bg-orange-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400"
      disabled={pending}
      type="submit"
    >
      {pending ? "開いています…" : "通知を開く"}
    </button>
  );
}

function ReadButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="min-h-10 rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:text-stone-400"
      disabled={pending}
      type="submit"
    >
      {pending ? "更新中…" : "既読にする"}
    </button>
  );
}

function MarkAllButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="min-h-11 w-full rounded-full border border-orange-300 bg-white px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:border-stone-200 disabled:text-stone-400 sm:w-auto"
      disabled={pending}
      type="submit"
    >
      {pending ? "既読にしています…" : "すべて既読"}
    </button>
  );
}

function ActionMessage({ state }: { state: NotificationActionState }) {
  if (state.error) {
    return (
      <p
        className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
        role="alert"
      >
        {state.error}
      </p>
    );
  }

  if (state.unavailable) {
    return (
      <p
        className="mt-3 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2 text-sm leading-6 text-stone-700"
        role="alert"
      >
        この通知の対象は現在表示できません。通知は既読にしました。
      </p>
    );
  }

  return null;
}

export function NotificationOpenAction({
  notificationId,
}: {
  notificationId: string;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(openNotification, initialState);

  useEffect(() => {
    if (state.completed) {
      router.refresh();
    }
  }, [router, state.completed, state.revision]);

  return (
    <form action={formAction}>
      <input name="notificationId" type="hidden" value={notificationId} />
      <OpenButton />
      <ActionMessage state={state} />
    </form>
  );
}

export function NotificationReadAction({
  notificationId,
}: {
  notificationId: string;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(
    markNotificationRead,
    initialState,
  );

  useEffect(() => {
    if (state.completed) {
      router.refresh();
    }
  }, [router, state.completed, state.revision]);

  return (
    <form action={formAction}>
      <input name="notificationId" type="hidden" value={notificationId} />
      <ReadButton />
      <ActionMessage state={state} />
    </form>
  );
}

export function MarkAllNotificationsReadAction() {
  const router = useRouter();
  const [state, formAction] = useActionState(
    markAllNotificationsRead,
    initialState,
  );

  useEffect(() => {
    if (state.completed) {
      router.refresh();
    }
  }, [router, state.completed, state.revision]);

  return (
    <form action={formAction}>
      <MarkAllButton />
      <ActionMessage state={state} />
    </form>
  );
}
