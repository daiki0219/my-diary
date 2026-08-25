import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";

export default function TagDetailNotFound() {
  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/tags" variant="quiet">
          ← タグ一覧へ戻る
        </ActionLink>

        <PageHeader
          className="mt-3 max-w-xl"
          description="存在しないか、現在は表示できないタグです。タグ一覧から別の言葉を探してみましょう。"
          eyebrow="404"
          title="タグが見つかりませんでした"
          variant="plain"
        />

        <nav
          aria-label="タグが見つからない場合の移動先"
          className="mt-5 flex min-w-0 flex-col items-start gap-2 sm:flex-row"
        >
          <ActionLink href="/tags" variant="secondary">
            タグ一覧へ戻る
          </ActionLink>
          <ActionLink href="/home" variant="quiet">
            ホームへ戻る
          </ActionLink>
        </nav>
      </div>
    </section>
  );
}
