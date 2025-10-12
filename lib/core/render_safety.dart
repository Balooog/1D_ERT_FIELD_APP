/// Utilities for defensive UI rendering when upstream models may be null.
T tryRenderSafe<T>(
  T? value,
  T fallback, {
  void Function()? onNull,
}) {
  if (value != null) {
    return value;
  }
  if (onNull != null) {
    onNull();
  }
  return fallback;
}
