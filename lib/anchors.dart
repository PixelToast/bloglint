import 'dart:html';

void addAnchors() {
  for (var e in querySelectorAll('.post-content h1, .post-content h2, .post-content h3')) {
    if (e.id == null) continue;
    var aTag = AnchorElement()
      ..href = '#${e.id}'
      ..nodes = e.nodes;
    e.nodes = [aTag];
  }
}