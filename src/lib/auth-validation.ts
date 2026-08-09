export const PASSWORD_MIN_LENGTH = 6;

export const PASSWORD_REQUIREMENTS_MESSAGE = `パスワードは${PASSWORD_MIN_LENGTH}文字以上で入力してください。`;

export function getPasswordValidationError(password: string) {
  if (!password) {
    return "パスワードを入力してください。";
  }

  if (password.length < PASSWORD_MIN_LENGTH) {
    return PASSWORD_REQUIREMENTS_MESSAGE;
  }

  return null;
}
