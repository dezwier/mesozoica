from utils_ingestion import load_dinosaur, chunk_documents


if __name__ == "__main__":
    docs = load_dinosaur("Triceratops")

    print(f"Loaded {len(docs)} document(s)")
    print(f"Characters: {len(docs[0].page_content)}")
    print(f"Metadata: {docs[0].metadata}")
    print("\nFirst 500 characters:")
    print(docs[0].page_content[:500])

    chunks = chunk_documents(docs)

    print(f"\nCreated {len(chunks)} chunks")

    lengths = [len(chunk.page_content) for chunk in chunks]

    print(f"Min length: {min(lengths)}")
    print(f"Max length: {max(lengths)}")
    print(f"Average length: {sum(lengths) / len(lengths):.0f}")

    for i, chunk in enumerate(chunks[:3]):
        print(f"\n--- Chunk {i} ---")
        print(chunk.metadata)
        print(chunk.page_content[:500])