import 'package:path_to_regexp_port/path_to_regexp_port.dart';
import 'package:test/test.dart';

void main() {
  test('.add()', () async {
    final keys = <Key>[];
    try {
      final hola = pathToRegexp('/a/:foo(\\d+)/:hola(c)?', keys);

      hola.hasMatch('/a/123/');
      int a = 1;
    } catch (e) {
      int a = 1;
    }
  });
}
