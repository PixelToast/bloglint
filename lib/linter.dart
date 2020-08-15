import 'dart:html';

import 'package:bloglint/lines.dart';
import 'package:tuple/tuple.dart';

abstract class Linter {
  Element codeElement;
  String src;

  List<Node> buf = [];

  void addText(String text) {
    buf.add(Text(text));
  }

  void token(String token, String text) {
    buf.add(
      SpanElement()
        ..classes.add('token')
        ..classes.add(token)
        ..text = text
    );
  }

  void regexTokens(String text, List<Tuple2<String, String>> tokens, {Element code}) {
    var index = 0;
    var regex = { for (var e in tokens) e.item1 : RegExp(e.item1) };

    while (index < text.length) {
      var success = false;
      for (var e in tokens) {
        var m = regex[e.item1].matchAsPrefix(text, index);
        if (m != null) {
          token(e.item2, m.group(0));
          index += m.end - m.start;
          success = true;
          break;
        }
      }
      if (!success) {
        addText(text.substring(index, index + 1));
        index++;
      }
    }
  }

  int addARM(String src) {
    var m = RegExp('(\\w+)(.+?)\$').firstMatch(src);
    if (m == null) {
      addText(src);
      return null;
    }

    const suffixes = {
      'eq', 'ne', 'cs', 'hs',
      'cc', 'lo', 'mi', 'pl',
      'vs', 'vc', 'hi', 'ls',
      'ge', 'lt', 'gt', 'le',
      'al',
    };

    const sfconflict = {
      'movt', 'movs', 'bics',
      'rscs', 'sbcs', 'adcs',
    };

    var iname = m.group(1);
    if (
      !sfconflict.contains(iname) &&
      iname.length > 2 &&
      suffixes.contains(iname.substring(iname.length - 2, iname.length))
    ) {
      var name = iname.substring(0, iname.length - 2);
      token('keyword', name);
      token('variable', iname.substring(iname.length - 2, iname.length));
      iname = name;
    } else {
      token('keyword', iname);
    }

    regexTokens(m.group(2), [
      Tuple2('(;|//)(.*)', 'comment'),
      Tuple2(r'[A-Za-z]\w*', 'function'),
      Tuple2(r'#?[\+\-]?(0x[0-9a-fA-F]+|[0-9]+)', 'number'),
    ]);

    if (iname == 'b') {
      var om = RegExp(r'\s*(\S+)').matchAsPrefix(m.group(2));
      return om == null ? null : int.tryParse(om.group(1));
    }
    return null;
  }

  void commit() {
    codeElement.nodes.addAll(buf);
    buf.clear();
  }

  Element commitDiv() {
    var div = DivElement()..nodes.addAll(buf);
    buf.clear();
    codeElement.children.add(div);
    return div;
  }

  void lint();

  static final registry = {
    'shell': () => ShellLinter(),
    'cluster-tbl': () => ClusterTblLinter(),
    'reg-tbl': () => RegTblLinter(),
    'dartvm-dasm': () => DartVMDasmLinter(),
    'dartdec-dasm': () => DartDecLinter(),
  };
}

class ShellLinter extends Linter {
  void lint() {
    for (var line in src.split('\n')) {
      var m = RegExp('(\\S+):(\\S+)\\\$ ([\\S\\s]+)').matchAsPrefix(line);
      if (m != null) {
        token('function', m.group(1));
        addText(':');
        token('builtin', m.group(2));
        addText('\$ ${m.group(3)}');
      } else {
        addText(line);
      }
      addText('\n');
    }
  }
}

class ClusterTblLinter extends Linter {
  void lint() {
    var lines = src.split('\n');
    addText(lines[0]);
    addText('\n');
    addText(lines[1]);
    addText('\n');
    for (var i = 2; i < lines.length; i++) {
      var m = RegExp('(.+)\\|(.+)\\|(.+)\\|(.+)').matchAsPrefix(lines[i]);
      if (m == null) {
        addText(lines[i]);
      } else {
        token('number', m.group(1));
        addText('|');
        token('number', m.group(2));
        addText('|');
        token('class-name', m.group(3));
        addText('|');
        token('builtin', m.group(4));
      }
      addText('\n');
    }
  }
}

class RegTblLinter extends Linter {
  void lint() {
    var lines = src.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var m = RegExp('(.+)\\|(.+)\\|(.+)').matchAsPrefix(lines[i]);
      if (m == null) {
        addText(lines[i]);
      } else {
        for (var m in RegExp('(\\-|[^-]+)').allMatches(m.group(1))) {
          var t = m.group(1);
          if (t == '-') {
            token('comment', t);
          } else {
            token('function', t);
          }
        }
        addText('|');
        token('function', m.group(2));
        addText('|');
        token('comment', m.group(3));
      }
      addText('\n');
    }
  }
}

