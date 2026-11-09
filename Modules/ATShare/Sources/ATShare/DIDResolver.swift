//
//  DIDResolver.swift
//  ATShare
//

import Foundation

/// The parts of a DID document we need: which PDS hosts the account.
struct DIDDocument: Decodable, Sendable {

	struct Service: Decodable, Sendable {
		let id: String
		let type: String
		let serviceEndpoint: String
	}

	let id: String
	let service: [Service]?

	var pdsURL: URL? {
		guard let pds = service?.first(where: { $0.id.hasSuffix("#atproto_pds") }) else {
			return nil
		}
		return URL(string: pds.serviceEndpoint)
	}
}

/// Finds the PDS for a DID, so we can read a friend's shares straight from their own server.
public struct DIDResolver: Sendable {

	let session: URLSession
	let plcDirectory: URL

	public init(session: URLSession = .shared, plcDirectory: URL = ATEndpoint.plcDirectory) {
		self.session = session
		self.plcDirectory = plcDirectory
	}

	public func pdsURL(for did: String) async throws -> URL {
		let document = try await didDocument(for: did)
		guard let url = document.pdsURL else {
			throw ATShareError.noPDS(did: did)
		}
		return url
	}

	func didDocumentURL(for did: String) throws -> URL {
		if did.hasPrefix("did:plc:") {
			return plcDirectory.appendingPathComponent(did)
		}
		if did.hasPrefix("did:web:") {
			let host = String(did.dropFirst("did:web:".count))
			guard !host.contains(":"), let url = URL(string: "https://\(host)/.well-known/did.json") else {
				throw ATShareError.unsupportedDID(did)
			}
			return url
		}
		throw ATShareError.unsupportedDID(did)
	}

	func didDocument(for did: String) async throws -> DIDDocument {
		let url = try didDocumentURL(for: did)
		let (data, response) = try await session.data(from: url)
		try ATShareError.check(response, data: data)
		return try JSONDecoder().decode(DIDDocument.self, from: data)
	}
}
