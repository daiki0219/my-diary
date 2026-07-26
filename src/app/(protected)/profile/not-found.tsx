import Link from "next/link";

export default function OwnProfileNotFound() {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-lg rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
        <p className="text-sm font-medium text-orange-700">404</p>
        <h1 className="mt-2 text-2xl font-bold text-stone-800">
          プロフィールが見つかりません
        </h1>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          プロフィールの初期データを確認できませんでした。
        </p>
        <Link
          className="mt-6 inline-flex rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
          href="/home"
        >
          ホームへ戻る
        </Link>
      </div>
    </section>
  );
}
