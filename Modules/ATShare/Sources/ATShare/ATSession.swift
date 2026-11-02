//
//  ATSession.swift
//  ATShare
//

import Foundation

/// A signed-in AT Protocol session. The app should store this in the Keychain (see the Secrets module).
public struct ATSession: Codable, Sendable, Equatable {
	public let did: String
	public let handle: String
	public let accessJwt: String
	public let refreshJwt: String
	/// The PDS that hosts this account's repo. Writes go here.
	public let pdsURL: URL
}

/// Response body for com.atproto.server.createSession and refreshSession.
struct SessionResponse: Decodable {
	let did: String
	let handle: String
	let accessJwt: String
	let refreshJwt: String
	let didDoc: DIDDocument?
}
