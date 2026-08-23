"use client";

import { useEffect, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";

import {
  createReply,
  type CreateReplyActionState,
} from "@/app/(protected)/posts/actions";
import { CommentCard } from "@/components/posts/comment-card";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import {
  COMMENT_MAX_LENGTH,
  type CommentThread,
} from "@/lib/comment-data";

function ReplyFormButtons({ onCancel }: { onCancel: () => void }) {
  const { pending } = useFormStatus();

  return (
    <div className="mt-4 flex flex-wrap justify-end gap-2">
      <Button
        disabled={pending}
        onClick={onCancel}
        type="button"
        variant="quiet"
      >
        キャンセル
      </Button>
      <Button
        aria-disabled={pending}
        disabled={pending}
        type="submit"
        variant="primary"
      >
        {pending ? "返信中…" : "返信する"}
      </Button>
    </div>
  );
}

function ReplyForm({
  body,
  onBodyChange,
  onCancel,
  onSuccess,
  parentCommentId,
  postId,
}: {
  body: string;
  onBodyChange: (body: string) => void;
  onCancel: () => void;
  onSuccess: () => void;
  parentCommentId: string;
  postId: string;
}) {
  const [state, setState] = useState<CreateReplyActionState>({
    error: null,
    fieldError: null,
    createdCommentId: null,
  });
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const bodyId = `reply-body-${parentCommentId}`;
  const helpId = `${bodyId}-help`;
  const errorId = `${bodyId}-error`;

  useEffect(() => {
    textareaRef.current?.focus();
  }, []);

  async function formAction(formData: FormData) {
    const nextState = await createReply(state, formData);
    setState(nextState);

    if (nextState.createdCommentId) {
      onSuccess();
    }
  }

  return (
    <form
      action={formAction}
      className="min-w-0 rounded-control bg-brand-soft/50 p-4 sm:p-5"
      id={`reply-form-${parentCommentId}`}
    >
      <input name="postId" type="hidden" value={postId} />
      <input
        name="parentCommentId"
        type="hidden"
        value={parentCommentId}
      />

      <label
        className="mb-2 block text-sm font-semibold text-text-primary"
        htmlFor={bodyId}
      >
        返信を書く
      </label>
      <textarea
        aria-describedby={state.fieldError ? `${helpId} ${errorId}` : helpId}
        aria-invalid={Boolean(state.fieldError)}
        className="min-h-24 w-full resize-y rounded-control border border-border-control bg-surface-elevated px-4 py-3 text-base leading-7 text-text-primary transition placeholder:text-text-muted focus:border-focus aria-invalid:border-danger"
        id={bodyId}
        maxLength={COMMENT_MAX_LENGTH}
        name="body"
        onChange={(event) => onBodyChange(event.target.value)}
        ref={textareaRef}
        required
        value={body}
      />
      <div className="mt-2 flex min-w-0 items-start justify-between gap-3 text-xs leading-5 text-text-muted">
        <p className="min-w-0" id={helpId}>
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
          id={errorId}
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

      <ReplyFormButtons onCancel={onCancel} />
    </form>
  );
}

export function CommentThreadList({
  currentUserId,
  postId,
  threads,
}: {
  currentUserId: string;
  postId: string;
  threads: CommentThread[];
}) {
  const router = useRouter();
  const [activeParentId, setActiveParentId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, string>>({});

  function closeReplyForm(parentCommentId: string, restoreFocus: boolean) {
    setActiveParentId(null);

    if (restoreFocus) {
      requestAnimationFrame(() => {
        document.getElementById(`reply-button-${parentCommentId}`)?.focus();
      });
    }
  }

  function completeReply(parentCommentId: string) {
    setDrafts((current) => ({ ...current, [parentCommentId]: "" }));
    closeReplyForm(parentCommentId, false);
    router.refresh();
  }

  return (
    <ol className="mt-7 divide-y divide-border-subtle/70">
      {threads.map((thread) => {
        if (thread.kind === "unavailable") {
          return (
            <li
              className="min-w-0 py-6 first:pt-0 last:pb-0"
              key={thread.key}
            >
              <article className="min-w-0 py-1">
                <p className="text-sm font-medium text-text-muted">
                  削除されたコメントです
                </p>
              </article>
              <ol
                aria-label="削除されたコメントへの返信"
                className="mt-3 ml-2 min-w-0 space-y-5 border-l border-brand-primary/20 pl-2 sm:ml-3 sm:pl-3"
              >
                {thread.replies.map((reply) => (
                  <li className="min-w-0" key={reply.id}>
                    <CommentCard
                      comment={reply}
                      currentUserId={currentUserId}
                      isReply
                      postId={postId}
                    />
                  </li>
                ))}
              </ol>
            </li>
          );
        }

        const parentId = thread.parent.id;
        const isReplyFormOpen = activeParentId === parentId;
        const replyFormId = `reply-form-${parentId}`;

        return (
          <li
            className="min-w-0 py-6 first:pt-0 last:pb-0"
            key={parentId}
          >
            <CommentCard
              comment={thread.parent}
              currentUserId={currentUserId}
              isReplyFormOpen={isReplyFormOpen}
              onReply={() => setActiveParentId(parentId)}
              postId={postId}
              replyControlsId={replyFormId}
            />
            {isReplyFormOpen && (
              <div className="mt-2 ml-2 min-w-0 border-l border-brand-primary/20 pl-2 sm:ml-3 sm:pl-3">
                <ReplyForm
                  body={drafts[parentId] ?? ""}
                  key={parentId}
                  onBodyChange={(body) =>
                    setDrafts((current) => ({
                      ...current,
                      [parentId]: body,
                    }))
                  }
                  onCancel={() => closeReplyForm(parentId, true)}
                  onSuccess={() => completeReply(parentId)}
                  parentCommentId={parentId}
                  postId={postId}
                />
              </div>
            )}
            {thread.replies.length > 0 && (
              <ol
                aria-label="返信"
                className="mt-3 ml-2 min-w-0 space-y-5 border-l border-brand-primary/20 pl-2 sm:ml-3 sm:pl-3"
              >
                {thread.replies.map((reply) => (
                  <li className="min-w-0" key={reply.id}>
                    <CommentCard
                      comment={reply}
                      currentUserId={currentUserId}
                      isReply
                      postId={postId}
                    />
                  </li>
                ))}
              </ol>
            )}
          </li>
        );
      })}
    </ol>
  );
}
