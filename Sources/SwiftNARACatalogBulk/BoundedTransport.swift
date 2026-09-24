#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import HTTPTypes
import SwiftNARACatalogBulkModels

// PageSequence uses buffered responses. Cap the bytes while receiving them, before XML decoding.
struct BoundedTransport: Transport {
  let base: any Transport
  let maximumBytes: Int

  func send(_ request: HTTPRequest, body: TransportBody, options: TransportOptions)
    async throws(TransportError) -> Response
  {
    let response = try await base.stream(request, body: body, options: options)
    var bytes = Data()
    for try await chunk in response.body {
      guard !Task.isCancelled else { throw .cancelled }
      guard chunk.count <= maximumBytes - bytes.count else {
        throw .decode(underlying: CatalogDecodingError.limitExceeded)
      }
      bytes.append(chunk)
    }
    guard !Task.isCancelled else { throw .cancelled }
    return Response(body: bytes, headers: response.headers, status: response.status)
  }

  func stream(_ request: HTTPRequest, body: TransportBody, options: TransportOptions)
    async throws(TransportError) -> StreamedResponse
  {
    try await base.stream(request, body: body, options: options)
  }
}
