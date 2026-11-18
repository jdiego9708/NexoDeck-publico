import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/devices_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/devices_table.dart';
import 'package:nexodeck/features/pairing/data/devices_repository.dart';
import 'package:nexodeck/features/pairing/domain/manual_host.dart';
import 'package:nexodeck/features/pairing/domain/paired_device.dart';

void main() {
  late NexoDeckDatabase db;
  late DevicesRepository repository;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    repository = DevicesRepository(DevicesDao(db));
  });

  tearDown(() => db.close());

  Future<void> pair({ManualHost? manualAddress}) => repository.pairDevice(
    id: 'device-1',
    name: 'JUANDIEGO-PC',
    platform: DevicePlatform.windows,
    certFingerprint: 'AA:BB',
    manualAddress: manualAddress,
  );

  Future<PairedDevice> read() async => (await repository.watchAll().first).single;

  test('emparejar sin direccion manual la deja vacia', () async {
    await pair();
    expect((await read()).manualAddress, isNull);
  });

  // Emparejar fuera de la LAN: mDNS nunca va a encontrar esa PC, asi que si
  // la direccion no se guarda con el dispositivo la reconexion se queda sin
  // a donde ir.
  test('emparejar por direccion manual la persiste', () async {
    await pair(manualAddress: const ManualHost(host: '100.64.0.5', port: 9000));
    final device = await read();
    expect(device.manualAddress, const ManualHost(host: '100.64.0.5', port: 9000));
  });

  test('setManualAddress la agrega despues del pairing', () async {
    await pair();
    await repository.setManualAddress(
      'device-1',
      const ManualHost(host: 'mi-pc.ts.net', port: kDefaultTransportPort),
    );
    expect((await read()).manualAddress?.host, 'mi-pc.ts.net');
  });

  test('setManualAddress con null la borra', () async {
    await pair(manualAddress: const ManualHost(host: '100.64.0.5', port: 9000));
    await repository.setManualAddress('device-1', null);
    expect((await read()).manualAddress, isNull);
  });

  // Mismo motivo por el que `setAuthorized` no usa `.replace()`: un update
  // por companion parcial no puede resetear las columnas ausentes.
  test('setManualAddress no pisa el resto de la fila', () async {
    await pair();
    await repository.setAuthorized('device-1', false);
    await repository.setManualAddress(
      'device-1',
      const ManualHost(host: '100.64.0.5', port: 9000),
    );

    final device = await read();
    expect(device.name, 'JUANDIEGO-PC');
    expect(device.certFingerprint, 'AA:BB');
    expect(device.isAuthorized, isFalse);
    expect(device.lastTransportUsed, TransportType.wifi);
  });
}
