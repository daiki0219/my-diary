export function CommentCount({
  count,
  variant = "default",
}: {
  count: number | null;
  variant?: "default" | "timeline";
}) {
  if (count === null) {
    return (
      <p
        className={
          variant === "timeline"
            ? "text-xs leading-5 text-red-700"
            : "mt-4 text-sm text-red-700"
        }
        role="alert"
      >
        コメント件数を読み込めませんでした。
      </p>
    );
  }

  if (variant === "timeline") {
    return (
      <p className="inline-flex min-h-11 items-center gap-1.5 text-xs font-medium text-text-muted">
        <svg
          aria-hidden="true"
          className="size-4"
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="1.7"
          viewBox="0 0 24 24"
        >
          <path d="M20 15a4 4 0 0 1-4 4H8l-4 3v-7a4 4 0 0 1-1-2.65V7a4 4 0 0 1 4-4h9a4 4 0 0 1 4 4Z" />
        </svg>
        <span>コメント {count}件</span>
      </p>
    );
  }

  return (
    <p className="mt-4 text-sm font-medium text-stone-600">
      コメント {count}件
    </p>
  );
}
