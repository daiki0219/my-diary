import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Surface } from "@/components/ui/surface";
import { getMoodLabel } from "@/lib/post-data";
import { createPostBodyExcerpt } from "@/lib/post-excerpt";
import type { RelatedPost } from "@/lib/related-post-data";

const RELATED_BODY_EXCERPT_LENGTH = 100;

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export type RelatedPostSection = {
  posts: RelatedPost[];
  error: boolean;
};

function RelatedPostCard({
  post,
  showAuthor,
}: {
  post: RelatedPost;
  showAuthor: boolean;
}) {
  const title = post.title?.trim() || "タイトルなしの日記";
  const body = createPostBodyExcerpt(
    post.body,
    RELATED_BODY_EXCERPT_LENGTH,
  );

  return (
    <Surface
      as="article"
      className="min-w-0 border border-border-subtle/60 p-4 sm:p-5"
      variant="muted"
    >
      {showAuthor && post.authorUsername && (
        <p className="break-words text-sm font-semibold text-text-primary [overflow-wrap:anywhere]">
          {post.authorUsername}
        </p>
      )}

      <div className="mt-1.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-muted first:mt-0">
        <time dateTime={post.created_at}>
          {dateFormatter.format(new Date(post.created_at))}
        </time>
        {post.mood && (
          <>
            <span aria-hidden="true">·</span>
            <span
              aria-label={`気分：${getMoodLabel(post.mood)}`}
              className="font-medium text-brand-primary-hover"
            >
              {getMoodLabel(post.mood)}
            </span>
          </>
        )}
      </div>

      <h4 className="mt-2.5 break-words font-brand text-lg font-medium leading-7 tracking-[0.01em] text-text-primary [overflow-wrap:anywhere]">
        {title}
      </h4>

      <p className="mt-2 whitespace-pre-wrap break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
        {body.text}
      </p>

      <ActionLink
        aria-label={`「${title}」の日記の詳細を見る`}
        className="-ml-3 mt-2"
        href={`/posts/${post.id}`}
        variant="quiet"
      >
        日記の詳細を見る
      </ActionLink>
    </Surface>
  );
}

function RelatedPostGroup({
  error,
  heading,
  headingId,
  posts,
  showAuthor,
}: {
  error: boolean;
  heading: string;
  headingId: string;
  posts: RelatedPost[];
  showAuthor: boolean;
}) {
  if (!error && posts.length === 0) {
    return null;
  }

  return (
    <section aria-labelledby={headingId}>
      <h3 className="text-base font-semibold text-text-primary" id={headingId}>
        {heading}
      </h3>
      {error ? (
        <FeedbackPanel className="mt-3" role="alert" variant="error">
          関連する日記の一部を読み込めませんでした。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      ) : (
        <ul className="mt-3 grid min-w-0 gap-3" role="list">
          {posts.map((post) => (
            <li className="min-w-0" key={post.id}>
              <RelatedPostCard post={post} showAuthor={showAuthor} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export function RelatedPosts({
  author,
  sameTag,
}: {
  author: RelatedPostSection;
  sameTag: RelatedPostSection;
}) {
  const hasPosts = author.posts.length > 0 || sameTag.posts.length > 0;
  const hasError = author.error || sameTag.error;

  if (!hasPosts && !hasError) {
    return null;
  }

  const totalFailure = author.error && sameTag.error;

  return (
    <aside
      aria-labelledby="related-posts-heading"
      className="mt-8 min-w-0 scroll-mt-16 border-t border-border-subtle/70 pt-7 sm:mt-10 sm:pt-8 lg:mt-0 lg:scroll-mt-28 lg:border-t-0 lg:pt-0"
      id="related-posts"
    >
      <h2
        className="text-xl font-semibold text-text-primary"
        id="related-posts-heading"
      >
        関連する日記
      </h2>

      {totalFailure ? (
        <FeedbackPanel className="mt-5" role="alert" variant="error">
          関連する日記を読み込めませんでした。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      ) : (
        <div className="mt-5 grid min-w-0 gap-7">
          <RelatedPostGroup
            error={author.error}
            heading="この人の他の日記"
            headingId="related-posts-author-heading"
            posts={author.posts}
            showAuthor={false}
          />
          <RelatedPostGroup
            error={sameTag.error}
            heading="同じタグの日記"
            headingId="related-posts-tag-heading"
            posts={sameTag.posts}
            showAuthor
          />
        </div>
      )}
    </aside>
  );
}
