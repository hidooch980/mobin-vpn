import 'package:flutter_test/flutter_test.dart';
import 'package:mobin_vpn/core/background_scanner.dart';

void main() {
  final t0 = DateTime(2026, 9, 15, 12);

  test('recent successes first (fastest first), unknown next, 3 failures last', () {
    final book = HealthBook()
      ..record('n', 'slow', 900, now: t0)
      ..record('n', 'fast', 120, now: t0);
    for (var i = 0; i < 3; i++) {
      book.record('n', 'bad', -1, now: t0);
    }
    final ordered = book.order('n', ['bad', 'unknown', 'slow', 'fast'], (s) => s, now: t0);
    expect(ordered, ['fast', 'slow', 'unknown', 'bad']);
  });

  test('two failures do not deprioritise; the 6 h penalty expires; success resets', () {
    final book = HealthBook()
      ..record('n', 'a', -1, now: t0)
      ..record('n', 'a', -1, now: t0);
    expect(book.isDeprioritised('n', 'a', now: t0), isFalse);
    book.record('n', 'a', -1, now: t0);
    expect(book.isDeprioritised('n', 'a', now: t0), isTrue);
    expect(book.isDeprioritised('n', 'a', now: t0.add(const Duration(hours: 7))), isFalse);
    book.record('n', 'a', 300, now: t0);
    expect(book.health('n', 'a')!.fails, 0);
    expect(book.isDeprioritised('n', 'a', now: t0), isFalse);
  });

  test('memory is per network and survives JSON', () {
    final book = HealthBook()..record('mci', 'x', 200, now: t0);
    expect(book.tier('irancell', 'x', now: t0), 1);
    final copy = HealthBook()..loadJsonString(book.toJsonString());
    expect(copy.tier('mci', 'x', now: t0), 0);
    expect(copy.health('mci', 'x')!.ms, 200);
  });

  test('hourly report budget', () {
    final budget = HourlyBudget(200);
    expect(budget.take(150, now: t0), 150);
    expect(budget.take(150, now: t0.add(const Duration(minutes: 30))), 50);
    expect(budget.take(10, now: t0.add(const Duration(minutes: 59))), 0);
    expect(budget.take(10, now: t0.add(const Duration(minutes: 61))), 10);
  });
}
