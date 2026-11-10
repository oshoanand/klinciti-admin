class PhoneFormatter {
  /// Formats a phone number from "79876543211" to "+7 987 654 32-11"
  static String format(String? mobile) {
    if (mobile == null || mobile.length < 11) return mobile ?? 'Нет номера';

    // Assumes format starts with 7 or 8 and has 11 digits
    const country = '+7';
    final code = mobile.substring(1, 4);
    final p1 = mobile.substring(4, 7);
    final p2 = mobile.substring(7, 9);
    final p3 = mobile.substring(9, 11);

    return '$country $code $p1 $p2-$p3';
  }
}
