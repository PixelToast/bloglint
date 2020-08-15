import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'package:bloglint/anchors.dart';
import 'package:bloglint/linter.dart';
import 'package:font_face_observer/font_face_observer.dart';

void start() async {
  var c = Completer();
  if (context['Prism'] != null) {
    (context['Prism']['hooks'] as JsObject).callMethod('add', [
      'before-highlightall', (env) {
        c.complete();
      }
    ]);
  } else {
    c.complete(window.animationFrame);
  }

  await Future.any([
    c.future,
    Future.delayed(Duration(seconds: 1)),
  ]);

  log('Done!');

  log('Loading monospace font...');

  await FontFaceObserver('Consolas, Monaco, "Andale Mono", "Ubuntu Mono", monospace').check();

  log('Done!');

  addAnchors();
  var codes = document.querySelectorAll('code').toList();

  log('Linting ${codes.length} code tags...');

  for (var q in codes) {
    if (q.classes.isNotEmpty && !q.classes.contains('language-plaintext')) continue;
    var text = q.innerText;
    var lmatch = RegExp('#lint (.+)\n([\\S\\s]+)').matchAsPrefix(text);

    if (lmatch == null) continue;

    q.innerHtml = '';

    var lint = lmatch.group(1);
    if (!Linter.registry.containsKey(lint)) continue;

    var linter = Linter.registry[lint]()
      ..src = lmatch.group(2).trimRight()
      ..codeElement = q;

    linter.lint();
    linter.commit();

    while (true) {
      var last = q.nodes.last;
      if (last is Text && last.data.isEmpty) {
        q.nodes.removeLast();
        continue;
      }
      break;
    }
  }

  log('Done!');
}

void main() async {
  log('Starting bloglint...');
  try {
    await start();
  } catch (e, bt) {
    log('Oh no! "$e" $bt');
  }
}

void log(Object x) {
  // print(x);
}