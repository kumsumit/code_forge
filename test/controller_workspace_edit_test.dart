import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodeForgeController.applyWorkspaceEdit', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('code_forge_edit_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('applies changes to the open buffer and other files', () async {
      final openFile = File('${tempDir.path}/open.dart')
        ..writeAsStringSync('class OldName {}\n');
      final otherFile = File('${tempDir.path}/other.dart')
        ..writeAsStringSync('OldName make() => OldName();\n');
      final controller = CodeForgeController()..openedFile = openFile.path;

      await controller.applyWorkspaceEdit({
        'changes': {
          openFile.uri.toString(): [
            {
              'range': {
                'start': {'line': 0, 'character': 6},
                'end': {'line': 0, 'character': 13},
              },
              'newText': 'NewName',
            },
          ],
          otherFile.uri.toString(): [
            {
              'range': {
                'start': {'line': 0, 'character': 0},
                'end': {'line': 0, 'character': 7},
              },
              'newText': 'NewName',
            },
            {
              'range': {
                'start': {'line': 0, 'character': 18},
                'end': {'line': 0, 'character': 25},
              },
              'newText': 'NewName',
            },
          ],
        },
      });

      expect(controller.text, 'class NewName {}\n');
      expect(otherFile.readAsStringSync(), 'NewName make() => NewName();\n');

      controller.dispose();
    });

    test('applies nested code action documentChanges', () async {
      final openFile = File('${tempDir.path}/main.dart')
        ..writeAsStringSync('void main() {\n  print(foo);\n}\n');
      final controller = CodeForgeController()..openedFile = openFile.path;

      await controller.applyWorkspaceEdit({
        'title': 'Replace foo',
        'edit': {
          'documentChanges': [
            {
              'textDocument': {'uri': openFile.uri.toString(), 'version': 1},
              'edits': [
                {
                  'range': {
                    'start': {'line': 1, 'character': 8},
                    'end': {'line': 1, 'character': 11},
                  },
                  'newText': 'bar',
                },
              ],
            },
          ],
        },
      });

      expect(controller.text, 'void main() {\n  print(bar);\n}\n');

      controller.dispose();
    });

    test('applies raw text edit lists to the open buffer', () async {
      final openFile = File('${tempDir.path}/raw.dart')
        ..writeAsStringSync('final value = 1;\n');
      final controller = CodeForgeController()..openedFile = openFile.path;

      await controller.applyWorkspaceEdit([
        {
          'range': {
            'start': {'line': 0, 'character': 14},
            'end': {'line': 0, 'character': 15},
          },
          'newText': '2',
        },
      ]);

      expect(controller.text, 'final value = 2;\n');

      controller.dispose();
    });

    test('creates a file before applying following document edits', () async {
      final createdFile = File('${tempDir.path}/created.dart');
      final controller = CodeForgeController();

      await controller.applyWorkspaceEdit({
        'documentChanges': [
          {
            'kind': 'create',
            'uri': createdFile.uri.toString(),
            'options': {'ignoreIfExists': true},
          },
          {
            'textDocument': {'uri': createdFile.uri.toString(), 'version': 1},
            'edits': [
              {
                'range': {
                  'start': {'line': 0, 'character': 0},
                  'end': {'line': 0, 'character': 0},
                },
                'newText': 'void created() {}\n',
              },
            ],
          },
        ],
      });

      expect(createdFile.readAsStringSync(), 'void created() {}\n');

      controller.dispose();
    });

    test('renames a file before applying edits to the new uri', () async {
      final oldFile = File('${tempDir.path}/old.dart')
        ..writeAsStringSync('hello world\n');
      final newFile = File('${tempDir.path}/new.dart');
      final controller = CodeForgeController();

      await controller.applyWorkspaceEdit({
        'documentChanges': [
          {
            'kind': 'rename',
            'oldUri': oldFile.uri.toString(),
            'newUri': newFile.uri.toString(),
          },
          {
            'textDocument': {'uri': newFile.uri.toString(), 'version': 1},
            'edits': [
              {
                'range': {
                  'start': {'line': 0, 'character': 6},
                  'end': {'line': 0, 'character': 11},
                },
                'newText': 'there',
              },
            ],
          },
        ],
      });

      expect(oldFile.existsSync(), isFalse);
      expect(newFile.readAsStringSync(), 'hello there\n');

      controller.dispose();
    });

    test('deletes files from documentChanges', () async {
      final deletedFile = File('${tempDir.path}/deleted.dart')
        ..writeAsStringSync('obsolete\n');
      final controller = CodeForgeController();

      await controller.applyWorkspaceEdit({
        'documentChanges': [
          {
            'kind': 'delete',
            'uri': deletedFile.uri.toString(),
            'options': {'ignoreIfNotExists': true},
          },
        ],
      });

      expect(deletedFile.existsSync(), isFalse);

      controller.dispose();
    });

    test('accepts LSP completion textEdit and additionalTextEdits', () {
      final controller = CodeForgeController()
        ..text = '\nprintt\n'
        ..selection = const TextSelection.collapsed(offset: 7);
      controller.suggestionsNotifier.value = [
        {
          'label': 'print',
          'textEdit': {
            'range': {
              'start': {'line': 1, 'character': 0},
              'end': {'line': 1, 'character': 6},
            },
            'newText': 'print',
          },
          'additionalTextEdits': [
            {
              'range': {
                'start': {'line': 0, 'character': 0},
                'end': {'line': 0, 'character': 0},
              },
              'newText': 'import dart:core;\n',
            },
          ],
        },
      ];

      controller.acceptSuggestion();

      expect(controller.text, 'import dart:core;\n\nprint\n');

      controller.dispose();
    });
  });
}
