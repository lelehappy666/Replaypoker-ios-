import Foundation

enum EntertainmentAmountFormatter {
    static func string(_ value: Int) -> String {
        "$\(value.formatted())"
    }
}
