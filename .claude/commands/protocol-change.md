Make a wire-protocol change the way this project requires ($ARGUMENTS describes it):

1. Specify it in `protocol/PROTOCOL.md` first: message table, field layout (binary: headerLength, append-only) or JSON shape, feature name for negotiation, who sends it and when. New types after 1.0 are IGNORABLE.
2. Mac: `mac/Sources/GingaProtocol` (Messages, MessageCodec, TestVectors: add a named vector), then the session code, with tests.
3. Regenerate vectors: `cd mac && swift build --product ginga && .build/debug/ginga protocol-vectors --out ../protocol/test-vectors`.
4. Android: codec + GoldenVectorTest must pass with the new vector (hand the exact PROTOCOL.md sections and vector names to the Android agent if another agent owns android/).
5. `scripts/check-all.sh`. Update `docs/status.md` and the affected docs.
