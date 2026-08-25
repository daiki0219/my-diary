import { FeedbackPanel } from "@/components/ui/feedback-panel";

export default function TagsLoading() {
  return (
    <section
      aria-busy="true"
      className="flex flex-1 px-4 pb-8 pt-6 sm:px-8 sm:pb-10 sm:pt-8"
    >
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <FeedbackPanel className="max-w-xl" role="status" variant="neutral">
          タグを読み込んでいます…
        </FeedbackPanel>
      </div>
    </section>
  );
}
