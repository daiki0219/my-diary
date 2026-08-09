"use client";

import { useEffect, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";

import {
  createReply,
  type CreateReplyActionState,
} from "@/app/(protected)/posts/actions";
import { CommentCard } from "@/components/posts/comment-card";
import {
  COMMENT_MAX_LENGTH,
  type CommentThread,
} from "@/lib/comment-data";

function ReplyFormButtons({ onCancel }: { onCancel: () => void }) {
  const { pending } = useFormStatus();

  return (
    <div className="mt-4 flex flex-wrap justify-end gap-2">
      <button
        className="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:bg-stone-100 disabled:text-stone-400"
        disabled={pending}
        onClick={onCancel}
        type="button"
      >
        キャンセル
      </button>
      <button
        aria-disabled={pending}
        className="rounded-full bg-orange-600 px-5 py-2 text-sm font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400"
        disabled={pending}
        type="submit"
      >
        {pending ? "返信中…" : "返信する"}
      </button>
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
      className="mt-3 min-w-0 rounded-2xl border border-orange-200 bg-orange-50 p-4"
      id={`reply-form-${parentCommentId}`}
    >
      <input name="postId" type="hidden" value={postId} />
      <input
        name="parentCommentId"
        type="hidden"
        value={parentCommentId}
      />

      <label
        className="mb-2 block text-sm font-semibold text-stone-700"
        htmlFor={bodyId}
      >
        返信を書く
      </label>
      <textarea
        aria-describedby={state.fieldError ? `${helpId} ${errorId}` : helpId}
        aria-invalid={Boolean(state.fieldError)}
        className="min-h-24 w-full resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
        id={bodyId}
        maxLength={COMMENT_MAX_LENGTH}
        name="body"
        onChange={(event) => onBodyChange(event.target.value)}
        ref={textareaRef}
        required
        value={body}
      />
      <div className="mt-2 flex min-w-0 items-start justify-between gap-3 text-xs leading-5 text-stone-500">
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
        <p className="mt-2 text-sm text-red-700" id={errorId} role="alert">
          {state.fieldError}
        </p>
      )}

      {state.error && (
        <p
          aria-live="polite"
          className="mt-3 break-words rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700 [overflow-wrap:anywhere]"
          role="alert"
        >
          {state.error}
        </p>
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
    <ol className="mt-4 space-y-4">
      {threads.map((thread) => {
        if (thread.kind === "unavailable") {
          return (
            <li className="min-w-0" key={thread.key}>
              <article className="min-w-0 rounded-2xl border border-stone-200 bg-white p-4">
                <p className="text-sm font-semibold text-stone-600">
                  削除されたコメントです
                </p>
              </article>
              <ol
                aria-label="削除されたコメントへの返信"
                className="mt-3 ml-3 min-w-0 space-y-3 border-l-2 border-orange-100 pl-3 sm:ml-6 sm:pl-5"
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
          <li className="min-w-0" key={parentId}>
            <CommentCard
              comment={thread.parent}
              currentUserId={currentUserId}
              isReplyFormOpen={isReplyFormOpen}
              onReply={() => setActiveParentId(parentId)}
              postId={postId}
              replyControlsId={replyFormId}
            />
            {isReplyFormOpen && (
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
            )}
            {thread.replies.length > 0 && (
              <ol
                aria-label="返信"
                className="mt-3 ml-3 min-w-0 space-y-3 border-l-2 border-orange-100 pl-3 sm:ml-6 sm:pl-5"
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
