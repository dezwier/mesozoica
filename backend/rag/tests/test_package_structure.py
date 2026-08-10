"""Keep the public package as three independent, readable subpackages."""

import ast
from pathlib import Path


PACKAGE = Path(__file__).parents[1] / "src" / "mesozoica_ai"
SUBPACKAGES = {"sources", "knowledge", "rag"}


def test_only_three_source_subpackages_exist():
    directories = {
        path.name
        for path in PACKAGE.iterdir()
        if path.is_dir() and not path.name.startswith("__")
    }
    assert directories == SUBPACKAGES
    assert {path.name for path in PACKAGE.glob("*.py")} == {"__init__.py"}
    assert (PACKAGE / "py.typed").is_file()


def test_subpackages_do_not_import_each_other():
    for owner in SUBPACKAGES:
        forbidden = {f"mesozoica_ai.{name}" for name in SUBPACKAGES - {owner}}
        for path in (PACKAGE / owner).rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            imported: set[str] = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imported.update(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.module:
                    imported.add(node.module)
            assert not any(
                name == blocked or name.startswith(blocked + ".")
                for name in imported
                for blocked in forbidden
            ), f"{path} crosses a subpackage boundary"
