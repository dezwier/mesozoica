from mesozoica_ai.knowledge import (
    KnowledgeSettings,
    create_knowledge_base,
)


knowledge = create_knowledge_base(
    KnowledgeSettings()
)

results = knowledge.search(
    "Give me a child friendly quiz question about dinosaurs, with 4 answers (multiple choice)",
    #filters={"dinosaur": "Tyrannosaurus"},
    mode="vector",
    top_k=5,
)

for i, chunk in enumerate(results, 1):
    print(f"\n--- {i} ---")
    print("Score:", chunk.score)
    print("Section:", chunk.metadata.get("section"))
    print(chunk.text[:700])