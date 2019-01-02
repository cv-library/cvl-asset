import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sass/sass.dart';
import 'package:watcher/watcher.dart';

bool brotli, watch, webp;

void main(List<String> args) {
  final parser = ArgParser()
    ..addSeparator("usage: cvl-asset [<flags>] <source> <destination>\n")
    ..addFlag('no-brotli', abbr: 'B', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('mount', abbr: 'm', defaultsTo: '/')
    ..addFlag('no-webp', abbr: 'W', negatable: false)
    ..addFlag('watch', abbr: 'w', negatable: false);

  String source, destination, mount;

  try {
    final result = parser.parse(args);

    brotli = !result['no-brotli'];
    mount = result['mount'];
    watch = result['watch'] as bool;
    webp = !result['no-webp'];

    source = result.rest[0];
    destination = result.rest[1];
  } catch (e) {
    print(parser.usage);
    exit(1);
  }

  source = absolute(source);
  destination = absolute(destination);

  Directory.current = source;

  List<File> files = [];

  for (var entity in Directory('').listSync(recursive: true)) {
    if (entity is File &&
        (!entity.path.endsWith('.scss') ||
            !basename(entity.path).startsWith('_'))) files.add(entity);
  }

  // Sort non-sass files first, then by name.
  files.sort((a, b) {
    final aIsSass = a.path.endsWith('.scss');
    final bIsSass = b.path.endsWith('.scss');

    if (aIsSass && !bIsSass)
      return 1;
    else if (!aIsSass && bIsSass)
      return -1;
    else
      return a.path.compareTo(b.path);
  });

  run(source, destination, mount, files);

  if (watch) {
    DirectoryWatcher(source).events.listen((e) {
      // Skip deleted files.
      if (e.type == ChangeType.REMOVE)
        return;

      // FIXME We're re-running everything on file change
      //       and not actually detecting new files!
      run(source, destination, mount, files);
    });
  }
}

void run(String source, String destination, String mount, List<File> files) {
  Map<String, String> manifest = Map();

  for (final file in files) {
    final path = file.path.substring(2);

    print("\x1B[0;34mProcessing $path\x1B[0m");

    List<int> bytes;
    var ext = extension(path);

    if (ext == '.scss') {
      ext = '.css';

      // TODO Build a dependency graph for watch.
      List<String> deps = [];

      final css = compile(
        path,
        functions: [
          Callable("asset-url", r"$url", (args) {
            var url = args[0].assertString("url").text;

            deps.add(url);

            // TODO Probably need to URL encode this.
            return SassString(
              'url(' + SassString(manifest[url]).toString() + ')',
              quotes: false,
            );
          }),
        ],
        loadPaths: [source],
        sourceMap: (map) => deps.addAll(map.urls),
        style: OutputStyle.compressed,
      );

      deps.removeWhere((dep) => dep == path);

      bytes = Utf8Encoder().convert(css);
    } else {
      bytes = file.readAsBytesSync();
    }

    final assetPath =
        withoutExtension(path) + '-' + md5.convert(bytes).toString() + ext;

    print("\x1B[0;32mGenerating $assetPath\x1B[0m");

    // Write the fingerprinted asset to disk.
    final asset = File(join(destination, assetPath));
    asset.createSync(recursive: true);
    asset.writeAsBytesSync(bytes, flush: true);

    switch (ext) {
      case '.css':
      case '.js':
      case '.svg':
        if (brotli) {
          final brPath = assetPath + '.br';

          print("\x1B[0;32mGenerating $brPath\x1B[0m");

          // TODO Show stderr
          Process.runSync('brotli', [join(destination, assetPath)]);
        }

        break;
      case '.png':
        if (webp) {
          final webpPath = assetPath + '.webp';

          print("\x1B[0;32mGenerating $webpPath\x1B[0m");

          // TODO Show stderr
          Process.runSync('cwebp', ['-z', '9', join(destination, assetPath), '-o', join(destination, webpPath)]);
        }

        break;
    }

    manifest[path] = mount + assetPath;
  }

  File(join(destination, 'manifest.json'))
      .writeAsBytesSync(JsonUtf8Encoder().convert(manifest), flush: true);
}
