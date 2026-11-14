import Foundation

// Pure model: no UIKit/SwiftUI so Tests/main.swift can compile it with plain swiftc.

// MARK: - Interval

enum TimeUnit: String, Codable, CaseIterable, Identifiable {
    case seconds, minutes, hours

    var id: Self { self }
    var factor: Double {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        }
    }
    var short: String {
        switch self {
        case .seconds: "s"
        case .minutes: "min"
        case .hours: "h"
        }
    }
    var label: String {
        switch self {
        case .seconds: "Segundos"
        case .minutes: "Minutos"
        case .hours: "Horas"
        }
    }
}

struct Span: Codable, Hashable {
    var value: Int
    var unit: TimeUnit

    var seconds: Double { Double(max(1, value)) * unit.factor }
    var text: String { "\(max(1, value)) \(unit.short)" }
}

enum IntervalMode: String, Codable, CaseIterable, Identifiable {
    case fixed, random

    var id: Self { self }
    var label: String { self == .fixed ? "Fijo" : "Aleatorio" }
}

struct Interval: Codable, Hashable {
    var mode: IntervalMode = .fixed
    var fixed = Span(value: 30, unit: .seconds)
    var minimum = Span(value: 10, unit: .seconds)
    var maximum = Span(value: 2, unit: .minutes)

    /// Seconds until the next notification.
    func next() -> Double {
        guard mode == .random else { return fixed.seconds }
        let a = minimum.seconds, b = maximum.seconds
        return Double.random(in: min(a, b)...max(a, b))
    }

    var average: Double {
        mode == .fixed ? fixed.seconds : (minimum.seconds + maximum.seconds) / 2
    }

    var summary: String {
        mode == .fixed ? "Cada \(fixed.text)" : "\(minimum.text) – \(maximum.text)"
    }

    static func describe(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 {
            let m = s / 60, r = s % 60
            return r == 0 ? "\(m) min" : "\(m) min \(r) s"
        }
        if s < 86_400 {
            let h = s / 3600, m = (s % 3600) / 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        let d = s / 86_400, h = (s % 86_400) / 3600
        return h == 0 ? "\(d) d" : "\(d) d \(h) h"
    }
}

// MARK: - Amount

enum NumberStyle: String, Codable, CaseIterable, Identifiable {
    case plain, comma, dot, space, plainComma

    var id: Self { self }
    var group: String {
        switch self {
        case .plain, .plainComma: ""
        case .comma: ","
        case .dot: "."
        case .space: " "
        }
    }
    var decimal: String {
        switch self {
        case .plain, .comma: "."
        case .dot, .space, .plainComma: ","
        }
    }
    var sample: String { "1\(group)234\(decimal)56" }
}

struct AmountConfig: Codable, Hashable {
    var minimum: Double = 1
    var maximum: Double = 10_000
    var decimals = 0
    var style = NumberStyle.comma

    // ponytail: "sin límite" means no cap in the UI; 1e13 keeps minor units inside Int64.
    static let ceiling = 1e13

    private var places: Int { min(max(decimals, 0), 2) }
    private var scale: Int64 { [1, 10, 100][places] }

    /// Random amount in minor units (cents when decimals = 2).
    func random<G: RandomNumberGenerator>(using rng: inout G) -> Int64 {
        let bounds = [minimum, maximum].map {
            Int64((min(max($0, 0), Self.ceiling) * Double(scale)).rounded())
        }
        return Int64.random(in: bounds.min()!...bounds.max()!, using: &rng)
    }

    func format(_ minor: Int64) -> String {
        let whole = String(minor / scale)
        var grouped = ""
        for (i, ch) in whole.enumerated() {
            if i > 0, (whole.count - i) % 3 == 0 { grouped += style.group }
            grouped.append(ch)
        }
        guard places > 0 else { return grouped }
        let fraction = String(minor % scale)
        return grouped + style.decimal + String(repeating: "0", count: places - fraction.count) + fraction
    }

    var example: String { format(Int64((1234.56 * Double(scale)).rounded(.down))) }
}

// MARK: - Names

struct NamePool: Codable, Hashable {
    var first: [String]
    var last: [String]

