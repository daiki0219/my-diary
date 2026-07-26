export function CommentCount({ count }: { count: number | null }) {
  if (count === null) {
    return (
      <p className="mt-4 text-sm text-red-700" role="alert">
        コメント件数を読み込めませんでした。
      </p>
    );
  }

  return (
    <p className="mt-4 text-sm font-medium text-stone-600">
      コメント {count}件
    </p>
  );
}
