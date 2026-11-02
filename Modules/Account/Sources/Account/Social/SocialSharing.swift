//
//  SocialSharing.swift
//  Account
//

import Foundation
import os
import RSCore
import ATShare
import RSParser
import Secrets

public extension Notification.Name {
	/// Posted when the Bluesky sign-in state changes.
	static let SocialSharingDidChange = Notification.Name("SocialSharingDidChange")
}

/// Google Reader–style sharing over AT Protocol.
///
/// Shares are written to the user’s own Bluesky repo. Shares from people they follow
/// show up in a “Friends” feed in the On My Mac account, so the timeline, unread counts,
/// and starring all work the way they do for any other feed.
@MainActor public final class SocialSharing: NSObject {

	public static let shared = SocialSharing()

	/// URL of the Friends feed. The local refresher skips this scheme; this class fills the feed instead.
	public static let friendsFeedURL = "atshare://friends"
	static let friendsFeedScheme = "atshare"

	public private(set) var handle: String?

	public var isSignedIn: Bool {
		handle != nil
	}

	public private(set) var isRefreshingFriends = false

	private var client: ATClient

	private static let keychainServer = "atproto"
	private static let didDefaultsKey = "ATShareSignedInDID"
	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "SocialSharing")

	override private init() {
		let session = Self.loadSession()
		self.client = Self.makeClient(session: session)
		self.handle = session?.handle
		super.init()

		NotificationCenter.default.addObserver(self, selector: #selector(accountRefreshDidFinish(_:)), name: .AccountRefreshDidFinish, object: nil)
	}

	@objc func accountRefreshDidFinish(_ notification: Notification) {
		guard isSignedIn, let account = notification.object as? Account, account === friendsAccount else {
			return
		}
		Task {
			await refreshFriends()
		}
	}

	// MARK: - Sign in

	/// Signs in with a Bluesky handle and an app password (Bluesky Settings → Privacy and security → App passwords).
	public func signIn(handle: String, appPassword: String) async throws {
		let identifier = handle.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("@")
		let session = try await client.signIn(identifier: String(identifier), appPassword: appPassword)
		self.handle = session.handle
		ensureFriendsFeed()
		postDidChange()
		await refreshFriends()
	}

	public func signOut() {
		if let did = UserDefaults.standard.string(forKey: Self.didDefaultsKey) {
			try? CredentialsManager.removeCredentials(type: .atprotoSession, server: Self.keychainServer, username: did)
		}
		UserDefaults.standard.removeObject(forKey: Self.didDefaultsKey)
		client = Self.makeClient(session: nil)
		handle = nil
		removeFriendsFeed()
		postDidChange()
	}

	// MARK: - Sharing

	/// Shares an article with the people who follow you.
	public func share(articleURL: String, title: String?, feedURL: String?, feedTitle: String?, comment: String? = nil) async throws {
		// Don’t re-share the Friends feed’s own synthetic feed URL.
		let sourceFeedURL = feedURL == Self.friendsFeedURL ? nil : feedURL
		let record = ShareRecord(url: articleURL, title: title, feedURL: sourceFeedURL, feedTitle: sourceFeedURL == nil ? nil : feedTitle, comment: comment)
		try await client.share(record)
	}

	// MARK: - Friends feed

	/// The account that holds the Friends feed. Only the On My Mac account is supported for now.
	var friendsAccount: Account? {
		let account = AccountManager.shared.defaultAccount
		return account.isActive ? account : nil
	}

	public var friendsFeed: Feed? {
		friendsAccount?.existingFeed(withFeedID: Self.friendsFeedURL)
	}

	/// Fetches recent shares from everyone you follow and stores them in the Friends feed.
	public func refreshFriends() async {
		guard let handle, !isRefreshingFriends else {
			return
		}
		guard let account = friendsAccount, let feed = ensureFriendsFeed() else {
			return
		}

		isRefreshingFriends = true
		defer {
			isRefreshingFriends = false
		}

		do {
			let items = try await FriendsTimeline(client: client).fetch(for: handle)
			let parsedItems = Set(items.map { Self.parsedItem(for: $0) })
			feed.lastCheckDate = Date()
			guard !parsedItems.isEmpty else {
				return
			}
			_ = await account.updateAsync(feedID: feed.feedID, parsedItems: parsedItems)
		} catch {
			Self.logger.error("SocialSharing: Friends refresh failed: \(error.localizedDescription)")
		}
	}

	static func isFriendsFeedURL(_ urlString: String) -> Bool {
		urlString.hasPrefix(friendsFeedScheme + ":")
	}
}