class DartVMDasmLinter extends Linter {
  void lint() {
    for (var l in src.split('\n')) {
      var m = RegExp('(C.+)(\'.+\') {').matchAsPrefix(l);
      if (m != null) {
        addText(m.group(1));
        token('string', m.group(2));
        addText(' {\n');
        continue;
      }
      m = RegExp('\\s+;;.+').matchAsPrefix(l);
      if (m != null) {
        token('comment', m.group(0));
        addText('\n');
        continue;
      }
      m = RegExp('(0x\\S+\\s+\\S+\\s+)(.+)').matchAsPrefix(l);
      if (m != null) {
        token('symbol', m.group(1));
        addARM(m.group(2));
        addText('\n');
        continue;
      }
      addText(l);
      addText('\n');
    }
  }
}

class DartDecLinter extends Linter {
  void lint() {
    var lineHeightText = codeElement.getComputedStyle().lineHeight.replaceAll('px', '').trim();
    var lineHeight = lineHeightText == '' ? 21.0 : double.parse(lineHeightText);
    lineHeight = (lineHeight - 0.5).floorToDouble();

    var offsets = <int, int>{};
    var jumps = <int, int>{};
    var lines = src.split('\n');
    var zoomText = document.body.getComputedStyle().zoom.replaceAll('px', '').trim();
    var zoom = zoomText == '' ? 1.0 : double.parse(zoomText);
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      var m = RegExp('([0-9a-fA-F]+) \\| (.+)').matchAsPrefix(l);
      if (m != null) {
        token('symbol', m.group(1));
        addText(' | ');
        var jump = addARM(m.group(2));
        var div = commitDiv()
          ..style.height = '${lineHeight}px';

        var offset = int.parse(m.group(1), radix: 16);
        offsets[offset] = div.clientHeight + div.documentOffset.y - codeElement.documentOffset.y;
        if (jump != null) {
          jumps[offset] = jump + offset;
        }

        continue;
      }
      m = RegExp('(.*)(//.*)').matchAsPrefix(l);
      if (m != null) {
        addText(m.group(1));
        token('comment', m.group(2));
        commitDiv()
          ..style.height = '${lineHeight}px';
        continue;
      }
      addText(l);
      commitDiv()
        ..style.height = '${lineHeight}px';
    }

    if (jumps.isEmpty) return;

    var pre = codeElement.parent;
    codeElement.remove();
    var canvas = CanvasElement();
    var row = DivElement()
      ..children.add(canvas)
      ..children.add(codeElement)
      ..style.display = 'flex'
      ..style.flexDirection = 'row';
    pre.children.add(row);

    var halfHeight = lineHeight / 2;
    var splitHeight = lineHeight / 4;

    var stack = LineStack();

    var jumpKeys = [];
    for (var j in jumps.entries) {
      stack.addLine(j.key, j.value);
      jumpKeys.add(j.key);
    }

    var stackOffsets = stack.toList();
    var drewTo = <int>{};

    var enters = <int>{};
    var exits = <int>{};
    var split = <int>{};
    for (var i = 0; i < jumpKeys.length; i++) {
      var from = jumpKeys[i];
      enters.add(from);
      if (exits.contains(from)) split.add(from);

      var to = jumps[from];
      exits.add(to);
      if (enters.contains(to)) split.add(to);
    }

    var canvasScale = window.devicePixelRatio;
    var cwidth = stack.stack.length * 4 + 22;
    canvas
      ..width = (cwidth * canvasScale).round()
      ..height = (canvas.clientHeight * canvasScale).round()
      ..style.width = '${cwidth}px'
      ..style.height = '${canvas.clientHeight.round()}px'
      ..style.marginRight = '8px';

    var ctx = canvas.context2D;

    ctx.scale(canvasScale, canvasScale);

    ctx.lineWidth = 2;
    ctx.strokeStyle = '#ccc';
    ctx.fillStyle = '#ccc';

    for (var i = 0; i < jumpKeys.length; i++) {
      var from = jumpKeys[i];
      var to = jumps[from];
      var half = drewTo.contains(to);

      drewTo.add(to);
      ctx.beginPath();

      var offset = stackOffsets[i] * 8 + 16.0;
      offset = (offset - 0.5).roundToDouble();

      var starty = offsets[from] - halfHeight;
      if (split.contains(from)) starty += splitHeight;
      starty = (starty - 0.5).roundToDouble();

      // ctx.fillText('$i', 0, starty);

      var endy = offsets[to] - halfHeight;
      if (split.contains(to)) endy -= splitHeight;
      ctx.moveTo(cwidth, starty);
      endy = (endy - 0.5).roundToDouble();

      var bwd = starty > endy ? -16 : 16;
      var x = cwidth - offset;

      ctx.arcTo(x, starty, x, starty + bwd, 8);
      ctx.arcTo(x, endy, x + cwidth, endy, 8);
      if (!half) {
        ctx.lineTo(cwidth - 4, endy);
      }
      ctx.stroke();

      if (!half) {
        ctx.beginPath();
        ctx.moveTo(cwidth - 6, endy - 4);
        ctx.lineTo(cwidth, endy);
        ctx.lineTo(cwidth - 6, endy + 4);
        ctx.closePath();
        ctx.fill();
      }
    }
  }
}