import { FeedbackPanel } from "@/components/ui/feedback-panel";

export default function ExchangeLoading() {
  return (
    <section
      aria-busy="true"
      className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6 lg:py-10"
    >
      <div className="mx-auto w-full max-w-5xl lg:max-w-6xl xl:max-w-none">
        <div className="xl:grid xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-x-8">
          <FeedbackPanel role="status" variant="neutral">
            交換日記を読み込んでいます…
          </FeedbackPanel>
        </div>
      </div>
    </section>
  );
}
