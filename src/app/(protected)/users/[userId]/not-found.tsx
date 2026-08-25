import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";

export default function UserProfileNotFound() {
  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>
        <PageHeader
          className="mt-3 max-w-xl"
          description="URLが正しいか確認してください。"
          eyebrow="404"
          title="プロフィールが見つかりません"
          variant="plain"
        />
      </div>
    </section>
  );
}
