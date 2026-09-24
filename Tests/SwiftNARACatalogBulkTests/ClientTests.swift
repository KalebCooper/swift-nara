import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ClientTests {
  @Test("Everyday requests and endpoints return equivalent captured pages")
  func everydayRequestsAndEndpointsReturnEquivalentCapturedPages() async throws {
    let data = try Fixture.manifestFirst.data()
    let transport = MockTransport(
      results: Array(repeating: .success(Response(body: data, status: .ok)), count: 4))
    let client = try makeClient(transport)
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    let stored = CatalogBulkRequest.manifest(query)
    let everyday = try await client.manifest(matching: query)
    let reusable = try await client.value(for: stored)
    let endpoint = try await client.send(.manifest(query))
    let receipt = try await client.response(for: .manifest(query))
    #expect(everyday == reusable && reusable == endpoint && endpoint == receipt.value)
    #expect(receipt.body == data)
    #expect(receipt.retrieval.status == 200)
    #expect(receipt.retrieval.retrievedAt == Date(timeIntervalSince1970: 1234))
    #expect(transport.requests.count == 4)
    #expect(
      transport.requests.allSatisfy {
        $0.request.path == "/?list-type=2&max-keys=4&prefix=descriptions%2Frecord-groups%2Frg_11%2F"
      })
    #expect(
      transport.requests.allSatisfy {
        $0.request.headerFields[.userAgent] == "(swift-nara tests, example.test)"
      })
    #expect(transport.requests.allSatisfy { $0.request.headerFields[.authorization] == nil })
  }

  @Test("Custom constrained factories and endpoint responses remain usable")
  func customConstrainedFactoriesAndEndpointResponsesRemainUsable() async throws {
    let data = try Fixture.manifestFirst.data()
    let transport = MockTransport(results: [
      .success(Response(body: data, status: .ok)),
      .success(Response(body: Data("custom".utf8), status: .ok)),
    ])
    let client = try makeClient(transport)
    let request = try CatalogBulkRequest.recordGroupEleven()
    #expect(try await client.value(for: request).objects.count == 4)
    let endpoint = try #require(Endpoint<CustomText>(path: "/descriptions/custom.jsonl"))
    let custom = CatalogBulkRequest(endpoint: endpoint)
    #expect(try await client.value(for: custom).text == "custom")
  }

  @Test("Manifest response bytes are bounded before decoding")
  func manifestResponseBytesAreBoundedBeforeDecoding() async throws {
    let data = try Fixture.manifestFirst.data()
    let transport = MockTransport(answers: [
      .success(.init(chunks: [Data(data.prefix(50)), Data(data.dropFirst(50))]))
    ])
    let client = try makeClient(transport, maximumManifestBytes: 60)
    do {
      _ = try await client.manifest(matching: ManifestQuery())
      Issue.record("Expected a byte limit failure")
    } catch CatalogBulkError.decoding(.limitExceeded) {}
    #expect(transport.requests.count == 1)
  }

  @Test("Redirects and rate limits retain their HTTP failures without replay")
  func redirectsAndRateLimitsRetainTheirHTTPFailuresWithoutReplay() async throws {
    for response in [
      Response(headers: [.location: "https://evil.test/"], status: .found),
      Response(
        body: Data("slow down".utf8), headers: [.retryAfter: "60"], status: .tooManyRequests),
    ] {
      let transport = MockTransport(results: [.success(response)])
      let client = try makeClient(transport)
      do {
        _ = try await client.manifest(matching: ManifestQuery());
        Issue.record("Expected HTTP failure")
      } catch CatalogBulkError.transport(.httpStatus(let body, let code, let headers)) {
        #expect(code == response.status.code)
        #expect(headers == response.headers)
        #expect(body == response.body)
      }
      #expect(transport.requests.count == 1)
    }
  }
}

func makeClient(
  _ transport: MockTransport, maximumManifestBytes: Int = 4 * 1024 * 1024,
  maximumShardBytes: Int64 = 1024 * 1024 * 1024
) throws -> CatalogBulkClient {
  CatalogBulkClient(
    configuration: try CatalogBulkConfiguration(
      maximumManifestBytes: maximumManifestBytes, maximumShardBytes: maximumShardBytes,
      userAgent: "(swift-nara tests, example.test)"),
    retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
}

private struct CustomText: CatalogBulkResponse {
  let text: String
  static func decode(_ data: Data) throws(CatalogDecodingError) -> Self {
    Self(text: String(decoding: data, as: UTF8.self))
  }
}

extension CatalogBulkRequest where Response == BulkManifest {
  fileprivate static func recordGroupEleven() throws -> Self {
    .manifest(try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/"))
  }
}
