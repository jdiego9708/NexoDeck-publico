import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/features/dashboard/domain/metric_kind.dart';
import 'package:nexodeck/features/processes/domain/process_group.dart';
import 'package:nexodeck/features/processes/domain/process_panel_dock.dart';
import 'package:nexodeck/features/processes/presentation/confirm_kill_dialog.dart';
import 'package:nexodeck/features/processes/presentation/process_panel.dart';
import 'package:nexodeck/features/processes/presentation/widgets/process_row.dart';
import 'package:nexodeck/features/processes/presentation/widgets/process_table.dart';

ProcessGroup _group({
  String name = 'chrome.exe',
  int processCount = 1,
  double cpu = 12.5,
  double memory = 4096,
  double? gpu = 3.5,
  double disk = 0,
  int runTime = 3661,
  bool isSelf = false,
}) => ProcessGroup(
  name: name,
  pids: List.generate(processCount, (i) => 100 + i),
  cpuPercent: cpu,
  memoryMb: memory,
  gpuPercent: gpu,
  diskBytesPerSec: disk,
  runTimeSecs: runTime,
  isSelf: isSelf,
);

void main() {
  group('MetricKind', () {
    test('CPU, RAM, GPU y Disco se pueden desglosar por proceso', () {
      // Red queda afuera por una limitacion real de Windows (hace falta
      // ETW), no por gusto: si se habilita sin implementar la fuente, la
      // tile responde al clic y no muestra nada. Disco SI se puede: sale de
      // `GetProcessIoCounters`, sin ETW de por medio.
      expect(MetricKind.cpu.supportsProcessBreakdown, isTrue);
      expect(MetricKind.ram.supportsProcessBreakdown, isTrue);
      expect(MetricKind.gpu.supportsProcessBreakdown, isTrue);
      expect(MetricKind.disk.supportsProcessBreakdown, isTrue);
      expect(MetricKind.network.supportsProcessBreakdown, isFalse);
    });
  });

  group('formatRunTime', () {
    test('escala de segundos a dias', () {
      expect(formatRunTime(45), '45 s');
      expect(formatRunTime(12 * 60), '12 min');
      expect(formatRunTime(2 * 3600 + 13 * 60), '2 h 13 min');
      // Sin minutos no se escribe "3 h 0 min".
      expect(formatRunTime(3 * 3600), '3 h');
      expect(formatRunTime(3 * 86400 + 4 * 3600), '3 d 4 h');
    });

    /// Cero es DESCONOCIDO, no recien arrancado: Windows no deja leer el
    /// tiempo de arranque de los procesos del sistema, y ahi `run_time` daba
    /// el epoch entero (`dwm.exe` aparecia con 20691 dias).
    test('cero significa desconocido y no cero segundos', () {
      expect(formatRunTime(0), '—');
      expect(formatRunTime(-5), '—');
    });
  });

  group('formatMetricValue', () {
    /// Un decimal y no cero como en la tile: con `toStringAsFixed(0)` dos
    /// tercios de la lista dirian "0%" y no se distinguiria el que consume
    /// algo del que no consume nada.
    test('los porcentajes llevan un decimal', () {
      expect(formatMetricValue(_group(cpu: 0.4), MetricKind.cpu), '0.4%');
      expect(formatMetricValue(_group(gpu: 3.54), MetricKind.gpu), '3.5%');
    });

    test('la memoria pasa a GB recien arriba del giga', () {
      expect(formatMetricValue(_group(memory: 740), MetricKind.ram), '740 MB');
      expect(
        formatMetricValue(_group(memory: 4096), MetricKind.ram),
        '4.00 GB',
      );
    });

    test('sin dato de GPU se dibuja una raya, no un cero', () {
      expect(formatMetricValue(_group(gpu: null), MetricKind.gpu), '—');
    });

    test('el disco se muestra como tasa, igual que la Red', () {
      expect(
        formatMetricValue(_group(disk: 2048), MetricKind.disk),
        '2.0 KB/s',
      );
    });
  });

  group('ProcessRowDensity', () {
    test('las columnas completas salen del ancho, no del modo del panel', () {
      expect(ProcessRowDensity.forWidth(320), ProcessRowDensity.compact);
      expect(
        ProcessRowDensity.forWidth(AppSizes.processPanelFullColumnsWidth),
        ProcessRowDensity.full,
      );
      expect(ProcessRowDensity.forWidth(1200), ProcessRowDensity.full);
    });
  });

  group('ProcessPanelDock', () {
    test('un valor guardado invalido cae al lado izquierdo', () {
      expect(ProcessPanelDock.fromName('nope'), ProcessPanelDock.left);
      expect(ProcessPanelDock.fromName(null), ProcessPanelDock.left);
      expect(
        ProcessPanelDock.fromName('maximized'),
        ProcessPanelDock.maximized,
      );
    });

    test('solo izquierda y derecha son laterales', () {
      expect(ProcessPanelDock.left.isSide, isTrue);
      expect(ProcessPanelDock.right.isSide, isTrue);
      expect(ProcessPanelDock.maximized.isSide, isFalse);
    });
  });

  group('ProcessPanelBody', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required List<ProcessGroup>? groups,
      MetricKind metric = MetricKind.cpu,
      bool gpuAvailable = true,
      Set<String> terminating = const {},
      ValueChanged<ProcessGroup>? onTerminate,
      VoidCallback? onClose,
      Size surface = const Size(360, 600),
    }) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessPanelBody(
              metric: metric,
              dock: ProcessPanelDock.left,
              groups: groups,
              gpuAvailable: gpuAvailable,
              terminating: terminating,
              onClose: onClose ?? () {},
              onDockChanged: (_) {},
              onTerminate: onTerminate,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('lista los grupos con su consumo y su tiempo', (tester) async {
      await pumpPanel(
        tester,
        groups: [_group(processCount: 14, cpu: 18.2, runTime: 3661)],
      );

      expect(find.text('chrome.exe'), findsOneWidget);
      expect(find.text('14 procesos'), findsOneWidget);
      expect(find.text('18.2%'), findsOneWidget);
      // El tiempo va en dos lineas para no comerse el ancho de una columna
      // de datos: la unidad grande arriba y el resto abajo.
      expect(find.text('1 h'), findsOneWidget);
      expect(find.text('1 min'), findsOneWidget);
    });

    /// "1 proceso" en cada fila seria ruido: solo se dice cuando agrupa.
    testWidgets('un grupo de uno solo no anuncia la cantidad', (tester) async {
      await pumpPanel(tester, groups: [_group(processCount: 1)]);
      expect(find.textContaining('procesos'), findsNothing);
    });

    testWidgets('el propio NexoDeck se muestra pero no se deja cerrar', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        groups: [_group(name: 'nexodeck.exe', isSelf: true)],
        onTerminate: (_) {},
      );

      expect(find.text('nexodeck.exe'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(ProcessRow),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('mientras se cierra, la fila lo dice en vez de desaparecer', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        groups: [_group()],
        terminating: {'chrome.exe'},
        onTerminate: (_) {},
      );

      expect(find.text('Cerrando…'), findsOneWidget);
      expect(find.text('chrome.exe'), findsOneWidget);
    });

    /// Los dos vacios de GPU dicen cosas distintas y no se pueden confundir.
    testWidgets('distingue "no se puede medir" de "nadie la usa"', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        groups: const [],
        metric: MetricKind.gpu,
        gpuAvailable: false,
      );
      expect(find.text('Sin datos por proceso'), findsOneWidget);

      await pumpPanel(
        tester,
        groups: const [],
        metric: MetricKind.gpu,
        gpuAvailable: true,
      );
      expect(find.text('Nadie está usando la GPU'), findsOneWidget);
    });

    testWidgets('sin la primera muestra todavia, muestra que esta midiendo', (
      tester,
    ) async {
      await pumpPanel(tester, groups: null);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('el boton de cerrar dispara el callback', (tester) async {
      var closes = 0;
      await pumpPanel(tester, groups: [_group()], onClose: () => closes++);

      await tester.tap(find.byTooltip('Cerrar (Esc)'));
      await tester.pump();
      expect(closes, 1);
    });

    /// Con el panel angosto solo entra la metrica elegida; ancho, las cuatro.
    testWidgets('con ancho de sobra aparecen todas las columnas', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        groups: [_group(cpu: 12.5, memory: 4096, gpu: 3.5, disk: 2048)],
        surface: const Size(900, 600),
      );

      expect(find.text('12.5%'), findsOneWidget);
      expect(find.text('4.00 GB'), findsOneWidget);
      expect(find.text('3.5%'), findsOneWidget);
      expect(find.text('2.0 KB/s'), findsOneWidget);
    });

    testWidgets('angosto muestra solo la metrica elegida', (tester) async {
      await pumpPanel(
        tester,
        groups: [_group(cpu: 12.5, memory: 4096, gpu: 3.5)],
        surface: const Size(320, 600),
      );

      expect(find.text('12.5%'), findsOneWidget);
      expect(find.text('4.00 GB'), findsNothing);
    });
  });

  group('showConfirmKillDialog', () {
    Future<bool?> openDialog(WidgetTester tester, ProcessGroup group) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showConfirmKillDialog(context, group);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('avisa cuantos procesos se van a cerrar', (tester) async {
      await openDialog(tester, _group(processCount: 14));

      expect(find.text('¿Cerrar chrome.exe?'), findsOneWidget);
      // Cerrar "chrome.exe" en realidad cierra sus 14 procesos, o sea todas
      // las pestanas: no se puede decir solo "cerrar chrome".
      expect(find.textContaining('14 procesos'), findsOneWidget);
    });

    testWidgets('con un solo proceso no habla de cantidades', (tester) async {
      await openDialog(tester, _group(processCount: 1));
      expect(find.textContaining('procesos'), findsNothing);
    });

    /// Cancelar es la accion por defecto: en una pantalla de clics rapidos,
    /// apretar Enter por inercia no puede matar nada.
    testWidgets('cancelar es lo que tiene el foco', (tester) async {
      await openDialog(tester, _group());

      final cancel = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cancelar'),
          matching: find.byType(TextButton),
        ),
      );
      expect(cancel.autofocus, isTrue);
    });

    testWidgets('cancelar devuelve false y cerrar devuelve true', (
      tester,
    ) async {
      await openDialog(tester, _group());
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await openDialog(tester, _group());
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('splitRunTime', () {
    /// Parte el tiempo en dos lineas: sin esto, "3 h 21 min" en una sola se
    /// comia el ancho de una columna de datos.
    test('separa la unidad grande del resto', () {
      expect(splitRunTime(3 * 3600 + 21 * 60), ('3 h', '21 min'));
      expect(splitRunTime(3 * 86400 + 4 * 3600), ('3 d', '4 h'));
    });

    /// Sin resto no se dibuja una segunda linea vacia.
    test('sin resto no hay segunda linea', () {
      expect(splitRunTime(45), ('45 s', null));
      expect(splitRunTime(12 * 60), ('12 min', null));
      expect(splitRunTime(3 * 3600), ('3 h', null));
    });

    test('cero sigue siendo desconocido', () {
      expect(splitRunTime(0), ('—', null));
    });
  });

  group('shareOfTotal', () {
    /// El dato que faltaba: 4 GB no dice si es mucho sin saber cuanta RAM
    /// tiene el equipo.
    test('la memoria se expresa como parte del total', () {
      expect(
        shareOfTotal(_group(memory: 4096), MetricKind.ram, 32768),
        '13% del total',
      );
      // Por debajo del 10% se usa un decimal, que ahi si distingue.
      expect(
        shareOfTotal(_group(memory: 1024), MetricKind.ram, 32768),
        '3.1% del total',
      );
    });

    /// CPU y GPU ya son fraccion del total: no hay nada que agregar.
    test('CPU y GPU no llevan esta columna', () {
      expect(shareOfTotal(_group(), MetricKind.cpu, 32768), isNull);
      expect(shareOfTotal(_group(), MetricKind.gpu, 32768), isNull);
    });

    test('sin total conocido no se inventa nada', () {
      expect(shareOfTotal(_group(), MetricKind.ram, null), isNull);
      expect(shareOfTotal(_group(), MetricKind.ram, 0), isNull);
    });
  });
}
