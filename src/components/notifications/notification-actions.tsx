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
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";

const initialState: NotificationActionState = {
  error: null,
  completed: false,
  unavailable: false,
  revision: 0,
};

function OpenButton({ notificationLabel }: { notificationLabel: string }) {
  const { pending } = useFormStatus();

  return (
    <Button
      aria-disabled={pending}
      className="px-3 text-sm text-brand-primary-hover hover:bg-brand-soft/60"
      disabled={pending}
      type="submit"
      variant="quiet"
    >
      <span className="sr-only">{notificationLabel}: </span>
      {pending ? "開いています…" : "通知を開く"}
    </Button>
  );
}

function ReadButton({ notificationLabel }: { notificationLabel: string }) {
  const { pending } = useFormStatus();

  return (
    <Button
      aria-disabled={pending}
      className="px-3 text-sm"
      disabled={pending}
      type="submit"
      variant="quiet"
    >
      <span className="sr-only">{notificationLabel}: </span>
      {pending ? "更新中…" : "既読にする"}
    </Button>
  );
}

function MarkAllButton() {
  const { pending } = useFormStatus();

  return (
    <Button
      aria-disabled={pending}
      className="px-3 text-sm text-brand-primary-hover hover:bg-brand-soft/60"
      disabled={pending}
      type="submit"
      variant="quiet"
    >
      {pending ? "既読にしています…" : "すべて既読"}
    </Button>
  );
}

function ActionMessage({ state }: { state: NotificationActionState }) {
  if (state.error) {
    return (
      <FeedbackPanel className="mt-2" role="alert" variant="error">
        {state.error}
      </FeedbackPanel>
    );
  }

  if (state.unavailable) {
    return (
      <FeedbackPanel className="mt-2" role="alert" variant="neutral">
        この通知の対象は現在表示できません。通知は既読にしました。
      </FeedbackPanel>
    );
  }

  return null;
}

export function NotificationOpenAction({
  notificationId,
  notificationLabel,
}: {
  notificationId: string;
  notificationLabel: string;
}) {
  const router = useRouter();
  const [state, formAction] = useActionState(openNotification, initialState);

  useEffect(() => {
    if (state.completed) {
      router.refresh();
    }
  }, [router, state.completed, state.revision]);

  return (
    <form action={formAction} className="min-w-0 max-w-full">
      <input name="notificationId" type="hidden" value={notificationId} />
      <OpenButton notificationLabel={notificationLabel} />
      <ActionMessage state={state} />
    </form>
  );
}

export function NotificationReadAction({
  notificationId,
  notificationLabel,
}: {
  notificationId: string;
  notificationLabel: string;
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
    <form action={formAction} className="min-w-0 max-w-full">
      <input name="notificationId" type="hidden" value={notificationId} />
      <ReadButton notificationLabel={notificationLabel} />
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
    <form action={formAction} className="min-w-0 max-w-full">
      <MarkAllButton />
      <ActionMessage state={state} />
    </form>
  );
}
