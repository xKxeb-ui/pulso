import Foundation

// Compiled with Pulso/Model.swift by CI: xcrun swiftc Pulso/Model.swift Tests/main.swift

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition {
        print("FALLO: \(message())")
        exit(1)
    }
}

var config = Config()
config.names = NamePool(first: ["Oswaldo"], last: ["Flores"])
config.amount.minimum = 16
config.amount.maximum = 16
let renderer = Renderer(config: config)

let prefix = "Oswaldo Flo* te envió un pago por S/ 16. El cód. de seguridad es: "
let payment = renderer.render(.payment, seed: 42).body
check(payment.hasPrefix(prefix), "plantilla: \(payment)")
let code = payment.dropFirst(prefix.count)
check(code.count == 3 && code.allSatisfy(\.isNumber), "código: \(code)")
check(renderer.render(.payment, seed: 7) == renderer.render(.payment, seed: 7), "semilla estable")

let custom = Template(name: "x", title: "{Nombre}", body: "{nombre:3}|{apellido}|{codigo:5}|{otro}|{")
let rendered = renderer.render(custom, seed: 1)
let parts = rendered.body.split(separator: "|", omittingEmptySubsequences: false)
check(rendered.title == "Oswaldo", "título: \(rendered.title)")
check(parts[0] == "Osw" && parts[1] == "Flores" && parts[2].count == 5, "tokens: \(parts)")
check(parts[3] == "{otro}" && parts[4] == "{", "tokens desconocidos: \(parts)")

var amount = AmountConfig()
var rng = SplitMix64(seed: 3)
for _ in 0..<5_000 {
    let value = amount.random(using: &rng)
    check((1...10_000).contains(value), "rango: \(value)")
}
check(amount.format(1_234) == "1,234", amount.format(1_234))
amount.decimals = 2
check(amount.format(123_456_789) == "1,234,567.89", amount.format(123_456_789))
amount.style = .dot
check(amount.format(5) == "0,05", amount.format(5))
amount.style = .space
amount.decimals = 0
check(amount.format(1_000_000) == "1 000 000", amount.format(1_000_000))
amount.style = .plain
check(amount.format(16) == "16", amount.format(16))
amount.minimum = 500
amount.maximum = 20
for _ in 0..<1_000 {
    check((20...500).contains(amount.random(using: &rng)), "rango invertido")
}
amount.maximum = 1e20
check(amount.random(using: &rng) <= Int64(AmountConfig.ceiling), "tope")

var interval = Interval()
interval.fixed = Span(value: 2, unit: .minutes)
check(interval.next() == 120, "fijo")
interval.mode = .random
interval.minimum = Span(value: 1, unit: .hours)
interval.maximum = Span(value: 30, unit: .seconds)
for _ in 0..<1_000 {
    check((30...3600).contains(interval.next()), "aleatorio")
}
check(Interval.describe(3_725) == "1 h 2 min", Interval.describe(3_725))
check(Interval.describe(45) == "45 s", Interval.describe(45))

let data = try JSONEncoder().encode(config)
check(try JSONDecoder().decode(Config.self, from: data) == config, "codable")

print("OK: modelo")
