import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";

export default function PostDetailNotFound() {
  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← タイムラインへ戻る
        </ActionLink>
        <PageHeader
          className="mt-3 max-w-xl"
          description="削除されたか、現在は表示できない日記です。"
          eyebrow="404"
          title="日記が見つかりませんでした"
          variant="plain"
        />
        <nav
          aria-label="日記が見つからない場合の移動先"
          className="mt-5 flex min-w-0 flex-col items-start gap-2 sm:flex-row"
        >
          <ActionLink href="/home" variant="secondary">
            タイムラインへ戻る
          </ActionLink>
          <ActionLink href="/posts/new" variant="quiet">
            日記を書く
          </ActionLink>
        </nav>
      </div>
    </section>
  );
}
