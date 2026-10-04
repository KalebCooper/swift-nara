import Foundation
import HTTPCore
import HTTPTypes

// Bound non-success evidence before HTTPClient's own status handling can buffer it.
struct ErrorBodyTransport: Transport {
  let base: any Transport
  let maximumBytes: Int

  func send(_ request: HTTPRequest, body: TransportBody, options: TransportOptions)
    async throws(TransportError) -> Response
  {
    // The client only uses streaming; refuse accidental unbounded buffering.
    throw .transport(kind: .other, underlying: DigitalObjectsError.invalidConfiguration)
  }

  func stream(_ request: HTTPRequest, body: TransportBody, options: TransportOptions)
    async throws(TransportError) -> StreamedResponse
  {
    let response = try await base.stream(request, body: body, options: options)
    guard response.status.kind != .successful else { return response }
    var bytes = Data()
    do {
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw TransportError.cancelled }
        bytes.append(chunk.prefix(maximumBytes - bytes.count))
        if bytes.count == maximumBytes { break }
      }
    } catch {
      if Task.isCancelled { throw .cancelled }
      // A status failure remains a status failure if its diagnostic body is interrupted.
    }
    guard !Task.isCancelled else { throw .cancelled }
    throw .httpStatus(body: bytes, code: response.status.code, headers: response.headers)
  }
}
