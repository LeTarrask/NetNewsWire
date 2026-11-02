//
//  ATClient.swift
//  ATShare
//

import Foundation

/// A small AT Protocol client that does only what sharing needs:
/// sign in, write and delete share records, list someone's shares, and list who someone follows.
public actor ATClient {

	public private(set) var session: ATSession?

	/// Called whenever the session is created or refreshed, so the app can save it to the Keychain.
	private let onSessionChange: @Sendable (ATSession?) -> Void
	private let urlSession: URLSession
	private let resolver: DIDResolver
	/// The public Bluesky AppView, used to read the social graph (who follows whom). No auth needed.
	private let appView: URL

	public init(session: ATSession? = nil,
	            urlSession: URLSession = .shared,
	            appView: URL = ATEndpoint.publicAppView,
	            onSessionChange: @escaping @Sendable (ATSession?) -> Void = { _ in }) {
		self.session = session
		self.urlSession = urlSession
		self.resolver = DIDResolver(session: urlSession)
		self.appView = appView
		self.onSessionChange = onSessionChange
	}

	// MARK: - Sign in

	/// Signs in with a handle (or email) and an app password, which the user creates in Bluesky settings.
	/// `service` is where the account lives; bsky.social works for every Bluesky-hosted account.
	@discardableResult
	public func signIn(identifier: String, appPassword: String, service: URL = ATEndpoint.bskySocial) async throws -> ATSession {
		let body = ["identifier": identifier, "password": appPassword]
		let data = try await post(service, "com.atproto.server.createSession", json: body, token: nil)
		let response = try JSONDecoder().decode(SessionResponse.self, from: data)
		let newSession = ATSession(did: response.did,
		                           handle: response.handle,
		                           accessJwt: response.accessJwt,
		                           refreshJwt: response.refreshJwt,
		                           pdsURL: response.didDoc?.pdsURL ?? service)
		setSession(newSession)
		return newSession
	}

	public func signOut() {
		setSession(nil)
	}

	// MARK: - Writing shares

	/// Publishes a share to the signed-in user's repo. Returns the record's at:// URI.
	@discardableResult
	public func share(_ record: ShareRecord) async throws -> String {
		struct CreateRecordResponse: Decodable { let uri: String }
		let data = try await authorizedPost("com.atproto.repo.createRecord") { session in
			CreateRecordRequest(repo: session.did, collection: ShareRecord.collection, record: record)
		}
		return try JSONDecoder().decode(CreateRecordResponse.self, from: data).uri
	}

	/// Removes a share, for example when the user un-stars an article.
	public func unshare(recordKey: String) async throws {
		_ = try await authorizedPost("com.atproto.repo.deleteRecord") { session in
			["repo": session.did, "collection": ShareRecord.collection, "rkey": recordKey]
		}
	}

	// MARK: - Reading shares

	/// Lists one person's shares, newest first, read directly from their PDS. No auth needed.
	public func shares(of did: String, handle: String? = nil, limit: Int = 25, cursor: String? = nil) async throws -> (items: [SharedItem], cursor: String?) {
		let pds = try await resolver.pdsURL(for: did)
		var query = [
			URLQueryItem(name: "repo", value: did),
			URLQueryItem(name: "collection", value: ShareRecord.collection),
			URLQueryItem(name: "limit", value: String(limit))
		]
		if let cursor {
			query.append(URLQueryItem(name: "cursor", value: cursor))
		}
		let data = try await get(pds, "com.atproto.repo.listRecords", query: query)
		let response = try JSONDecoder().decode(ListRecordsResponse.self, from: data)
		let items = response.records.compactMap { entry -> SharedItem? in
			guard let record = entry.value else {
				return nil // Skip records that don't match our schema instead of failing the whole list.
			}
			return SharedItem(uri: entry.uri, authorDID: did, authorHandle: handle, record: record)
		}
		return (items, response.cursor)
	}

	/// Everyone `actor` follows on Bluesky. This reuses the Bluesky graph, so friends don't have to re-follow anyone.
	public func follows(of actor: String, maxCount: Int = 1000) async throws -> [Profile] {
		var profiles = [Profile]()
		var cursor: String?
		repeat {
			var query = [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: "100")]
			if let cursor {
				query.append(URLQueryItem(name: "cursor", value: cursor))
			}
			let data = try await get(appView, "app.bsky.graph.getFollows", query: query)
			let page = try JSONDecoder().decode(FollowsResponse.self, from: data)
			profiles.append(contentsOf: page.follows)
			cursor = page.cursor
		} while cursor != nil && profiles.count < maxCount
		return Array(profiles.prefix(maxCount))
	}

	// MARK: - Private

	private func setSession(_ newSession: ATSession?) {
		session = newSession
		onSessionChange(newSession)
	}

	/// Posts with the access token, refreshing it once if it has expired.
	private func authorizedPost<Body: Encodable & Sendable>(_ method: String, body makeBody: (ATSession) -> Body) async throws -> Data {
		guard let current = session else {
			throw ATShareError.notSignedIn
		}
		do {
			return try await post(current.pdsURL, method, json: makeBody(current), token: current.accessJwt)
		} catch let error as ATShareError where error.isExpiredToken {
			let refreshed = try await refresh(current)
			return try await post(refreshed.pdsURL, method, json: makeBody(refreshed), token: refreshed.accessJwt)
		}
	}

	private func refresh(_ current: ATSession) async throws -> ATSession {
		let data = try await post(current.pdsURL, "com.atproto.server.refreshSession", json: nil as String?, token: current.refreshJwt)
		let response = try JSONDecoder().decode(SessionResponse.self, from: data)
		let refreshed = ATSession(did: response.did,
		                          handle: response.handle,
		                          accessJwt: response.accessJwt,
		                          refreshJwt: response.refreshJwt,
		                          pdsURL: response.didDoc?.pdsURL ?? current.pdsURL)
		setSession(refreshed)
		return refreshed
	}

	private func post<Body: Encodable>(_ host: URL, _ method: String, json body: Body?, token: String?) async throws -> Data {
		var request = URLRequest(url: xrpcURL(host, method))
		request.httpMethod = "POST"
		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONEncoder().encode(body)
		}
		if let token {
			request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
		let (data, response) = try await urlSession.data(for: request)
		try ATShareError.check(response, data: data)
		return data
	}

	private func get(_ host: URL, _ method: String, query: [URLQueryItem]) async throws -> Data {
		guard var components = URLComponents(url: xrpcURL(host, method), resolvingAgainstBaseURL: false) else {
			throw ATShareError.invalidURL
		}
		components.queryItems = query
		guard let url = components.url else {
			throw ATShareError.invalidURL
		}
		let (data, response) = try await urlSession.data(from: url)
		try ATShareError.check(response, data: data)
		return data
	}

	private func xrpcURL(_ host: URL, _ method: String) -> URL {
		host.appendingPathComponent("xrpc").appendingPathComponent(method)
	}
}

// MARK: - Wire types

public struct Profile: Decodable, Sendable, Hashable {
	public let did: String
	public let handle: String
	public let displayName: String?
}

struct CreateRecordRequest: Encodable, Sendable {
	let repo: String
	let collection: String
	let record: ShareRecord
}

struct ListRecordsResponse: Decodable {

	struct Entry: Decodable {
		let uri: String
		let value: ShareRecord?

		enum CodingKeys: String, CodingKey { case uri, value }

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			uri = try container.decode(String.self, forKey: .uri)
			value = try? container.decode(ShareRecord.self, forKey: .value)
		}
	}

	let cursor: String?
	let records: [Entry]
}

struct FollowsResponse: Decodable {
	let follows: [Profile]
	let cursor: String?
}