    static let peru = NamePool(
        first: [
            "Oswaldo", "Carlos", "José", "Luis", "Jorge", "Juan", "Miguel", "Pedro", "Víctor", "César",
            "Raúl", "Ricardo", "Manuel", "Fernando", "Javier", "Alberto", "Diego", "Renzo", "Kevin", "Jhon",
            "Edwin", "Wilmer", "Percy", "Elmer", "Christian", "María", "Rosa", "Ana", "Carmen", "Luz",
            "Juana", "Gladys", "Milagros", "Lucía", "Sofía", "Valeria", "Camila", "Diana", "Patricia", "Karina",
            "Yesenia", "Flor", "Sandra", "Liliana", "Rocío", "Andrea", "Fiorella", "Katherine", "Jimena", "Mariela",
        ],
        last: [
            "Flores", "Quispe", "García", "Rodríguez", "Mamani", "Huamán", "Sánchez", "Rojas", "Chávez", "Vásquez",
            "Torres", "Ramírez", "Castillo", "Díaz", "Mendoza", "Gutiérrez", "Ramos", "Espinoza", "López", "Pérez",
            "Vargas", "Cruz", "Silva", "Gonzales", "Fernández", "Romero", "Salazar", "Morales", "Herrera", "Medina",
            "Aguilar", "Castro", "Ríos", "Paredes", "Cárdenas", "Córdova", "Palomino", "Huanca", "Condori", "Zapata",
            "Valverde", "Delgado", "Benites", "Navarro", "Soto", "Reyes", "Campos", "Villanueva", "Alvarado", "Guerrero",
        ]
    )
}

// MARK: - Templates

struct Template: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var title = ""
    var body: String

    static let payment = Template(
        name: "Pago recibido",
        body: "{nombre} {apellido:3}* te envió un pago por S/ {monto}. El cód. de seguridad es: {codigo}"
    )
}

struct Token: Identifiable {
    let code: String
    let info: String
    var id: String { code }

    static let all = [
        Token(code: "{nombre}", info: "Nombre al azar"),
        Token(code: "{apellido}", info: "Apellido completo"),
        Token(code: "{apellido:3}", info: "Primeras 3 letras del apellido"),
        Token(code: "{monto}", info: "Monto con el formato elegido"),
        Token(code: "{codigo}", info: "Código numérico al azar"),
    ]
}

// MARK: - Config

// ponytail: synthesized Codable; a new field without a default migration resets saved settings.
struct Config: Codable, Hashable {
    var templates: [Template] = [.payment]
    var activeID: UUID?
    var interval = Interval()
    var amount = AmountConfig()
    var codeDigits = 3
    var names = NamePool.peru
    var sound = true

    var activeTemplate: Template {
        templates.first { $0.id == activeID } ?? templates.first ?? .payment
    }
}

// MARK: - Rendering

struct Rendered: Hashable {
    var title: String
    var body: String
}

struct Renderer {
    let config: Config

    /// Same seed, same text: keeps previews still while the user types.
    func render(_ template: Template, seed: UInt64) -> Rendered {
        var rng = SplitMix64(seed: seed)
        return render(template, using: &rng)
    }

    func render<G: RandomNumberGenerator>(_ template: Template, using rng: inout G) -> Rendered {
        let first = config.names.first.randomElement(using: &rng) ?? "Oswaldo"
        let last = config.names.last.randomElement(using: &rng) ?? "Flores"
        let amount = config.amount.format(config.amount.random(using: &rng))
        var digits = ""
        for _ in 0..<12 { digits += String(Int.random(in: 0...9, using: &rng)) }
        let defaultDigits = config.codeDigits

        let resolve: (String, Int?) -> String? = { key, arg in
            switch key {
            case "nombre": return Self.clip(first, arg)
            case "apellido": return Self.clip(last, arg)
            case "monto": return amount
            case "codigo", "código": return String(digits.prefix(min(max(arg ?? defaultDigits, 1), 12)))
            default: return nil
            }
        }
        return Rendered(title: Self.fill(template.title, resolve), body: Self.fill(template.body, resolve))
    }

    static func clip(_ text: String, _ count: Int?) -> String {
        count.map { String(text.prefix(max($0, 0))) } ?? text
    }

    /// Replaces `{key}` and `{key:n}`; unknown tokens stay as written.
    static func fill(_ text: String, _ resolve: (String, Int?) -> String?) -> String {
        var out = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let parts = rest[rest.index(after: open)..<close].split(separator: ":", maxSplits: 1)
            let key = parts.first.map { $0.lowercased() } ?? ""
            let arg = parts.count > 1 ? Int(parts[1]) : nil
            out += resolve(key, arg) ?? String(rest[open...close])
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
