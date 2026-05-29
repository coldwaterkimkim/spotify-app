import Foundation

extension Dictionary where Key == String, Value == String {
    var formURLEncodedData: Data {
        map { key, value in
            "\(key.urlFormEscaped)=\(value.urlFormEscaped)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

extension String {
    var urlFormEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}
