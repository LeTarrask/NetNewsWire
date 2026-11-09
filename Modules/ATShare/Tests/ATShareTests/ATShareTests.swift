//
//  ATShareTests.swift
//  ATShareTests
//

import Foundation
import Testing
@testable import ATShare

struct ShareRecordTests {

	@Test func encodesTypeField() throws {
		let record = ShareRecord(url: "https://example.com/post", title: "A post", createdAt: Date(timeIntervalSince1970: 0))
		let json = try #require(String(data: JSONEncoder().encode(record), encoding: .utf8))
		#expect(json.contains("\"$type\":\"io.github.letarrask.reader.share\""))
		#expect(json.contains("\"createdAt\":\"1970-01-01T00:00:00.000Z\""))
	}

	@Test func parsesDatesWithAndWithoutFractionalSeconds() throws {
		for createdAt in ["2026-11-02T12:00:00.123Z", "2026-11-02T12:00:00Z"] {
			let json = #"{"$type":"io.github.letarrask.reader.share","url":"https://example.com","createdAt":"\#(createdAt)"}"#
			let record = try JSONDecoder().decode(ShareRecord.self, from: Data(json.utf8))
			#expect(record.createdDate != nil)
		}
	}
}

struct ListRecordsTests {

	@Test func skipsRecordsThatDoNotMatchTheSchema() throws {
		let json = """
		{
			"cursor": "abc",
			"records": [
				{ "uri": "at://did:plc:a/io.github.letarrask.reader.share/1", "cid": "x",
				  "value": { "$type": "io.github.letarrask.reader.share", "url": "https://example.com/1", "createdAt": "2026-11-02T12:00:00Z" } },
				{ "uri": "at://did:plc:a/io.github.letarrask.reader.share/2", "cid": "y",
				  "value": { "$type": "io.github.letarrask.reader.share", "title": "missing url" } }
			]
		}
		"""
		let response = try JSONDecoder().decode(ListRecordsResponse.self, from: Data(json.utf8))
		#expect(response.cursor == "abc")
		#expect(response.records.count == 2)
		#expect(response.records.compactMap(\.value).count == 1)
	}

	@Test func recordKeyIsLastPathComponent() {
		let item = SharedItem(uri: "at://did:plc:a/io.github.letarrask.reader.share/3kabc", authorDID: "did:plc:a", authorHandle: nil,
		                      record: ShareRecord(url: "https://example.com"))
		#expect(item.recordKey == "3kabc")
	}
}

struct DIDResolverTests {

	@Test func findsPDSInDIDDocument() throws {
		let json = """
		{
			"id": "did:plc:abc",
			"service": [
				{ "id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "https://morel.us-east.host.bsky.network" }
			]
		}
		"""
		let document = try JSONDecoder().decode(DIDDocument.self, from: Data(json.utf8))
		#expect(document.pdsURL == URL(string: "https://morel.us-east.host.bsky.network"))
	}

	@Test func buildsDocumentURLs() throws {
		let resolver = DIDResolver()
		#expect(try resolver.didDocumentURL(for: "did:plc:abc").absoluteString == "https://plc.directory/did:plc:abc")
		#expect(try resolver.didDocumentURL(for: "did:web:example.com").absoluteString == "https://example.com/.well-known/did.json")
		#expect(throws: ATShareError.self) { try resolver.didDocumentURL(for: "did:key:z6Mk") }
	}
}

struct FriendsTimelineTests {

	@Test func sortsNewestFirst() {
		let old = SharedItem(uri: "at://a/c/1", authorDID: "a", authorHandle: nil, record: ShareRecord(url: "https://e.com/1", createdAt: Date(timeIntervalSince1970: 100)))
		let new = SharedItem(uri: "at://b/c/2", authorDID: "b", authorHandle: nil, record: ShareRecord(url: "https://e.com/2", createdAt: Date(timeIntervalSince1970: 200)))
		#expect(FriendsTimeline.sortedNewestFirst([old, new]).map(\.uri) == ["at://b/c/2", "at://a/c/1"])
	}
}
