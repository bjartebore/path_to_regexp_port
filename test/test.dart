import 'package:path_to_regexp_port/path_to_regexp_port.dart';
import 'package:test/test.dart';

void main() {
  test('optional paths', () async {
    final keys = <Key>[];
    final matcher =
        pathToRegexp('/products/(category)?/(group)?/(model)?', keys);

    expect(matcher.hasMatch('/products'), isTrue);
    expect(matcher.hasMatch('/products/category'), isTrue);
    expect(matcher.hasMatch('/products/category/group'), isTrue);
  });
}
