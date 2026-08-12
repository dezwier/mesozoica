from mesozoica_ai.common.inventory import (
    KnowledgeOverview,
    StoreCounts,
    azure_knowledge_overview_from_rows,
    azure_store_counts_from_rows,
    knowledge_overview_from_embedded_rows,
    knowledge_overview_from_sql_rows,
    overview_drift_lines,
)


def test_azure_knowledge_overview_from_rows():
    overview = azure_knowledge_overview_from_rows(
        [
            {"id": "1", "subject_id": "dinosaur:1", "source": "wikipedia", "source_id": "wiki-1"},
            {"id": "2", "subject_id": "dinosaur:1", "source": "wikipedia", "source_id": "wiki-1"},
            {"id": "3", "subject_id": "dinosaur:1", "source": "openalex", "source_id": "W1"},
            {"id": "4", "subject_id": "dinosaur:1", "source": "openalex", "source_id": "W1"},
            {"id": "5", "subject_id": "dinosaur:2", "source": "openalex", "source_id": "W2"},
        ]
    )
    assert overview == KnowledgeOverview(
        dinosaurs=2,
        wikipedia_dinos=1,
        wikipedia_units=2,
        openalex_dinos=2,
        openalex_papers=2,
        openalex_units=3,
        unit_label="chunks",
    )
    lines = overview.log_lines(title="In Azure Search")
    assert lines[0] == "=== In Azure Search ==="
    assert "2 paper(s)" in lines[1]
    # Per-source log helper used by acquire/embed/ingest scripts.
    class _Capture:
        def __init__(self) -> None:
            self.messages: list[str] = []

        def info(self, msg: str, *args) -> None:
            self.messages.append(msg % args if args else msg)

    capture = _Capture()
    overview.log(capture, prefix="inventory Azure")
    assert capture.messages[0] == "inventory Azure: 2 dino(s)"
    assert "wikipedia: 1 dino(s) / 2 chunks" in capture.messages[1]
    assert "openalex: 2 dino(s) / 2 paper(s) / 3 chunks" in capture.messages[2]


def test_overview_drift_lines_flag_paper_mismatch():
    sql = KnowledgeOverview(
        dinosaurs=12,
        wikipedia_dinos=12,
        wikipedia_units=92,
        openalex_dinos=11,
        openalex_papers=82,
        openalex_units=457,
        unit_label="chunks",
    )
    azure = KnowledgeOverview(
        dinosaurs=12,
        wikipedia_dinos=12,
        wikipedia_units=159,
        openalex_dinos=10,
        openalex_papers=71,
        openalex_units=1249,
        unit_label="chunks",
    )
    lines = overview_drift_lines(sql, azure, left_name="Embedded", right_name="Azure")
    assert any("openalex papers: Embedded=82 Azure=71" in line for line in lines)
    assert any("behind Embedded" in line for line in lines)


def test_sql_knowledge_overview_counts_papers_and_sections():
    class Row:
        def __init__(self, subject_id, source, documents):
            self.subject_id = subject_id
            self.source = source
            self.documents = documents

    overview = knowledge_overview_from_sql_rows(
        [
            Row(
                "1",
                "wikipedia",
                [{"metadata": {"source_id": "w", "title": "T"}}, {"metadata": {}}],
            ),
            Row(
                "1",
                "openalex",
                [
                    {"metadata": {"source_id": "W1", "title": "A"}},
                    {"metadata": {"source_id": "W1", "title": "A"}},
                    {"metadata": {"source_id": "W2", "title": "B"}},
                ],
            ),
        ]
    )
    assert overview.dinosaurs == 1
    assert overview.wikipedia_dinos == 1
    assert overview.wikipedia_units == 2
    assert overview.openalex_dinos == 1
    assert overview.openalex_papers == 2
    assert overview.openalex_units == 3
    assert overview.unit_label == "sections"


def test_embedded_overview_counts_chunks_and_papers():
    class Row:
        def __init__(self, subject_id, source, embedded_chunks):
            self.subject_id = subject_id
            self.source = source
            self.embedded_chunks = embedded_chunks

    overview = knowledge_overview_from_embedded_rows(
        [
            Row(
                "1",
                "wikipedia",
                [{"id": "c1", "metadata": {}}, {"id": "c2", "metadata": {}}],
            ),
            Row(
                "1",
                "openalex",
                [
                    {"id": "c3", "metadata": {"source_id": "W1"}},
                    {"id": "c4", "metadata": {"source_id": "W1"}},
                    {"id": "c5", "metadata": {"source_id": "W2"}},
                ],
            ),
        ]
    )
    assert overview.dinosaurs == 1
    assert overview.wikipedia_units == 2
    assert overview.openalex_papers == 2
    assert overview.openalex_units == 3
    assert overview.unit_label == "chunks"
    assert "chunks" in overview.summary_line()


def test_azure_store_counts_from_rows():
    counts = azure_store_counts_from_rows(
        [
            {
                "id": "1",
                "subject_id": "dinosaur:1",
                "source": "wikipedia",
                "source_id": "wiki-1",
                "document_id": "doc-a",
            },
            {
                "id": "2",
                "subject_id": "dinosaur:1",
                "source": "wikipedia",
                "source_id": "wiki-1",
                "document_id": "doc-a",
            },
            {
                "id": "3",
                "subject_id": "dinosaur:1",
                "source": "openalex",
                "source_id": "W1",
                "document_id": "doc-b",
            },
            {
                "id": "4",
                "subject_id": "dinosaur:2",
                "source": "openalex",
                "source_id": "W2",
                "document_id": "doc-c",
            },
        ]
    )
    assert counts == StoreCounts(dinosaurs=2, sources=3, docs=3, chunks=4)
    assert "2 unique dino(s)" in counts.summary_line()
    assert "3 source-row(s)" in counts.summary_line()
