export function PostLocation({
  locationName,
  variant = "default",
}: {
  locationName: string | null;
  variant?: "default" | "timeline";
}) {
  if (!locationName) {
    return null;
  }

  return (
    <p
      className={`min-w-0 break-words [overflow-wrap:anywhere] ${
        variant === "timeline"
          ? "mt-1.5 text-xs leading-5 text-text-muted"
          : "mt-3 text-sm leading-6 text-stone-500"
      }`}
    >
      <span
        className={
          variant === "timeline"
            ? "font-medium text-text-secondary"
            : "font-medium text-stone-600"
        }
      >
        場所:
      </span>{" "}
      {locationName}
    </p>
  );
}
