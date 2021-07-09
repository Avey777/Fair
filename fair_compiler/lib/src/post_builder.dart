/*
 * Copyright (C) 2005-present, 58.com.  All rights reserved.
 * Use of this source code is governed by a BSD type license that can be
 * found in the LICENSE file.
 */

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:path/path.dart' as path;

import 'helper.dart' show FlatCompiler;

class ArchiveBuilder extends PostProcessBuilder with FlatCompiler {
  @override
  FutureOr<void> build(PostProcessBuildStep buildStep) async {
    final dir = path.join('build', 'fair');
    Directory(dir).createSync(recursive: true);
    final bundleName = path.join(
        dir,
        buildStep.inputId.path
            .replaceAll(inputExtensions.first, '.fair.json')
            .replaceAll('/', '_')
            .replaceAll('\\', '_'));
    final jsName = bundleName.replaceFirst('.json', '.js');
    await dart2JS(buildStep.inputId.path, jsName);

    final bytes = await buildStep.readInputAsBytes();
    final file = File(bundleName)..writeAsBytesSync(bytes);
    if (file.lengthSync() > 0) {
      buildStep.deletePrimaryInput();
    }
    var bin = await compile(file.absolute.path);
    if (bin.success) {
      print('[Fair] FlatBuffer format generated for ${file.path}');
    }
    final buffer = StringBuffer();
    buffer.writeln('# Generated by Fair on ${DateTime.now()}.\n');
    final source =
        buildStep.inputId.path.replaceAll(inputExtensions.first, '.dart');
    buffer.writeln('source: ${buildStep.inputId.package}|$source');
    final digest = md5.convert(bytes).toString();
    buffer.writeln('md5: $digest');
    buffer.writeln('json: ${buildStep.inputId.package}|${file.path}');
    if (bin.success) {
      buffer.writeln('bin: ${buildStep.inputId.package}|${bin.data}');
    }
    buffer.writeln('date: ${DateTime.now()}');
    File('${bundleName.replaceAll('.json', '.metadata')}')
        .writeAsStringSync(buffer.toString());

    print('[Fair] New bundle generated => ${file.path}');

    // 压缩下发产物
    var zipPath  = path.join(Directory.current.path, 'build', 'fair');
    _zip(Directory(zipPath), File('./build/fair/fair_patch.zip'));
  }

  @override
  Iterable<String> get inputExtensions => ['.bundle.json'];

  void dart2JS(String input, String jsName) async {
    var result = await Process.run('which', ['dart']);
    var bin = StringBuffer();
    bin.write(result.stdout);
    var strBin = bin.toString();
    var dirEndIndex = strBin.lastIndexOf(Platform.pathSeparator);
    var binDir = strBin.substring(0, dirEndIndex);
    var partPath  = path.join(Directory.current.path, input.replaceFirst('.bundle.json', '.js.dart'));
    print('\u001b[33m [Fair Dart2JS] partPath => ${partPath} \u001b[0m');
    if (File(partPath).existsSync()) {
      var transferPath  = path.join(Directory.current.parent.parent.path, 'fair_compiler', 'lib', 'entry.aot');
      print('\u001b[33m [Fair Dart2JS] transferPath => ${transferPath} \u001b[0m');
      print(
          '\u001b[33m [Fair Dart2JS] dartaotruntime path => ${binDir}/dartaotruntime \u001b[0m');
      print(
          '\u001b[33m [Fair Dart2JS] jsName => ${jsName} \u001b[0m');
      try {
        result =
            await Process.run('$binDir/dartaotruntime', [transferPath, '--compress', partPath]);
        File(jsName)..writeAsString(result.stdout.toString());
      } catch(e) {
        print(
            '[Fair Dart2JS] e => ${e}');
      }
    }
  }

  void _zip(Directory data, File zipFile) {
    final Archive archive = Archive();
    for (FileSystemEntity entity in data.listSync(recursive: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path.endsWith('.js') || entity.path.endsWith('.json')) {
        final File file = entity as File;
        var filename = file.path.split("/").last;
        final List<int> bytes = file.readAsBytesSync();
        archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      }
    }
    zipFile.writeAsBytesSync(ZipEncoder().encode(archive), flush: false);
  }

}
