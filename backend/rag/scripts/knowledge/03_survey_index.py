from mesozoica_ai.knowledge import (
    KnowledgeSettings,
    create_knowledge_inspector,
)





settings = KnowledgeSettings()


inspector = create_knowledge_inspector(settings)
inspector.overview()
overview = inspector.overview()

print("Chunks:", overview["chunks"])

print("\nSources")
for name, count in overview["sources"].items():
    print(f"{count:4}  {name}")

print("\nDinosaurs")
for name, count in overview["dinosaurs"].items():
    print(f"{count:4}  {name}")

print("\nSections")
for name, count in overview["sections"].items():
    print(f"{count:4}  {name}")