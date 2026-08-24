"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  updateProfile,
  type ProfileActionState,
} from "@/app/(protected)/profile/actions";
import { ActionLink, Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormInput, FormTextarea } from "@/components/ui/form-controls";

type ProfileFormProps = {
  username: string;
  bio: string | null;
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

export function ProfileForm({ username, bio }: ProfileFormProps) {
  const [bioValue, setBioValue] = useState(bio ?? "");
  const initialState: ProfileActionState = {
    error: null,
    fieldErrors: {},
  };
  const [state, formAction] = useActionState(updateProfile, initialState);

  return (
    <form action={formAction}>
      <fieldset className="min-w-0 space-y-7">
        {state.error && (
          <FeedbackPanel
            aria-live="polite"
            role="alert"
            variant="error"
          >
            {state.error}
          </FeedbackPanel>
        )}

        <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="profile-username"
          >
            ユーザー名
          </label>
          <FormInput
            aria-describedby={
              state.fieldErrors.username
                ? "profile-username-error profile-username-help"
                : "profile-username-help"
            }
            aria-invalid={Boolean(state.fieldErrors.username)}
            defaultValue={username}
            id="profile-username"
            maxLength={50}
            name="username"
            required
            type="text"
          />
          <p
            className="mt-2 text-xs leading-5 text-text-muted"
            id="profile-username-help"
          >
            1文字以上50文字以下で入力してください。
          </p>
          {state.fieldErrors.username && (
            <p
              className="mt-2 text-sm text-danger"
              id="profile-username-error"
              role="alert"
            >
              {state.fieldErrors.username}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="profile-bio"
          >
            自己紹介
          </label>
          <FormTextarea
            aria-describedby={
              state.fieldErrors.bio ? "profile-bio-error" : undefined
            }
            aria-invalid={Boolean(state.fieldErrors.bio)}
            className="min-h-48 resize-y leading-7 sm:min-h-56"
            id="profile-bio"
            maxLength={500}
            name="bio"
            onChange={(event) => setBioValue(event.target.value)}
            value={bioValue}
          />
          <p
            aria-hidden="true"
            className="mt-2 text-right text-xs leading-5 text-text-muted"
          >
            {Array.from(bioValue).length} / 500文字
          </p>
          {state.fieldErrors.bio && (
            <p
              className="mt-2 text-sm text-danger"
              id="profile-bio-error"
              role="alert"
            >
              {state.fieldErrors.bio}
            </p>
          )}
        </div>

        <div className="flex flex-col gap-2 border-t border-border-subtle/70 pt-6 sm:items-end">
          <SaveButton />
          <ActionLink
            className="w-full sm:w-auto sm:min-w-36"
            href="/profile"
            variant="quiet"
          >
            キャンセル
          </ActionLink>
        </div>
      </fieldset>
    </form>
  );
}
