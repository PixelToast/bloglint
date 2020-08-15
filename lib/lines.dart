import 'dart:math';

import 'package:tuple/tuple.dart';

Tuple2<int, int> lineNormal(Tuple2<int, int> x) {
  if (x.item1 > x.item2) return Tuple2(x.item2, x.item1);
  return x;
}

bool lineOverlap(Tuple2<int, int> a, Tuple2<int, int> b) {
  a = lineNormal(a);
  b = lineNormal(b);
  return a.item2 > b.item1 && b.item2 > a.item1;
}

bool linesOverlap(List<Tuple2<int, int>> lines, Tuple2<int, int> x) =>
    lines.any((e) => lineOverlap(e, x));

int lineLength(Tuple2<int, int> x) {
  x = lineNormal(x);
  return x.item2 - x.item1;
}

class LineStack<T> {
  List<Tuple2<int, int>> lines = [];
  List<Set<int>> stack = [];

  bool overlaps(int a, int b) {
    if (lines[a].item2 == lines[b].item2) return false;
    var al = lineNormal(lines[a]);
    var bl = lineNormal(lines[b]);
    return al.item2 > bl.item1 && bl.item2 > al.item1;
  }

  int addLine(int start, int end) {
    var i = lines.length;
    lines.add(Tuple2(start, end));
    insert(i, 0);
    return i;
  }

  void insert(int line, int at) {
    var j = at;
    var take = <int>{};

    while (true) {
      if (j == stack.length) {
        stack.add({});
        break;
      }

      for (var e in stack[j].where((e) => lines[e].item2 == lines[line].item2).toList()) {
        stack[j].remove(e);
        take.add(e);
      }

      var ovr = stack[j].where((e) => overlaps(e, line)).toList();

      if (ovr.isNotEmpty) {
        var mn = ovr.map((e) => lineNormal(lines[e]).item1).reduce(min);
        var mx = ovr.map((e) => lineNormal(lines[e]).item2).reduce(max);
        var mln = mx - mn;
        var ln = lineLength(lines[line]);

        if (ln < mln || (ln == mln && lines[ovr.first].item1 > lines[line].item1)) {
          for (var e in ovr) {
            stack[j].remove(e);
            insert(e, j + 1);
          }
          break;
        }
      } else {
        break;
      }

      j++;
    }

    for (var i = j + 1; i < stack.length; i++) {
      if (stack[i].any((e) => lines[e].item2 == lines[line].item2)) {
        j = i;
        break;
      }
    }

    take.forEach(stack[j].add);

    stack[j].add(line);
  }

  List<int> toList() {
    var l = <Tuple2<int, int>>[];
    for (var s = 0; s < stack.length; s++) {
      for (var e in stack[s]) {
        l.add(Tuple2(s, e));
      }
    }
    assert(l.length == lines.length);
    l.sort((a, b) => a.item2.compareTo(b.item2));
    return l.map((e) => e.item1).toList();
  }
}