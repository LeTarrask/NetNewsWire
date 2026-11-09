//
//  FriendsTimeline.swift
//  ATShare
//

import Foundation

/// Builds the "Friends" timeline: recent shares from everyone you follow, newest first.
/// The app runs this on each refresh and stores the results locally like any other feed.
public struct FriendsTimeline: Sendable {

	let client: ATClient
	/// How many friends to read at the same time.
	let concurrency: Int

	public init(client: ATClient, concurrency: Int = 8) {
		self.client = client
		self.concurrency = concurrency
	}

	/// Fetches recent shares from each followed account.
	/// A friend whose PDS fails or who has never shared anything is skipped, so one bad server doesn't break the timeline.
	public func fetch(for actor: String, perFriendLimit: Int = 25) async throws -> [SharedItem] {
		let friends = try await client.follows(of: actor)
		var all = [SharedItem]()

		for start in stride(from: 0, to: friends.count, by: concurrency) {
			let batch = friends[start..<min(start + concurrency, friends.count)]
			let results = await withTaskGroup(of: [SharedItem].self) { group in
				for friend in batch {
					group.addTask {
						(try? await client.shares(of: friend.did, handle: friend.handle, limit: perFriendLimit).items) ?? []
					}
				}
				var collected = [SharedItem]()
				for await items in group {
					collected.append(contentsOf: items)
				}
				return collected
			}
			all.append(contentsOf: results)
		}

		return FriendsTimeline.sortedNewestFirst(all)
	}

	static func sortedNewestFirst(_ items: [SharedItem]) -> [SharedItem] {
		items.sorted { ($0.record.createdDate ?? .distantPast) > ($1.record.createdDate ?? .distantPast) }
	}
}
