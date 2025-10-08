import 'dart:math' as math;

String formatCompactValue(double value, {int maxDecimals = 2}) {
  if (value.isNaN || value.isInfinite) {
    return '';
  }
  final roundedInteger = value.roundToDouble();
  if ((value - roundedInteger).abs() < 1e-9) {
    return roundedInteger.toStringAsFixed(0);
  }
  if (maxDecimals <= 0) {
    return roundedInteger.toStringAsFixed(0);
  }
  final oneDecimal = (value * 10).roundToDouble() / 10;
  if ((oneDecimal - value).abs() < 1e-6 || maxDecimals == 1) {
    return _trimTrailingZeros(oneDecimal.toStringAsFixed(1));
  }
  final decimals = math.min(2, maxDecimals);
  final factor = math.pow(10, decimals).toDouble();
  final rounded = (value * factor).roundToDouble() / factor;
  return _trimTrailingZeros(rounded.toStringAsFixed(decimals));
}

String formatOptionalCompact(double? value, {int maxDecimals = 2}) {
  if (value == null) {
    return '';
  }
  return formatCompactValue(value, maxDecimals: maxDecimals);
}

String formatMetersTooltip(double value) {
  if (value.isNaN || value.isInfinite) {
    return '';
  }
  return value.toStringAsFixed(2);
}

String _trimTrailingZeros(String text) {
  if (!text.contains('.')) {
    return text;
  }
  text = text.replaceAll(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
