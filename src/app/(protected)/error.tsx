"use client";

import { ActionLink, Button } from "@/components/ui/actions";
import { Surface } from "@/components/ui/surface";

type ProtectedErrorProps = {
  error: Error & { digest?: string };
  reset: () => void;
};

export default function ProtectedError({ reset }: ProtectedErrorProps) {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8 sm:py-12">
      <Surface
        className="mx-auto w-full max-w-xl px-5 py-8 text-center sm:px-8 sm:py-10"
        variant="muted"
      >
        <p className="text-sm font-medium text-danger">エラー</p>
        <h1 className="mt-2 break-words text-2xl font-semibold tracking-tight text-text-primary [overflow-wrap:anywhere] sm:text-3xl">
          うまく読み込めませんでした
        </h1>
        <p className="mx-auto mt-3 max-w-md break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere] sm:text-base sm:leading-7">
          一時的な問題が起きたようです。もう一度試すか、ホームへ戻ってください。
        </p>
        <div className="mx-auto mt-6 flex max-w-sm flex-col gap-3 sm:flex-row sm:justify-center">
          <Button
            className="w-full sm:w-auto"
            onClick={reset}
            type="button"
            variant="primary"
          >
            もう一度試す
          </Button>
          <ActionLink
            className="w-full sm:w-auto"
            href="/home"
            variant="neutral"
          >
            ホームへ戻る
          </ActionLink>
        </div>
      </Surface>
    </section>
  );
}
