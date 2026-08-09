from utils_ingestion import load_wikipedia_sections, chunk_sections

# --------------------------------
# Test
# --------------------------------

docs = load_wikipedia_sections(
    "Triceratops"
)

chunks = chunk_sections(
    docs
)

print("\n==============================")
print("RESULT")
print("==============================")

print("Sections:", len(docs))
print("Chunks:", len(chunks))


# Show some example chunks
for chunk in chunks[:15]:

    print("\n--------------------")

    print(
        "ID:",
        chunk.metadata["chunk_id"],
    )

    print(
        "Section:",
        chunk.metadata["section"],
    )

    print(
        chunk.page_content[:300]
    )