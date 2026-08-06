"""Fast dependency-boundary checks for the feature-first architecture."""

from __future__ import annotations

import ast
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app"


def _python_violations() -> list[str]:
    violations: list[str] = []
    feature_root = APP / "features"
    for path in feature_root.rglob("*.py"):
        owner = path.relative_to(feature_root).parts[0]
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Import, ast.ImportFrom)):
                continue
            names = [node.module] if isinstance(node, ast.ImportFrom) else [n.name for n in node.names]
            for name in filter(None, names):
                if name == "app.services" or name.startswith("app.services."):
                    violations.append(
                        f"{path.relative_to(ROOT)}: feature code cannot import the transitional app.services layer ({name})"
                    )
                    continue
                prefix = "app.features."
                if not name.startswith(prefix):
                    continue
                parts = name[len(prefix) :].split(".")
                if parts[0] != owner and (len(parts) < 2 or parts[1] != "public"):
                    violations.append(
                        f"{path.relative_to(ROOT)}: cross-feature import must use {parts[0]}.public ({name})"
                    )
    return violations


def _dart_violations() -> list[str]:
    violations: list[str] = []
    features = ROOT.parent / "flutter" / "lib" / "features"
    directive = re.compile(r"(?:import|export)\s+['\"]([^'\"]+)['\"]")
    for path in features.glob("*/**/*.dart"):
        owner = path.relative_to(features).parts[0]
        text = path.read_text(encoding="utf-8")
        for uri in directive.findall(text):
            target: Path | None = None
            package_prefix = "package:mesozoica/features/"
            if uri.startswith(package_prefix):
                target = features / uri[len(package_prefix) :]
            elif uri.startswith("."):
                target = (path.parent / uri).resolve()
            if target is None:
                continue
            try:
                relative = target.relative_to(features.resolve())
            except ValueError:
                continue
            target_owner = relative.parts[0]
            if target_owner == owner:
                continue
            allowed = relative == Path(target_owner) / f"{target_owner}.dart"
            if not allowed:
                violations.append(
                    f"{path}: cross-feature import must use {target_owner}/{target_owner}.dart ({uri})"
                )
    for layer in ("domain", "data"):
        for path in features.glob(f"*/{layer}/**/*.dart"):
            text = path.read_text(encoding="utf-8")
            if "BuildContext" in text:
                violations.append(f"{path}: {layer} code must be presentation independent")
            if "/widgets/" in text or "/screens/" in text:
                violations.append(f"{path}: {layer} code cannot import presentation folders")
    return violations


def main() -> int:
    violations = _python_violations() + _dart_violations()
    if violations:
        print("\n".join(violations))
        return 1
    print("Architecture boundaries OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
