"""Keep package root as __init__ only; everything else lives in clean subpackages."""

import ast
import importlib
from pathlib import Path


PACKAGE = Path(__file__).parents[1] / "src" / "mesozoica_ai"
PACKAGES = {"common", "sources", "index", "generate", "evaluate"}


def test_root_contains_only_init_and_typed_marker():
    directories = {
        path.name
        for path in PACKAGE.iterdir()
        if path.is_dir() and not path.name.startswith("__")
    }
    assert directories == PACKAGES
    assert {path.name for path in PACKAGE.glob("*") if path.is_file()} == {
        "__init__.py",
        "py.typed",
    }


def test_root_public_surface_is_pipeline_callables():
    root = importlib.import_module("mesozoica_ai")
    assert set(root.__all__) == {
        "AiConfig",
        "chunk_documents",
        "embed_chunks",
        "embed_query",
        "ensure_index",
        "index_chunks",
        "prompt_rag",
        "retrieve_chunks",
        "retrieve_openalex",
        "sync_documents",
    }


def test_feature_packages_only_depend_on_allowed_peers():
    """sources→common; index→common; generate→common+index; evaluate→common+index."""
    allowed = {
        "sources": {"mesozoica_ai.common"},
        "index": {"mesozoica_ai.common"},
        "generate": {"mesozoica_ai.common", "mesozoica_ai.index"},
        "evaluate": {"mesozoica_ai.common", "mesozoica_ai.index"},
    }
    for owner, allowed_for in allowed.items():
        for path in (PACKAGE / owner).rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            imported: set[str] = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imported.update(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.module:
                    imported.add(node.module)
            peer_hits = [
                name
                for name in imported
                if name.startswith("mesozoica_ai.")
                and name != f"mesozoica_ai.{owner}"
                and not name.startswith(f"mesozoica_ai.{owner}.")
                and not any(
                    name == allowed or name.startswith(allowed + ".")
                    for allowed in allowed_for
                )
                and name != "mesozoica_ai"
            ]
            assert not peer_hits, f"{path} imports peers {peer_hits}"


def test_domain_packages_export_expected_helpers():
    common = importlib.import_module("mesozoica_ai.common")
    assert {"store_documents", "acquire_knowledge"} <= set(common.__all__)
    sources = importlib.import_module("mesozoica_ai.sources")
    assert set(sources.__all__) == {"retrieve_openalex"}
    index = importlib.import_module("mesozoica_ai.index")
    assert "index_knowledge" in index.__all__
    assert "embed_knowledge" in index.__all__
    assert "ingest_knowledge" in index.__all__
    generate = importlib.import_module("mesozoica_ai.generate")
    assert {"generate_quiz", "answer_from_index", "answer_question", "prompt_rag", "GroundedAnswer"} <= set(
        generate.__all__
    )
    evaluate = importlib.import_module("mesozoica_ai.evaluate")
    assert {"evaluate_knowledge", "evaluate_against_index", "prepare_retrieval_cases"} <= set(
        evaluate.__all__
    )
    assert "FoundryRagEvaluator" not in evaluate.__all__
