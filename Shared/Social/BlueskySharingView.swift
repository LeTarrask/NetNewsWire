//
//  BlueskySharingView.swift
//  NetNewsWire
//

import SwiftUI
import Account

/// Sign in to Bluesky so you can share articles and see what people you follow have shared.
struct BlueskySharingView: View {

	@State private var handle = ""
	@State private var appPassword = ""
	@State private var signedInHandle = SocialSharing.shared.handle
	@State private var isWorking = false
	@State private var errorMessage: String?

	var body: some View {
		Form {
			if let signedInHandle {
				signedInSection(signedInHandle)
			} else {
				signInSection
			}
			if let errorMessage {
				Section {
					Text(errorMessage)
						.foregroundStyle(.red)
				}
			}
		}
		.formStyle(.grouped)
		.navigationTitle(Text("Bluesky Sharing", comment: "Title of the Bluesky sharing settings"))
	}

	private func signedInSection(_ signedInHandle: String) -> some View {
		Section {
			LabeledContent(String(localized: "Signed in as", comment: "Label before the Bluesky handle"), value: "@\(signedInHandle)")
			Button {
				refreshFriends()
			} label: {
				Text("Refresh Friends Now", comment: "Button that fetches new shares from people you follow")
			}
			.disabled(isWorking)
			Button(role: .destructive) {
				SocialSharing.shared.signOut()
				self.signedInHandle = nil
			} label: {
				Text("Sign Out", comment: "Button that signs out of Bluesky")
			}
		} footer: {
			Text("Articles you share appear for people who follow you on Bluesky. Articles shared by people you follow appear in the Friends feed.", comment: "Explanation of Bluesky sharing")
		}
	}

	private var signInSection: some View {
		Section {
			handleField
			SecureField(String(localized: "App Password", comment: "Bluesky app password field"), text: $appPassword)
			Button {
				signIn()
			} label: {
				if isWorking {
					ProgressView()
				} else {
					Text("Sign In", comment: "Button that signs in to Bluesky")
				}
			}
			.disabled(isWorking || handle.isEmpty || appPassword.isEmpty)
		} footer: {
			Text("Use an app password, not your main password. Create one in Bluesky under Settings → Privacy and security → App passwords.", comment: "Explains how to get a Bluesky app password")
		}
	}

	@ViewBuilder private var handleField: some View {
		let field = TextField(String(localized: "Handle", comment: "Bluesky handle field"), text: $handle, prompt: Text(verbatim: "you.bsky.social"))
			.autocorrectionDisabled()
		#if os(iOS)
		field
			.textInputAutocapitalization(.never)
			.keyboardType(.emailAddress)
		#else
		field
		#endif
	}

	private func signIn() {
		isWorking = true
		errorMessage = nil
		Task {
			defer {
				isWorking = false
			}
			do {
				try await SocialSharing.shared.signIn(handle: handle, appPassword: appPassword)
				appPassword = ""
				signedInHandle = SocialSharing.shared.handle
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	private func refreshFriends() {
		isWorking = true
		Task {
			await SocialSharing.shared.refreshFriends()
			isWorking = false
		}
	}
}
