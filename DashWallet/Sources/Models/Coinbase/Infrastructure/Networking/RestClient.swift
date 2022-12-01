//
//  RestClient.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation

private var acceptableStatusCodes: Range<Int> { 200..<300 }
private var ACCESS_TOKEN: String?

// MARK: - RestClient

/// Provides access to the REST Backend
protocol RestClient {
    /// Retrieves a JSON resource and decodes it
    func get<T: Decodable, E: Endpoint>(_ endpoint: E) -> AnyPublisher<T, Error>

    /// Creates some resource by sending a JSON body and returning empty response
    func post<T: Decodable, S: Encodable, E: Endpoint>(_ endpoint: E, using body: S?, using verificationCode:String?)
        -> AnyPublisher<T, Error>

    /// Creates some resource by sending a JSON body and returning empty response
    func post<T: Decodable, E: Endpoint>(_ endpoint: E, using queryItems: [URLQueryItem]?)
        -> AnyPublisher<T, Error>
}



// MARK: - RestClientImpl

class RestClientImpl: RestClient {


    private let session: URLSession

    init(sessionConfig: URLSessionConfiguration? = nil) {
        session = URLSession(configuration: sessionConfig ?? URLSessionConfiguration.default)
    }

    func get<T>(_ endpoint: some Endpoint) -> AnyPublisher<T, Error> where T: Decodable, {
        startRequest(for: endpoint, method: "GET", jsonBody: nil as String?)
            .tryMap { try $0.parseJson() }
            .eraseToAnyPublisher()
    }

    func post<T>(_ endpoint: some Endpoint, using body: (some Encodable)?,
                 using verificationCode: String? = nil) -> AnyPublisher<T, Error> where T: Decodable, {
        startRequest(for: endpoint, method: "POST", jsonBody: body, verificationCode: verificationCode)
            .tryMap { try $0.parseJson() }
            .eraseToAnyPublisher()
    }

    func post<T>(_ endpoint: some Endpoint, using queryItems: [URLQueryItem]?) -> AnyPublisher<T, Error> where T : Decodable, {
        startRequest(for: endpoint, method: "POST", jsonBody: nil as String?, queryItems: queryItems)
            .tryMap { try $0.parseJson() }
            .eraseToAnyPublisher()
    }


    private func startRequest(for endpoint: some Endpoint,
                              method: String,
                              jsonBody: (some Encodable)? = nil,
                              queryItems: [URLQueryItem]? = nil,
                              verificationCode:String?=nil)
        -> AnyPublisher<InterimRestResponse, Error> {
        var request: URLRequest

        do {
            request = try buildRequest(endpoint: endpoint, method: method, jsonBody: jsonBody,
                                       queryItems:queryItems, verificationCode: verificationCode)
        } catch {
            print("Failed to create request: \(String(describing: error))")
            return Fail(error: error).eraseToAnyPublisher()
        }

        print("Starting \(method) request for \(String(describing: request))")

        return session.dataTaskPublisher(for: request)
            .tryMap { (data: Data, response: URLResponse) in
                let response = response as! HTTPURLResponse
                print("Got response with status code \(response.statusCode) and \(data.count) bytes of data")

                #if DEBUG
                print(try! JSONSerialization.jsonObject(with: data, options: .allowFragments))
                #endif

                if !acceptableStatusCodes.contains(response.statusCode) {
                    throw RestClientError.requestFailed(code: response.statusCode)
                }

                return InterimRestResponse(data: data, response: response)
            }.eraseToAnyPublisher()
    }

    private func buildRequest(endpoint: some Endpoint,
                              method: String,
                              jsonBody: (some Encodable)?,
                              queryItems: [URLQueryItem]? = nil,
                              verificationCode: String? = nil) throws
        -> URLRequest {
        var request = URLRequest(url: endpoint.url, timeoutInterval: 10)

        if let queryItems {
            var urlComponents = URLComponents(string: endpoint.url.absoluteString)
            urlComponents?.queryItems = queryItems

            request = URLRequest(url: urlComponents?.url ?? endpoint.url , timeoutInterval: 10)
        }

        request.httpMethod = method

        if let apiAccessToken = NetworkRequest.accessToken {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiAccessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("2021-09-07", forHTTPHeaderField: "CB-VERSION")
        }

        if let verificationCode {
            request.setValue(verificationCode, forHTTPHeaderField: "CB-2FA-TOKEN")
        }

        // if we got some data, we encode as JSON and put it in the request
        if let body = jsonBody {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw RestClientError.jsonDecode(error: error)
            }
        }

        return request
    }

    struct InterimRestResponse {
        let data: Data
        let response: HTTPURLResponse

        func parseJson<T: Decodable>() throws -> T {
            if data.isEmpty {
                throw RestClientError.noDataReceived
            }

            do {
                let result = try JSONDecoder().decode(T.self, from: data)
                print("JSON Result: \(result)", String(describing: result))
                return result
            } catch {
                print("Failed to decode JSON: \(error)", String(describing: error))
                throw RestClientError.jsonDecode(error: error)
            }
        }
    }

}

