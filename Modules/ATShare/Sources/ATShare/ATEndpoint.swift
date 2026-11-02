//
//  ATEndpoint.swift
//  ATShare
//

import Foundation

/// Well-known AT Protocol hosts.
public enum ATEndpoint {

	/// Entryway for Bluesky-hosted accounts. Sign-in works here for any of them.
	public static let bskySocial = makeURL("https://bsky.social")
	/// Public Bluesky AppView, for reading the follow graph without auth.
	public static let publicAppView = makeURL("https://public.api.bsky.app")
	/// Directory that resolves did:plc identifiers to DID documents.
	public static let plcDirectory = makeURL("https://plc.directory")

	private static func makeURL(_ string: String) -> URL {
		guard let url = URL(string: string) else {
			preconditionFailure("Invalid built-in URL: \(string)")
		}
		return url
	}
}
