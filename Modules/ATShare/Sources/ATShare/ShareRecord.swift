//
//  ShareRecord.swift
//  ATShare
//

import Foundation

/// An article someone shared, stored as an AT Protocol record in their own repo (PDS).
/// Schema: lexicons/io.github.letarrask.reader.share.json
public struct ShareRecord: Codable, Sendable, Hashable {

	/// The record collection (NSID). It must sit under a domain we control: letarrask.github.io.
	public static let collection = "io.github.letarrask.reader.share"

	public let type: String
	public let url: String
	public let title: String?
	public let feedURL: String?
	public let feedTitle: String?
	public let comment: String?
	public let createdAt: String

	enum CodingKeys: String, CodingKey {
		case type = "$type"
		case url, title, feedURL, feedTitle, comment, createdAt
	}

	public init(url: String, title: String? = nil, feedURL: String? = nil, feedTitle: String? = nil, comment: String? = nil, createdAt: Date = Date()) {
		self.type = Self.collection
		self.url = url
		self.title = title
		self.feedURL = feedURL
		self.feedTitle = feedTitle
		self.comment = comment
		self.createdAt = ShareRecord.dateFormatter.string(from: createdAt)
	}

	public var createdDate: Date? {
		ShareRecord.dateFormatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
	}

	nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()
}

/// A share as read back from someone's repo, with who shared it.
public struct SharedItem: Sendable, Hashable {
	public let uri: String // at://did/collection/rkey
	public let authorDID: String
	public let authorHandle: String?
	public let record: ShareRecord

	public var recordKey: String? {
		uri.split(separator: "/").last.map(String.init)
	}
}
