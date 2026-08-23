"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";

import {
  createComment,
  type CreateCommentActionState,
} from "@/app/(protected)/posts/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormTextarea } from "@/components/ui/form-controls";
import { COMMENT_MAX_LENGTH } from "@/lib/comment-data";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <Button
      aria-disabled={pending}
      className="w-full sm:w-auto sm:min-w-32"
      disabled={pending}
      type="submit"
      variant="primary"
    >
      {pending ? "投稿中…" : "コメントする"}
    </Button>
  );
}

export function CommentForm({ postId }: { postId: string }) {
  const [body, setBody] = useState("");
  const [state, setState] = useState<CreateCommentActionState>({
    error: null,
    fieldError: null,
    createdCommentId: null,
  });

  async function formAction(formData: FormData) {
    const nextState = await createComment(state, formData);
    setState(nextState);

    if (nextState.createdCommentId) {
      setBody("");
    }
  }

  return (
    <form
      action={formAction}
      className="mt-4 scroll-mt-16 rounded-card bg-surface-muted/70 p-4 sm:p-5 lg:scroll-mt-28"
      id="comment-form"
    >
      <input name="postId" type="hidden" value={postId} />

      <label
        className="mb-2 block text-sm font-semibold text-text-primary"
        htmlFor="comment-body"
      >
        コメントを書く
      </label>
      <FormTextarea
        aria-describedby={
          state.fieldError
            ? "comment-body-help comment-body-error"
            : "comment-body-help"
        }
        aria-invalid={Boolean(state.fieldError)}
        className="min-h-28 resize-y bg-surface-elevated leading-7"
        id="comment-body"
        maxLength={COMMENT_MAX_LENGTH}
        name="body"
        onChange={(event) => setBody(event.target.value)}
        required
        value={body}
      />
      <div className="mt-2 flex min-w-0 items-start justify-between gap-3 text-xs leading-5 text-text-muted">
        <p className="min-w-0" id="comment-body-help">
          {COMMENT_MAX_LENGTH.toLocaleString("ja-JP")}
          文字以下で入力してください。改行も使用できます。
        </p>
        <p aria-hidden="true" className="shrink-0">
          {Array.from(body).length} /{" "}
          {COMMENT_MAX_LENGTH.toLocaleString("ja-JP")}
        </p>
      </div>

      {state.fieldError && (
        <FeedbackPanel
          className="mt-3"
          id="comment-body-error"
          role="alert"
          variant="error"
        >
          {state.fieldError}
        </FeedbackPanel>
      )}

      {state.error && (
        <FeedbackPanel className="mt-3" role="alert" variant="error">
          {state.error}
        </FeedbackPanel>
      )}

      {state.createdCommentId && (
        <FeedbackPanel className="mt-3" role="status" variant="success">
          コメントを投稿しました。
        </FeedbackPanel>
      )}

      <div className="mt-4 flex justify-end">
        <SubmitButton />
      </div>
    </form>
  );
}
