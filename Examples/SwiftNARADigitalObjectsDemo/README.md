# SwiftNARADigitalObjectsDemo

An offline example that streams the attributed FDR JPEG, reads its IIIF information,
and downloads the recorded 200-pixel-wide JPEG derivative. It prints separate original
and derivative byte evidence and removes only its own temporary directory.
It makes no live request. Media reuse remains subject to source rights and attribution.

Run `bash Scripts/demo-media-linux.sh` from the package root.

The range example replays an attributed 32-byte interval separately from the complete-file
example, prints its offset and full-source length, and removes the temporary fragment afterward.
It performs no live request, persistence, retry, or resume.

A separately labeled synthetic resume example retains a four-byte checkpoint after a refused HTTP 200, reloads it from an older caller checkpoint, publishes eight exact bytes, and explicitly discards the owned partial and sidecar. No live request is made.
