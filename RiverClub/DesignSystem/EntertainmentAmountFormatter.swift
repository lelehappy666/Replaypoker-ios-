import Foundation

enum EntertainmentAmountFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func string(_ value: Int) -> String {
        let formatted = numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        if formatted.hasPrefix("-") {
            return "-$\(formatted.dropFirst())"
        }
        return "$\(formatted)"
    }
}
