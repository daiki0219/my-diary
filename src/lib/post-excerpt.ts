export const TIMELINE_BODY_EXCERPT_LENGTH = 280;

export function createPostBodyExcerpt(
  body: string,
  maximumCodePoints = TIMELINE_BODY_EXCERPT_LENGTH,
) {
  const codePoints = Array.from(body);

  if (codePoints.length <= maximumCodePoints) {
    return { text: body, isTruncated: false };
  }

  return {
    text: `${codePoints.slice(0, maximumCodePoints).join("")}…`,
    isTruncated: true,
  };
}
