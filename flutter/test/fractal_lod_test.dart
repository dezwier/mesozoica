import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/fractal_tree_layout.dart';

void main() {
  group('FractalLodPolicy', () {
    test('collapses subtrees when branch is tiny on screen', () {
      expect(
        FractalLodPolicy.shouldCollapse(
          branchLength: 80,
          zoomScale: 0.05,
          hasChildren: true,
        ),
        isTrue,
      );

      expect(
        FractalLodPolicy.shouldCollapse(
          branchLength: 80,
          zoomScale: 0.05,
          hasChildren: false,
        ),
        isFalse,
      );
    });

    test('expands subtrees when branch is large enough on screen', () {
      expect(
        FractalLodPolicy.shouldCollapse(
          branchLength: 80,
          zoomScale: 0.2,
          hasChildren: true,
        ),
        isFalse,
      );
    });

    test('shows labels only at sufficient zoom', () {
      expect(
        FractalLodPolicy.shouldShowLabel(
          branchLength: 80,
          zoomScale: 0.1,
        ),
        isFalse,
      );

      expect(
        FractalLodPolicy.shouldShowLabel(
          branchLength: 80,
          zoomScale: 0.3,
        ),
        isTrue,
      );
    });

    test('genus nodes become tappable at genus threshold', () {
      expect(
        FractalLodPolicy.isGenusTappable(
          branchLength: 65,
          zoomScale: 0.15,
          isGenus: true,
        ),
        isFalse,
      );

      expect(
        FractalLodPolicy.isGenusTappable(
          branchLength: 65,
          zoomScale: 0.25,
          isGenus: true,
        ),
        isTrue,
      );

      expect(
        FractalLodPolicy.isGenusTappable(
          branchLength: 65,
          zoomScale: 0.25,
          isGenus: false,
        ),
        isFalse,
      );
    });

    test('screenLength multiplies branch length by zoom scale', () {
      expect(FractalLodPolicy.screenLength(80, 0.5), 40);
      expect(FractalLodPolicy.screenLength(100, 2), 200);
    });
  });
}
