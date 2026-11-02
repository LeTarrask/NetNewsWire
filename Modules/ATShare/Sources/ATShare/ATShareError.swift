//
//  ATShareError.swift
//  ATShare
//

import Foundation

public enum ATShareError: Error, Sendable, Equatable {
	case unsupportedDID(String)
	case noPDS(did: String)
	case notSignedIn
	/// XRPC error, e.g. "ExpiredToken" or "InvalidRequest".
	case xrpc(status: Int, error: String?, message: String?)
	case badResponse
	case invalidURL

	struct XRPCErrorBody: Decodable {
		let error: String?
		let message: String?
	}

	static func check(_ response: URLResponse, data: Data) throws {
		guard let http = response as? HTTPURLResponse else {
			throw ATShareError.badResponse
		}
		guard (200..<300).contains(http.statusCode) else {
			let body = try? JSONDecoder().decode(XRPCErrorBody.self, from: data)
			throw ATShareError.xrpc(status: http.statusCode, error: body?.error, message: body?.message)
		}
	}

	public var isExpiredToken: Bool {
		if case .xrpc(_, let error, _) = self {
			return error == "ExpiredToken"
		}
		return false
	}
}

extension ATShareError: LocalizedError {

	public var errorDescription: String? {
		switch self {
		case .unsupportedDID(let did):
			return String(localized: "This account uses an identity type that isn’t supported yet: \(did)")
		case .noPDS(let did):
			return String(localized: "Couldn’t find the server for \(did).")
		case .notSignedIn:
			return String(localized: "Sign in to Bluesky to share articles.")
		case .xrpc(let status, let error, let message):
			if status == 401 || error == "AuthenticationRequired" {
				return String(localized: "Bluesky didn’t accept that handle and app password.")
			}
			if status == 429 || error == "RateLimitExceeded" {
				return String(localized: "Bluesky is rate-limiting requests. Try again in a few minutes.")
			}
			return message ?? error ?? String(localized: "Bluesky returned an error (\(status)).")
		case .badResponse, .invalidURL:
			return String(localized: "Bluesky sent a response that couldn’t be read.")
		}
	}
}
