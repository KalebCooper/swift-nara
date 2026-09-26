# SwiftNARACatalogBulkDemo

An offline command-line example using original recorded NARA responses. It lists the recorded authority-records directory and prints each discovered partition, then walks two manifest pages, stops without prefetch, saves the FDR shard through the streaming download operation, then independently reads local records with NAIDs, line numbers, and byte offsets, along with each record's transcription count and its machine-generated flag broken out as true, false, and not declared. It also downloads a recorded person authority shard and prints the first record's heading and authority type. It makes no live request and removes its temporary shards on exit.

From the repository root:

```sh
swift run --package-path Examples/SwiftNARACatalogBulkDemo SwiftNARACatalogBulkDemo "$PWD/Sources/SwiftNARACatalogBulkTestSupport/Fixtures"
```

Requires Swift 6.2 or later and macOS 26 or Linux. For live operation, supply a real transport, your application identity, and a retrieval clock to `CatalogBulkClient`.
