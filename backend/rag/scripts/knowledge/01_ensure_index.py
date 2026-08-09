from mesozoica_ai.knowledge import (
    KnowledgeSettings,
    create_knowledge_index,
)


RECREATE = True


settings = KnowledgeSettings()

index = create_knowledge_index(settings)

if RECREATE:
    index.recreate()
    print(f"Recreated index: {settings.search_index}")
else:
    index.ensure()
    print(f"Index ready: {settings.search_index}")