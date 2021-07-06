/*
 * Tokenizer results.
 */

library path_to_regexp_port;

//
enum LexTokenType {
  OPEN,
  CLOSE,
  PATTERN,
  NAME,
  CHAR,
  ESCAPED_CHAR,
  MODIFIER,
  END,
}

class LexToken {
  LexToken({
    required this.type,
    required this.index,
    required this.value,
  });
  final LexTokenType type;
  final int index;
  final String value;
}

typedef Token = dynamic;

class Key {
  Key({
    required this.name,
    required this.prefix,
    required this.suffix,
    required this.pattern,
    required this.modifier,
  });
  final dynamic name;
  final String prefix;
  final String suffix;
  final String pattern;
  final String modifier;
}

String _defaultEncode(String value) => value;

/*
 * Tokenize input string.
 */
List<LexToken> lexer(String str) {
  final List<LexToken> tokens = [];
  int i = 0;

  while (i < str.length) {
    final char = str[i];

    if (char == '*' || char == '+' || char == '?') {
      tokens.add(
          LexToken(type: LexTokenType.MODIFIER, index: i, value: str[i++]));
      continue;
    }

    if (char == '\\') {
      tokens.add(
          LexToken(type: LexTokenType.ESCAPED_CHAR, index: i, value: str[i++]));
      continue;
    }

    if (char == '{') {
      tokens.add(LexToken(type: LexTokenType.OPEN, index: i, value: str[i++]));
      continue;
    }

    if (char == '}') {
      tokens.add(LexToken(type: LexTokenType.CLOSE, index: i, value: str[i++]));
      continue;
    }

    if (char == ':') {
      String name = '';
      int j = i + 1;

      while (j < str.length) {
        final code = str.codeUnitAt(j);

        if (
            // '0-9'
            (code >= 48 && code <= 57) ||
                // 'A-Z'
                (code >= 65 && code <= 90) ||
                // 'a-z'
                (code >= 97 && code <= 122) ||
                // '_'
                code == 95) {
          name += str[j++];
          continue;
        }

        break;
      }

      if (['', null].contains(name)) {
        // 'Missing parameter name at $i')
        throw TypeError();
      }

      tokens.add(LexToken(type: LexTokenType.NAME, index: i, value: name));
      i = j;
      continue;
    }

    if (char == '(') {
      int count = 1;
      String pattern = '';
      int j = i + 1;

      if (str[j] == '?') {
        // 'Pattern cannot start with "?" at ${j}'
        throw TypeError();
      }

      while (j < str.length) {
        if (str[j] == '\\') {
          pattern += str[j++] + str[j++];
          continue;
        }

        if (str[j] == ')') {
          count--;
          if (count == 0) {
            j++;
            break;
          }
        } else if (str[j] == '(') {
          count++;
          if (str[j + 1] != '?') {
            // 'Capturing groups are not allowed at ${j}'
            throw TypeError();
          }
        }

        pattern += str[j++];
      }

      if (count != 0) {
        // 'Unbalanced pattern at ${i}'
        throw TypeError();
      }
      // 'Missing pattern at ${i}'
      if ([null, ''].contains(pattern)) {
        throw TypeError();
      }

      tokens
          .add(LexToken(type: LexTokenType.PATTERN, index: i, value: pattern));
      i = j;
      continue;
    }

    tokens.add(LexToken(type: LexTokenType.CHAR, index: i, value: str[i++]));
  }

  tokens.add(LexToken(type: LexTokenType.END, index: i, value: ''));

  return tokens;
}

/*
 * Parse a string for the raw tokens.
 */
