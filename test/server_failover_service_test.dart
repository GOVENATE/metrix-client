import 'package:flutter_test/flutter_test.dart';
import 'package:metrix_client/server_failover_service.dart';

void main() {
  group('server failover retry policy', () {
    test('retries transport and temporary server failures', () {
      for (final status in [-1, 0, 408, 425, 429, 500, 503]) {
        expect(
          ServerFailoverService.isRetryableStatus(status),
          isTrue,
          reason: 'status $status should use the fallback after retries',
        );
      }
    });

    test('does not hide client or authentication errors', () {
      for (final status in [400, 401, 403, 404, 422]) {
        expect(
          ServerFailoverService.isRetryableStatus(status),
          isFalse,
          reason: 'status $status requires configuration correction',
        );
      }
    });
  });
}
