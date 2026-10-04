# SwiftNARACatalogBulkDemo

An offline command-line example using original recorded NARA responses. It lists the recorded authority-records directory and prints each discovered partition, then walks two manifest pages, stops without prefetch, saves the FDR shard through the streaming download operation, then independently reads local records with NAIDs, line numbers, and byte offsets, along with each record's transcription count and its machine-generated flag broken out as true, false, and not declared. It also downloads a recorded person authority shard and prints the first record's heading and authority type. It then replays a recorded 304 for the same FDR shard, printing its ETag without touching the already-saved file, and replays the recorded 200 into a second, different destination file. It makes no live request and removes its temporary shards on exit.

From the repository root:

```sh
swift run --package-path Examples/SwiftNARACatalogBulkDemo SwiftNARACatalogBulkDemo "$PWD/Sources/SwiftNARACatalogBulkTestSupport/Fixtures"
```

Requires Swift 6.2 or later and macOS 26 or Linux. For live operation, supply a real transport, your application identity, and a retrieval clock to `CatalogBulkClient`.

The range example replays an attributed 32-byte interval separately from the complete-file
example, prints its offset and full-source length, and removes the temporary fragment afterward.
It performs no live request, persistence, retry, or resume.

A separately labeled synthetic resume example retains a four-byte checkpoint after a refused HTTP 200, reloads it from an older caller checkpoint, publishes eight exact bytes, and explicitly discards the owned partial and sidecar. No live request is made.

A complete 229-byte ZIP fixture is locally authored, not a provider capture. The archive example verifies whole acquisition and archive resume under explicit byte/disk limits, compares complete SHA-256, and discards retained state without extracting entries.
