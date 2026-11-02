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

## Status

The module is a prototype. It hasn't been compiled yet because it was written without Xcode, and it hasn't been run against a live PDS. The next steps are:

1. **Build and test**: open the Xcode project, add `Modules/ATShare` as a local package (File → Add Package Dependencies → Add Local), and run `swift test` in `Modules/ATShare`.
2. **Manual smoke test**: create an app password in Bluesky (Settings → Privacy and security → App passwords), call `ATClient.signIn`, then `share(...)`. Check the record at `https://<pds>/xrpc/com.atproto.repo.listRecords?repo=<did>&collection=io.github.letarrask.reader.share`.
3. **Integration (step 3 of the plan)**:
   - Store `ATSession` in the Keychain through the `Secrets` module.
   - Add a "Share" action next to Star in the article toolbar on Mac and iOS. Keep it separate from Star, so starring stays private by default.
   - Add a "Friends" smart feed modeled on `Shared/SmartFeeds/StarredFeedDelegate.swift`, backed by a local cache of `FriendsTimeline` results that's updated on each refresh.
   - Add a Bluesky sign-in screen in Settings → Accounts.

## Open questions

- Should Star publish automatically (like Reader's "shared" items), or should Share be its own action? The prototype assumes a separate action.
- Cost of polling: one `listRecords` per followed account per refresh. That's fine for a few hundred follows. Later we could cache which follows have never shared anything, or subscribe to the Jetstream firehose filtered by our collection.
