//
//  SpacetimeDBClient+identity.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

extension SpacetimeDBClient {
    /// Retrieves an new identity & access token from the server
    public func identity() async throws -> (Identity, AuthenticationToken) {
        let httpHost = if host.hasPrefix("ws:") {
            "http:" + host.suffix(host.count - 3)
        } else if host.hasPrefix("wss:") {
            "https:" + host.suffix(host.count - 4)
        } else {
            throw Errors.invalidServerAddress
        }
        guard let v1Url = URL(string: "\(httpHost)/v1/identity") else {
            throw Errors.invalidServerAddress
        }
        var request = URLRequest(url: v1Url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let identityResponse = try? JSONDecoder().decode(IdentityResponse.self, from: data)
        else {
            throw Errors.badServerResponse
        }
        return (identityResponse.identity, identityResponse.token)
    }

}
