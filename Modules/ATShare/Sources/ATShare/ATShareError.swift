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