// MARK: - Private

private extension SocialSharing {

	@discardableResult
	func ensureFriendsFeed() -> Feed? {
		guard let account = friendsAccount else {
			return nil
		}
		if let feed = account.existingFeed(withFeedID: Self.friendsFeedURL) {
			return feed
		}
		let feed = account.createFeed(with: nil, url: Self.friendsFeedURL, feedID: Self.friendsFeedURL, homePageURL: nil)
		feed.editedName = NSLocalizedString("Friends", comment: "Name of the feed that shows articles shared by people you follow on Bluesky")
		account.addFeedToTreeAtTopLevel(feed)
		return feed
	}

	func removeFriendsFeed() {
		guard let account = friendsAccount, let feed = account.existingFeed(withFeedID: Self.friendsFeedURL) else {
			return
		}
		account.removeFeedFromTreeAtTopLevel(feed)
	}

	func postDidChange() {
		NotificationCenter.default.post(name: .SocialSharingDidChange, object: self)
	}

	// MARK: Session storage

	static func makeClient(session: ATSession?) -> ATClient {
		ATClient(session: session) { newSession in
			Task { @MainActor in
				saveSession(newSession)
			}
		}
	}

	static func loadSession() -> ATSession? {
		guard let did = UserDefaults.standard.string(forKey: didDefaultsKey) else {
			return nil
		}
		guard let credentials = try? CredentialsManager.retrieveCredentials(type: .atprotoSession, server: keychainServer, username: did) else {
			return nil
		}
		return try? JSONDecoder().decode(ATSession.self, from: Data(credentials.secret.utf8))
	}

	static func saveSession(_ session: ATSession?) {
		guard let session else {
			return
		}
		do {
			let json = try JSONEncoder().encode(session)
			let secret = String(decoding: json, as: UTF8.self)
			let credentials = Credentials(type: .atprotoSession, username: session.did, secret: secret)
			try CredentialsManager.storeCredentials(credentials, server: keychainServer)
			UserDefaults.standard.set(session.did, forKey: didDefaultsKey)
		} catch {
			logger.error("SocialSharing: could not save session: \(error.localizedDescription)")
		}
	}

	// MARK: Converting shares to articles

	static func parsedItem(for item: SharedItem) -> ParsedItem {
		let record = item.record
		let who = item.authorHandle.map { "@\($0)" } ?? item.authorDID
		let profileURL = "https://bsky.app/profile/\(item.authorHandle ?? item.authorDID)"
		let author = ParsedAuthor(name: who, url: profileURL, avatarURL: nil, emailAddress: nil)

		return ParsedItem(syncServiceID: nil,
		                  uniqueID: item.uri,
		                  feedURL: friendsFeedURL,
		                  url: record.url,
		                  externalURL: nil,
		                  title: record.title ?? record.url,
		                  language: nil,
		                  contentHTML: contentHTML(for: item, who: who, profileURL: profileURL),
		                  contentText: nil,
		                  markdown: nil,
		                  summary: record.comment,
		                  imageURL: nil,
		                  thumbnailURL: nil,
		                  bannerImageURL: nil,
		                  datePublished: record.createdDate,
		                  dateModified: nil,
		                  authors: [author],
		                  tags: nil,
		                  attachments: nil)
	}

	static func contentHTML(for item: SharedItem, who: String, profileURL: String) -> String {
		let record = item.record
		var html = "<p><a href=\"\(escaped(profileURL))\">\(escaped(who))</a> shared this"
		if let feedTitle = record.feedTitle, let feedURL = record.feedURL {
			html += " from <a href=\"\(escaped(feedURL))\">\(escaped(feedTitle))</a>"
		}
		html += ".</p>"
		if let comment = record.comment, !comment.isEmpty {
			html += "<blockquote>\(escaped(comment))</blockquote>"
		}
		html += "<p><a href=\"\(escaped(record.url))\">\(escaped(record.title ?? record.url))</a></p>"
		return html
	}

	static func escaped(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
}
