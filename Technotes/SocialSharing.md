# Social sharing over AT Protocol

This fork adds Google Reader–style sharing: you share an article, and the people who follow you see it in a "Friends" timeline. There's no central server. Each person's shares are records in their own AT Protocol repo (on their PDS, such as a Bluesky account), and readers fetch them directly from there.

## Why AT Protocol

- Friends can sign in with a Bluesky account they already have, so there's nothing to host or set up.
- The follow graph is reused from Bluesky (`app.bsky.graph.getFollows`), so people you already follow there show up automatically.
- Shares belong to the user and are portable. Any other app can read them.
- Reading, starring, and the local database all stay on the device as before. Only shares go out, and only when you share something.

## The record

Collection `io.github.letarrask.reader.share` (schema: `Modules/ATShare/lexicons/`). The NSID is the reversed `letarrask.github.io`, a domain we control. Fields: `url`, `title`, `feedURL`, `feedTitle`, `comment`, `createdAt`.

## Module: `Modules/ATShare`

A Foundation-only package with no dependencies.

- `ATClient` (actor) handles sign-in with an app password, refreshing the token, `share`, `unshare`, `shares(of:)`, and `follows(of:)`.
- `DIDResolver` looks up a DID (did:plc or did:web) to find its PDS, so reads go straight to each friend's server.
- `FriendsTimeline` fetches the follows, reads each one's recent shares (8 at a time), and returns them newest first. Friends with no shares or a failing server are skipped.

## How it’s wired into the app

- **`SocialSharing`** (`Modules/Account/Sources/Account/Social/`) is the app-facing API. It handles Bluesky sign-in and sign-out, saves the session in the Keychain (`CredentialsType.atprotoSession`), shares articles, and keeps the Friends feed filled. The app imports only `Account`, so the Xcode project needed no changes: `Account` depends on `ATShare` in its `Package.swift`.
- **Friends feed**: when you sign in, a feed named “Friends” with the URL `atshare://friends` is added to the On My Mac account. `LocalAccountRefresher` skips that URL. After each refresh of the local account (and right after sign-in), `SocialSharing.refreshFriends()` fetches your follows’ shares and saves them as articles in that feed. Because it’s an ordinary feed, the timeline, unread counts, starring, and search all work unchanged. Each article says who shared it and which feed it came from, and links to the original.
- **Share with Friends**: available in the timeline context menu on both Mac and iOS when you’re signed in. Errors (wrong password, rate limits) appear as a normal alert.
- **Sign-in UI**: a shared SwiftUI view, `Shared/Social/BlueskySharingView.swift`. On the Mac it’s under NetNewsWire menu → Bluesky Sharing…, and on iOS under Settings → Accounts → Bluesky Sharing.

## Trying it in Xcode

1. Build and run as usual. The new files are picked up automatically by the synchronized `Shared`, `Mac`, and `iOS` groups.
2. In Bluesky, create an app password (Settings → Privacy and security → App passwords).
3. Open Bluesky Sharing, sign in with your handle and the app password. A Friends feed appears in the sidebar under On My Mac.
4. Right-click (or long-press on iOS) any article and choose Share with Friends. Check the record at `https://<your pds>/xrpc/com.atproto.repo.listRecords?repo=<your did>&collection=io.github.letarrask.reader.share`.
5. Have a friend do the same. Their shares appear in your Friends feed after the next refresh, or right away if you press Refresh Friends Now.

## Known limitations

- The Friends feed only lives in the On My Mac account. If that account is turned off, there’s nowhere to put it.
- You can’t un-share from the UI yet. `ATClient.unshare(recordKey:)` exists, but nothing calls it.
- There’s no comment field yet, even though the record supports one.
- Each refresh makes one request per account you follow. That’s fine for a few hundred follows.

## Open questions

- Should Star publish automatically (like Reader's "shared" items), or should Share be its own action? The prototype assumes a separate action.
- Cost of polling: one `listRecords` per followed account per refresh. That's fine for a few hundred follows. Later we could cache which follows have never shared anything, or subscribe to the Jetstream firehose filtered by our collection.
