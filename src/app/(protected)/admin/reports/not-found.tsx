import Link from "next/link";

export default function AdminReportsNotFound() {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-lg rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
        <p className="text-sm font-medium text-orange-700">404</p>
        <h1 className="mt-2 text-2xl font-bold text-stone-800">
          ページが見つかりませんでした
        </h1>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          現在は表示できないページです。
        </p>
        <Link
          className="mt-6 inline-flex min-h-11 items-center rounded-full bg-orange-700 px-5 py-3 font-semibold text-white transition hover:bg-orange-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700"
          href="/home"
        >
          ホームへ戻る
        </Link>
      </div>
    </section>
  );
}