List<Token> parse(
  String str, {
  String? delimiter,
  String prefixes = './',
}) {
  final tokens = lexer(str);
  final defaultPattern = "[^${escapeString(delimiter ?? '/#?')}]+?";
  final List<Token> result = [];

  int key = 0;
  int i = 0;
  String? path = '';

  String? tryConsume(LexTokenType type) {
    if (i < tokens.length && tokens[i].type == type) {
      return tokens[i++].value;
    }
  }

  String? mustConsume(LexTokenType type) {
    final a = tokens[i];
    final value = tryConsume(type);
    if (value != null) {
      return value;
    }
    // nextType = tokens[i].type;
    // index = tokens[i].index;
    // 'Unexpected ${nextType} at ${index}, expected ${type}'
    throw TypeError();
  }

  String consumeText() {
    String result = '';
    String? value;
    // tslint:disable-next-line
    while (true) {
      value = tryConsume(LexTokenType.CHAR) ??
          tryConsume(LexTokenType.ESCAPED_CHAR);
      if (value == null) {
        break;
      }
      result += value;
    }
    return result;
  }

  while (i < tokens.length) {
    final char = tryConsume(LexTokenType.CHAR);
    final name = tryConsume(LexTokenType.NAME);
    final pattern = tryConsume(LexTokenType.PATTERN);

    if (name != null || pattern != null) {
      String? prefix = char ?? '';

      if (!prefixes.split('').contains(prefix)) {
        path = '$path$prefix';
        prefix = '';
      }

      if (path != null) {
        result.add(path);
        path = '';
      }

      result.add(Key(
          name: name ?? key++,
          prefix: prefix,
          suffix: '',
          pattern: pattern ?? defaultPattern,
          modifier: tryConsume(LexTokenType.MODIFIER) ?? ''));

      continue;
    }

    final value = char ?? tryConsume(LexTokenType.ESCAPED_CHAR);
    if (value != null) {
      path = '$path$value';
      continue;
    }

    if (path != null) {
      result.add(path);
      path = '';
    }

    final open = tryConsume(LexTokenType.OPEN);
    if (open != null) {
      final prefix = consumeText();
      final name = tryConsume(LexTokenType.NAME);
      final pattern = tryConsume(LexTokenType.PATTERN);
      final suffix = consumeText();

      mustConsume(LexTokenType.CLOSE);

      result.add(Key(
          name: name ?? (pattern != null ? key++ : ''),
          pattern: name != null && pattern == null ? defaultPattern : pattern!,
          prefix: prefix,
          suffix: suffix,
          modifier: tryConsume(LexTokenType.MODIFIER) ?? ''));

      continue;
    }

    mustConsume(LexTokenType.END);
  }

  return result;
}

/*
 * Compile a string to a template function for the path.
 */
PathFunction compile(
  String str, {
  bool sensitive = false,
  String Function(String)? encode,
  bool validate = true,
  String? delimiter,
  String prefixes = './',
}

    // options?: ParseOptions & TokensToFunctionOptions
    ) {
  return tokensToFunction(
    parse(str, prefixes: prefixes, delimiter: delimiter),
    sensitive: sensitive,
    encode: encode,
    validate: validate,
  );
}

typedef PathFunction = String Function(dynamic data);

/*
 * Expose a method for transforming tokens into the path function.
 */
PathFunction tokensToFunction(
  List<Token> tokens, {
  bool sensitive = false,
  String Function(String)? encode,
  bool validate = true,
}) {
  final encoder = encode ?? _defaultEncode;

  // Compile all the tokens into regexps.
  final matches = tokens.map((token) {
    if (token is RegExp) {
      return RegExp('^(?:${token.pattern})\$', caseSensitive: false);
    }
  });

  return (dynamic data) {
    String path = '';

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      if (token is String) {
        path += token;
        continue;
      }

      final value = data != null ? data[token.name] : null;
      final optional = token.modifier == '?' || token.modifier == '*';
      final repeat = token.modifier == '*' || token.modifier == '+';

      if (value is List) {
        if (!repeat) {
          // 'Expected "${token.name}" to not repeat, but got an array'
          throw TypeError();
        }

        if (value.isEmpty) {
          if (optional) {
            continue;
          }

          // 'Expected "${token.name}" to not be empty'
          throw TypeError();
        }

        for (var j = 0; j < value.length; j++) {
          final segment = encoder.call(value[j] as String);

          if (validate && !(matches.elementAt(i) as RegExp).hasMatch(segment)) {
            // 'Expected all "${token.name}" to match "${token.pattern}", but got "${segment}"'
            throw TypeError();
          }

          path += '${token.prefix}$segment${token.suffix}';
        }

        continue;
      }

      if (value is String || value is num) {
        final segment = encoder.call(value.toString());

        if (validate && !(matches.elementAt(i) as RegExp).hasMatch(segment)) {
          // 'Expected "${token.name}" to match "${token.pattern}", but got "${segment}"'
          throw TypeError();
        }

        path += '${token.prefix}$segment${token.suffix}';
        continue;
      }

      if (optional) {
        continue;
      }

      // final typeOfMessage = repeat ? "an array" : "a string";
      // 'Expected "${token.name}" to be ${typeOfMessage}'
      throw TypeError();
    }

    return path;
  };
}

