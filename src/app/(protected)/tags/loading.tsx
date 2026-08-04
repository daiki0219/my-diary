export default function TagsLoading() {
  return (
    <section
      aria-busy="true"
      className="flex flex-1 items-center px-4 py-10 sm:px-8"
    >
      <div
        className="mx-auto w-full max-w-lg rounded-3xl border border-orange-100 bg-orange-50 p-6 text-center text-sm font-medium text-stone-700"
        role="status"
      >
        タグを読み込んでいます…
      </div>
    </section>
  );
}
