import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/processes/domain/process_ai_prompt.dart';
import 'package:nexodeck/features/processes/domain/process_group.dart';
import 'package:nexodeck/src/rust/api/processes.dart' as bridge;

ProcessGroup _group({
  String name = 'chrome.exe',
  double cpu = 12.5,
  double memory = 4096,
  double? gpu = 3.5,
  int runTime = 3661,
}) => ProcessGroup(
  name: name,
  pids: const [100, 101],
  cpuPercent: cpu,
  memoryMb: memory,
  gpuPercent: gpu,
  diskBytesPerSec: 0,
  runTimeSecs: runTime,
  isSelf: false,
);

void main() {
  group('buildProcessQuestionPrompt', () {
    test('sin detalle, con lo que ya trae el grupo', () {
      final prompt = buildProcessQuestionPrompt(_group());

      expect(prompt, contains('chrome.exe'));
      expect(prompt, contains('12.5% de CPU'));
      expect(prompt, contains('4.00 GB de RAM'));
      expect(prompt, contains('3.5% de GPU'));
      expect(prompt, contains('1 h 1 min'));
      // Sin detalle, no hay PID ni linea de comando.
      expect(prompt, isNot(contains('PID')));
      expect(prompt, isNot(contains('lanzo')));
    });

    test('sin GPU disponible no menciona GPU', () {
      final prompt = buildProcessQuestionPrompt(_group(gpu: null));
      expect(prompt, isNot(contains('GPU')));
    });

    test('con detalle agrega PID, padre, dueno y linea de comando', () {
      final prompt = buildProcessQuestionPrompt(
        _group(),
        details: const bridge.ProcessDetails(
          pid: 4821,
          parentName: 'explorer.exe',
          commandLine: 'chrome.exe --profile-directory=Default',
          exePath: r'C:\Program Files\Google\Chrome\chrome.exe',
          owner: 'juan',
        ),
      );

      expect(prompt, contains('PID 4821'));
      expect(prompt, contains('Lo lanzo "explorer.exe"'));
      expect(prompt, contains('usuario "juan"'));
      expect(
        prompt,
        contains('chrome.exe --profile-directory=Default'),
      );
    });

    test('con detalle pero sin linea de comando cae al ejecutable', () {
      final prompt = buildProcessQuestionPrompt(
        _group(),
        details: const bridge.ProcessDetails(
          pid: 4821,
          exePath: r'C:\Program Files\Google\Chrome\chrome.exe',
        ),
      );

      expect(prompt, contains('Ejecutable'));
      expect(prompt, contains(r'C:\Program Files\Google\Chrome\chrome.exe'));
    });

    test('un detalle vacio no agrega nada extra mas alla del PID', () {
      final prompt = buildProcessQuestionPrompt(
        _group(),
        details: const bridge.ProcessDetails(pid: 4821),
      );

      expect(prompt, contains('PID 4821'));
      expect(prompt, isNot(contains('lanzo')));
      expect(prompt, isNot(contains('usuario')));
      expect(prompt, isNot(contains('Linea de comando')));
      expect(prompt, isNot(contains('Ejecutable')));
    });
  });
}