// export interface RegexpToFunctionOptions {
//   /*
//    * Function for decoding strings for params.
//    */
//   decode?: (value: string, token: Key) => string;
// }

/*
 * A match result contains data about the path match.
 */
class MatchResult {
  MatchResult({
    required this.path,
    required this.index,
    required this.params,
  });

  final String path;
  final int index;
  final dynamic params;
}

/*
 * A match is either 'false' (no match) or a match result.
 */
typedef Match = MatchResult;

/*
 * The match function takes a string and returns whether it matched the path.
 */
typedef MatchFunction = Match? Function(String path);

/*
 * Create path match function from 'path-to-regexp' spec.
 */

dynamic match(
  dynamic str, {
  required String Function(String?, dynamic) decode,
}) {
  final List<Key> keys = [];
  final re = pathToRegexp(str, keys);
  return regexpToFunction(re, keys, decode);
}

/*
 * Create a path match function from 'path-to-regexp' output.
 */
MatchFunction regexpToFunction(
  RegExp re,
  List<Key> keys,
  String Function(String?, dynamic) decode,
  // options: RegexpToFunctionOptions = {}
) {
  // final { decode = (x: string) => x } = options;

  return (String pathname) {
    final m = re.firstMatch(pathname);
    if (m == null) {
      return null;
    }

    // final { 0: path, index } = m;

    final path = m.group(0)!;
    final index = m.start;

    final params = {};

    for (int i = 1; i < m.groupCount; i++) {
      // tslint:disable-next-line
      if (m[i] == null) {
        continue;
      }

      final key = keys[i - 1];

      if (key.modifier == '*' || key.modifier == '+') {
        params[key.name] = m[i]?.split(key.prefix + key.suffix).map((value) {
          return decode(value, key);
        });
      } else {
        params[key.name] = decode(m[i], key);
      }
    }

    return Match(
      index: index,
      path: path,
      params: params,
    );
  };
}

/*
 * Escape a regular expression string.
 */
String escapeString(String str) {
  return str.replaceAll(RegExp(r'/([.+*?=^!:${}()[\]|/\\])/g'), '\$1');
}

/*
 * Get the flags for a regexp from the options.
 */
String flags({bool sensitive = false}) {
  return sensitive ? '' : 'i';
}

/*
 * Metadata about a key.
 */
// export interface Key {
//   name: string | number;
//   prefix: string;
//   suffix: string;
//   pattern: string;
//   modifier: string;
// }

/*
 * A token is a string (nothing special) or key metadata (capture group).
 */
// export type Token = string | Key;

/*
 * Pull out keys from a regexp.
 */
RegExp regexpToRegexp({required RegExp path, List<Key>? keys}) {
  if (keys == null) {
    return path;
  }

  final groupsRegex = RegExp(r'/\((?:\?<(.*?)>)?(?!\?)/g');

  int index = 0;
  final matchResults = groupsRegex.allMatches(path.pattern);

  for (final match in matchResults) {
    keys.add(Key(
        name: match[1] ?? index++,
        prefix: '',
        suffix: '',
        modifier: '',
        pattern: ''));
  }

  return path;
}

/*
 * Transform an array into a regexp.
 */
RegExp arrayToRegexp(List<dynamic> paths, List<Key>? keys,
    {bool sensitive = false}
    // options?: TokensToRegexpOptions & ParseOptions
    ) {
  final parts = paths.map((path) => pathToRegexp(path, keys).pattern);

  return RegExp("(?:${parts.join("|")})", caseSensitive: sensitive);
}

/*
 * Create a path regexp from string input.
 */
RegExp stringToRegexp(
  String path,
  List<Key>? keys, {
  String? delimiter,
  String prefixes = './',
  bool strict = false,
  bool start = true,
  bool end = true,
  String Function(String)? encode,
}
    // options?: TokensToRegexpOptions & ParseOptions
    ) {
  return tokensToRegexp(
      parse(path, delimiter: delimiter, prefixes: prefixes), keys,
      strict: strict, start: start, end: end, encode: encode);
}

