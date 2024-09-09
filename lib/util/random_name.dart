import 'dart:math';

_generateRandomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random();
  return List.generate(
    10,
    (index) => chars[random.nextInt(chars.length)],
    growable: false,
  ).join();
}
