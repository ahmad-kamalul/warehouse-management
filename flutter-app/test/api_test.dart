import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warehouse_mobile/core/api_client.dart';
import 'package:warehouse_mobile/data/api_warehouse_repository.dart';
import 'package:warehouse_mobile/domain/models.dart';

void main() {
  test(
    'login token is attached to paginated inventory and cleared on logout',
    () async {
      final client = ApiClient(
        baseUrl: 'https://warehouse.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            expect(jsonDecode(request.body)['email'], 'a@example.com');
            expect(request.headers.containsKey('Authorization'), isFalse);
            return http.Response(
              jsonEncode({
                'accessToken': 'token',
                'user': {'name': 'Alex', 'email': 'a@example.com'},
              }),
              200,
            );
          }
          expect(request.url.path, '/api/items');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(request.url.queryParameters['lowStock'], 'true');
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            '{"content":[],"totalElements":0,"totalPages":0}',
            200,
          );
        }),
      );
      final repo = ApiWarehouseRepository(client);
      await repo.authenticate(email: ' a@example.com ', password: 'password');
      await repo.list(const InventoryQuery(lowStock: true, page: 2));
      repo.signOut();
      expect(client.token, isNull);
      repo.dispose();
    },
  );
  test('field errors and conflict status survive transport', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          '{"message":"Duplicate SKU","errors":{"sku":"Already exists"}}',
          409,
        ),
      ),
    );
    await expectLater(
      api.request('POST', '/items'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.fields['sku'], 'SKU error', 'Already exists'),
      ),
    );
    api.close();
  });
  test('204 deletion succeeds without decoding an empty body', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('', 204)),
    );
    expect(await api.request('DELETE', '/items/1'), isNull);
    api.close();
  });
  test('network errors become actionable messages', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      api.request('GET', '/items'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Cannot reach'),
        ),
      ),
    );
    api.close();
  });
}