// export interface TokensToRegexpOptions {
//   /*
//    * When 'true' the regexp will be case sensitive. (default: 'false')
//    */
//   sensitive?: boolean;
//   /*
//    * When 'true' the regexp won't allow an optional trailing delimiter to match. (default: 'false')
//    */
//   strict?: boolean;
//   /*
//    * When 'true' the regexp will match to the end of the string. (default: 'true')
//    */
//   end?: boolean;
//   /*
//    * When 'true' the regexp will match from the beginning of the string. (default: 'true')
//    */
//   start?: boolean;
//   /*
//    * Sets the final character for non-ending optimistic matches. (default: '/')
//    */
//   delimiter?: string;
//   /*
//    * List of characters that can also be "end" characters.
//    */
//   endsWith?: string;
//   /*
//    * Encode path tokens for use in the 'RegExp'.
//    */
//   encode?: (value: string) => string;
// }

/*
 * Expose a function for taking tokens and returning a RegExp.
 */
RegExp tokensToRegexp(
  List<Token> tokens,
  List<Key>? keys, {
  bool strict = false,
  bool start = true,
  bool end = true,
  String? delimiter,
  String? endsWith,
  String Function(String)? encode,
  bool sensitive = false,
}) {
  final encoder = encode ?? _defaultEncode;
  final _endsWith = '[${escapeString(endsWith ?? "")}]|\$';
  final _delimiter = '[${escapeString(delimiter ?? "/#?")}]';
  String route = start ? '^' : '';

  // Iterate over the tokens and create our regexp string.
  for (final token in tokens) {
    if (token is String) {
      route += escapeString(encoder(token));
    } else if (token is Key) {
      final prefix = escapeString(encoder(token.prefix));
      final suffix = escapeString(encoder(token.suffix));

      final groupName = ![null, ''].contains(token.name) && token.name is String
          ? '?<${token.name}>'
          : '';

      if (!['', null].contains(token.pattern)) {
        if (keys != null) {
          keys.add(token);
        }

        if (!['', null].contains(prefix) || !['', null].contains(suffix)) {
          if (token.modifier == '+' || token.modifier == '*') {
            final mod = token.modifier == '*' ? '?' : '';
            route +=
                '(?:$prefix((?:${token.pattern})(?:$suffix$prefix(?:${token.pattern}))*)$suffix)$mod';
          } else {
            route +=
                '(?:$prefix($groupName${token.pattern})$suffix)${token.modifier}';
          }
        } else {
          route += '($groupName${token.pattern})${token.modifier}';
        }
      } else {
        route += '(?:$prefix$suffix)${token.modifier}';
      }
    }
  }

  if (end) {
    if (!strict) {
      route += '$_delimiter?';
    }

    route += endsWith == null ? r'$' : '(?=$_endsWith)';
  } else {
    final endToken = tokens[tokens.length - 1];
    final isEndDelimited = endToken is String
        ? delimiter?.split('').contains(endToken[endToken.length - 1])
        : // tslint:disable-next-line
        endToken == null;

    if (!strict) {
      route += '(?:$_delimiter(?=$_endsWith))?';
    }

    if (isEndDelimited == null) {
      route += '(?=$_delimiter|$_endsWith)';
    }
  }

  return RegExp(route, caseSensitive: sensitive);
}

/*
 * Supported 'path-to-regexp' input types.
 */
// typedef Path = String | RegExp | Array<String | RegExp>;

/*
 * Normalize the given path string, returning a regular expression.
 *
 * An empty array can be passed in for the keys, which will hold the
 * placeholder key descriptions. For example, using '/user/:id', 'keys' will
 * contain '[{ name: 'id', delimiter: '/', optional: false, repeat: false }]'.
 */
RegExp pathToRegexp(
  dynamic path,
  List<Key>? keys, {
  String? delimiter,
  String prefixes = './',
  bool strict = false,
  bool start = true,
  bool end = true,
  String Function(String)? encode,
  bool sensitive = false,
}
    // options?: TokensToRegexpOptions & ParseOptions
    ) {
  if (path is RegExp) {
    return regexpToRegexp(path: path, keys: keys);
  }
  if (path is List) {
    return arrayToRegexp(path, keys, sensitive: sensitive);
  }
  if (path is String) {
    return stringToRegexp(
      path,
      keys,
      delimiter: delimiter,
      prefixes: prefixes,
      strict: strict,
      start: start,
      end: end,
      encode: encode,
    );
  }
  throw TypeError();
}
