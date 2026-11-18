import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/domain/cpu_frequency.dart';

void main() {
  test('formats the frequency in GHz with two decimals', () {
    expect(formatCpuFrequency(4351), '4.35 GHz');
    expect(formatCpuFrequency(3401), '3.40 GHz');
  });

  test('keeps the digit that tells two turbo steps apart', () {
    // Con un solo decimal los dos se leerian "4.2 GHz".
    expect(formatCpuFrequency(4204), isNot(formatCpuFrequency(4244)));
  });
}
