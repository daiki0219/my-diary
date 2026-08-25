import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";

export default function OwnProfileNotFound() {
  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>
        <PageHeader
          className="mt-3 max-w-xl"
          description="プロフィールの初期データを確認できませんでした。"
          eyebrow="404"
          title="プロフィールが見つかりません"
          variant="plain"
        />
      </div>
    </section>
  );
}
