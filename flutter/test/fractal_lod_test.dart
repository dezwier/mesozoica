import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/tree/fractal_tree_layout.dart';
import 'package:mesozoica/widgets/tree/fractal_fern_painter.dart';

void main() {
  group('FractalLodPolicy', () {
    test('collapses subtrees when branch is tiny on screen', () {
      expect(
        FractalLodPolicy.shouldCollapse(
          branchLength: 80,
          zoomScale: 0.04,
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

    test('shows genus cards when branch is large enough on screen', () {
      expect(
        FractalLodPolicy.shouldShowGenusCard(
          branchLength: 80,
          zoomScale: 0.6,
          isGenus: true,
        ),
        isFalse,
      );

      expect(
        FractalLodPolicy.shouldShowGenusCard(
          branchLength: 80,
          zoomScale: 0.69,
          isGenus: true,
        ),
        isFalse,
      );

      expect(
        FractalLodPolicy.shouldShowGenusCard(
          branchLength: 80,
          zoomScale: 0.7,
          isGenus: true,
        ),
        isTrue,
      );

      expect(
        FractalLodPolicy.shouldShowGenusCard(
          branchLength: 80,
          zoomScale: 1.0,
          isGenus: true,
        ),
        isTrue,
      );
    });

    test('genusCardScreenSize grows with zoom toward catalog width', () {
      final compact = FractalLodPolicy.genusCardScreenSize(
        390,
        FractalLodPolicy.genusCardMinZoomScale,
      );
      final mid = FractalLodPolicy.genusCardScreenSize(390, 8.0);
      final full = FractalLodPolicy.genusCardScreenSize(390, 14.0);
      expect(compact.width, closeTo(390 * FractalLodPolicy.genusCardScale, 0.1));
      expect(full.width, closeTo(390, 0.1));
      expect(mid.width, lessThan(full.width * 0.65));
      expect(full.width, greaterThan(compact.width));
    });

    test('genus card title font scales with zoom', () {
      expect(
        FractalLodPolicy.genusCardTitleFontSize(14.0),
        closeTo(FractalLodPolicy.genusCardCatalogTitleFontSize, 0.1),
      );
      expect(
        FractalLodPolicy.genusCardTitleFontSize(8.0),
        lessThan(FractalLodPolicy.genusCardTitleFontSize(14.0)),
      );
      expect(
        FractalLodPolicy.genusCardTitleFontSize(8.0),
        greaterThan(FractalLodPolicy.genusCardTitleFontSize(4.0)),
      );
    });

    test('genus card shows facts only at full catalog size', () {
      expect(FractalLodPolicy.genusCardShowsFacts(4.0), isFalse);
      expect(FractalLodPolicy.genusCardShowsFacts(8.0), isFalse);
      expect(FractalLodPolicy.genusCardShowsFacts(13.9), isFalse);
      expect(FractalLodPolicy.genusCardShowsFacts(14.0), isTrue);
      expect(
        FractalLodPolicy.genusCardFactsZoomScale(),
        FractalLodPolicy.genusCardFullZoomScale,
      );
    });

    test('focusFractalTransform centers tree point in viewport', () {
      const bounds = Rect.fromLTWH(10, 20, 400, 300);
      const viewport = Size(390, 844);
      const treePoint = Offset(110, 170);
      const scale = 6.0;
      final matrix = focusFractalTransform(
        treePoint: treePoint,
        bounds: bounds,
        viewportSize: viewport,
        scale: scale,
      );
      final local = Offset(
        treePoint.dx - bounds.left,
        treePoint.dy - bounds.top,
      );
      final screen = MatrixUtils.transformPoint(matrix, local);
      expect(screen.dx, closeTo(viewport.width / 2, 0.01));
      expect(screen.dy, closeTo(viewport.height / 2, 0.01));
    });

    test('fitFractalTransform centers layout bounds in viewport', () {
      const bounds = Rect.fromLTWH(10, 20, 400, 300);
      const viewport = Size(390, 844);
      final matrix = fitFractalTransform(bounds: bounds, viewportSize: viewport);
      final local = Offset(
        bounds.center.dx - bounds.left,
        bounds.center.dy - bounds.top,
      );
      final screen = MatrixUtils.transformPoint(matrix, local);
      expect(screen.dx, closeTo(viewport.width / 2, 0.01));
      expect(screen.dy, closeTo(viewport.height / 2, 0.01));
    });

    test('lerpFractalFocusTransform ends on focused leaf', () {
      const bounds = Rect.fromLTWH(10, 20, 400, 300);
      const viewport = Size(390, 844);
      const leaf = Offset(150, 90);
      const endScale = 10.0;
      final start = fitFractalTransform(bounds: bounds, viewportSize: viewport);
      final end = lerpFractalFocusTransform(
        start: start,
        endTreePoint: leaf,
        bounds: bounds,
        viewportSize: viewport,
        endScale: endScale,
        t: 1.0,
      );
      final leafLocal = Offset(leaf.dx - bounds.left, leaf.dy - bounds.top);
      final screen = MatrixUtils.transformPoint(end, leafLocal);
      expect(screen.dx, closeTo(viewport.width / 2, 0.01));
      expect(screen.dy, closeTo(viewport.height / 2, 0.01));
      expect(end.getMaxScaleOnAxis(), closeTo(endScale, 0.01));
    });

    test('leafScreenZoomScale grows with zoom scale', () {
      expect(
        FractalLodPolicy.leafScreenZoomScale(4),
        greaterThan(FractalLodPolicy.leafScreenZoomScale(1)),
      );
    });

    test('leaf blob screen radius grows as you zoom in', () {
      final lowZoom = FractalLodPolicy.leafScreenRadius(
        leafCount: 1,
        maxLeaves: 100,
        isGenus: false,
        zoomScale: 1,
      );
      final highZoom = FractalLodPolicy.leafScreenRadius(
        leafCount: 1,
        maxLeaves: 100,
        isGenus: false,
        zoomScale: 4,
      );
      expect(highZoom, greaterThan(lowZoom * 1.8));
    });

    test('nodeZoomBoost grows with zoom scale', () {
      expect(FractalLodPolicy.nodeZoomBoost(1), 1);
      expect(
        FractalLodPolicy.nodeZoomBoost(10),
        greaterThan(FractalLodPolicy.nodeZoomBoost(1)),
      );
      expect(
        FractalLodPolicy.nodeZoomBoost(100),
        greaterThan(FractalLodPolicy.nodeZoomBoost(10)),
      );
    });
  });
}
