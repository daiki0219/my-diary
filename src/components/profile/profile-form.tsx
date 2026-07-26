"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  updateProfile,
  type ProfileActionState,
} from "@/app/(protected)/profile/actions";

type ProfileFormProps = {
  username: string;
  bio: string | null;
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

export function ProfileForm({ username, bio }: ProfileFormProps) {
  const [bioValue, setBioValue] = useState(bio ?? "");
  const initialState: ProfileActionState = {
    error: null,
    fieldErrors: {},
  };
  const [state, formAction] = useActionState(updateProfile, initialState);

  return (
    <form action={formAction} className="space-y-6">
      {state.error && (
        <p
          aria-live="polite"
          className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="profile-username"
        >
          ユーザー名
        </label>
        <input
          aria-describedby={
            state.fieldErrors.username
              ? "profile-username-error profile-username-help"
              : "profile-username-help"
          }
          aria-invalid={Boolean(state.fieldErrors.username)}
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          defaultValue={username}
          id="profile-username"
          maxLength={50}
          name="username"
          required
          type="text"
        />
        <p className="mt-2 text-xs leading-5 text-stone-500" id="profile-username-help">
          1文字以上50文字以下で入力してください。
        </p>
        {state.fieldErrors.username && (
          <p
            className="mt-2 text-sm text-red-700"
            id="profile-username-error"
            role="alert"
          >
            {state.fieldErrors.username}
          </p>
        )}
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="profile-bio"
        >
          自己紹介
        </label>
        <textarea
          aria-describedby={
            state.fieldErrors.bio
              ? "profile-bio-error"
              : undefined
          }
          aria-invalid={Boolean(state.fieldErrors.bio)}
          className="min-h-40 w-full resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="profile-bio"
          maxLength={500}
          name="bio"
          onChange={(event) => setBioValue(event.target.value)}
          value={bioValue}
        />
        <p
          aria-hidden="true"
          className="mt-2 text-right text-xs leading-5 text-stone-500"
        >
          {Array.from(bioValue).length} / 500文字
        </p>
        {state.fieldErrors.bio && (
          <p
            className="mt-2 text-sm text-red-700"
            id="profile-bio-error"
            role="alert"
          >
            {state.fieldErrors.bio}
          </p>
        )}
      </div>

      <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <Link
          className="rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 sm:min-w-36"
          href="/profile"
        >
          キャンセル
        </Link>
        <SaveButton />
      </div>
    </form>
  );
}
