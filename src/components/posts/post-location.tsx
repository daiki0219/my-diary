export function PostLocation({
  locationName,
}: {
  locationName: string | null;
}) {
  if (!locationName) {
    return null;
  }

  return (
    <p className="mt-3 min-w-0 break-words text-sm leading-6 text-stone-500 [overflow-wrap:anywhere]">
      <span className="font-medium text-stone-600">場所:</span>{" "}
      {locationName}
    </p>
  );
}
