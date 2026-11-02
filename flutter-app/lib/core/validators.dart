import 'dart:convert';

abstract final class Validators {
  static String? requiredText(String? value, int max) {
    if (value == null || value.trim().isEmpty) return 'This field is required.';
    if (value.trim().length > max) return 'Use at most $max characters.';
    return null;
  }

  static String? email(String? value) {
    if (requiredText(value, 254) case final error?) return error;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
        ? null
        : 'Enter a valid email address.';
  }

  static String? password(String? value, {required bool registration}) {
    if (value == null || value.trim().isEmpty) return 'Enter your password.';
    if (registration && value.length < 12) return 'Use at least 12 characters.';
    if (value.length > 72 || utf8.encode(value).length > 72) {
      return 'Password must fit within 72 UTF-8 bytes.';
    }
    return null;
  }

  static String? sku(String? value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Use 1–40 letters, numbers, hyphens or underscores.';
  static String? wholeNumber(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null ||
            number < 0 ||
            number > 2147483647 ||
            !RegExp(r'^\d+$').hasMatch(value!.trim())
        ? 'Enter a whole number from 0 to 2147483647.'
        : null;
  }

  static String? price(String? value) =>
      RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Use up to 10 whole digits and 2 decimal places (0 allowed).';
}
