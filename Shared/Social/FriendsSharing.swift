//
//  FriendsSharing.swift
//  NetNewsWire
//

import Foundation
import Articles
import Account

/// App-level glue between articles and Bluesky sharing.
@MainActor enum FriendsSharing {

	static func canShare(_ article: Article) -> Bool {
		SocialSharing.shared.isSignedIn && article.preferredLink != nil
	}

	static func share(_ article: Article) async throws {
		guard let link = article.preferredLink else {
			return
		}
		let feed = article.feed
		try await SocialSharing.shared.share(articleURL: link, title: article.title, feedURL: feed?.url, feedTitle: feed?.nameForDisplay)
	}

	static let shareCommandTitle = NSLocalizedString("Share with Friends", comment: "Command that shares an article with people who follow you on Bluesky")
}
