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
            "Aarón", "Abel", "Abelardo", "Abraham", "Adán", "Adolfo", "Adrián", "Agustín", "Alan", "Alejo",
            "Alejandro", "Alexis", "Alfonso", "Alfredo", "Alonso", "Álvaro", "Amadeo", "Amador", "Amílcar", "Américo",
            "Aníbal", "Andrés", "Ángel", "Anselmo", "Antonio", "Ariel", "Armando", "Arnoldo", "Arturo", "Augusto",
            "Aureliano", "Baltazar", "Bautista", "Benicio", "Benjamín", "Bernardo", "Blas", "Boris", "Braulio", "Brayan",
            "Bruno", "Caín", "Camilo", "Carmelo", "Casimiro", "Ciro", "Claudio", "Clemente", "Conrado", "Cristóbal",
            "Damián", "Dante", "Darío", "David", "Demetrio", "Domingo", "Edgar", "Edgardo", "Edilberto", "Eduardo",
            "Efraín", "Elías", "Eloy", "Emanuel", "Emilio", "Enrique", "Ernesto", "Esteban", "Eugenio", "Eusebio",
            "Evaristo", "Ezequiel", "Facundo", "Fabián", "Fabio", "Fabricio", "Felipe", "Félix", "Fermín", "Flavio",
            "Francisco", "Franco", "Froilán", "Gabriel", "Gael", "Gaspar", "Genaro", "Gerardo", "Germán", "Gilberto",
            "Gonzalo", "Gregorio", "Guillermo", "Gustavo", "Héctor", "Hernán", "Hilario", "Horacio", "Hugo", "Humberto",
            "Ignacio", "Iker", "Ismael", "Israel", "Iván", "Jacinto", "Jaime", "Jeremías", "Jesús", "Joaquín",
            "Joel", "Jonás", "Jonathan", "Josué", "Julián", "Julio", "Leandro", "Leonardo", "Leonel", "Lorenzo",
            "Lucas", "Luciano", "Marco", "Marcelo", "Marcos", "Mariano", "Mario", "Martín", "Mateo", "Matías",
            "Mauricio", "Maximiliano", "Máximo", "Milton", "Nahuel", "Néstor", "Nicolás", "Noel", "Octavio", "Omar",
            "Orlando", "Óscar", "Pablo", "Patricio", "Paulo", "Rafael", "Ramiro", "Ramón", "Renato", "Roberto",
            "Rodolfo", "Rodrigo", "Rogelio", "Rolando", "Román", "Rubén", "Salvador", "Samuel", "Santiago", "Sebastián",
            "Sergio", "Silvio", "Simón", "Tadeo", "Teodoro", "Tomás", "Valentín", "Vicente", "Xavier", "Yahir",
            "Yeray", "Yovani", "Yerson", "Yefri", "Wilfredo", "Willian", "Walter", "Fredy", "Franklin", "Grover",
            "Heber", "Hermes", "Jhonny", "Lenin", "Nelson", "Nilo", "Nixon", "Robinson", "Josimar", "Jairo",
            "Anderson", "Jean", "Thiago", "Tiago", "Mateus", "João", "Davi", "Enzo", "Arthur", "Heitor",
            "Theo", "Matheus", "Henrique", "Guilherme", "Vinícius", "Caio", "Murilo", "Vitor", "Yuri", "Antônio",
            "Luan", "Danilo", "Edson", "Everton", "Fabiano", "Luiz", "Márcio", "Ruan", "Valter", "Wagner",
            "Zeca", "Wenceslao", "Waldir", "Ubaldo", "Teófilo", "Uriel", "Ulises", "Valério", "Venancio", "Vasco",
            "Wálter", "Yair", "Yordi", "Yordy", "Yul", "Yulian", "Yosimar", "Zacarías", "Zenón", "Cristhian",
            "Jhonatan", "Jhoel", "Jhordan", "Stiven", "Deyvis", "Deivis", "Yelsin", "Yeferson", "Yonatan", "John",
            "Johnatan", "Juan Pablo", "Juan Carlos", "Juan José", "José Luis", "José Antonio", "José Manuel", "Luis Alberto", "Luis Enrique", "Carlos Alberto",
            "Carlos Andrés", "Miguel Ángel", "Marco Antonio", "Pedro José", "José María", "Juan Diego", "Juan Sebastián", "José Miguel", "Luis Fernando", "Juan Manuel",
            "José Ángel", "Abigail", "Aída", "Alejandra", "Alicia", "Amalia", "Ángela", "Antonella", "Araceli", "Beatriz",
            "Belén", "Brenda", "Brisa", "Carla", "Carolina", "Catalina", "Cecilia", "Celeste", "Clara", "Claudia",
            "Constanza", "Cristina", "Daniela", "Débora", "Elena", "Emilia", "Emma", "Erika", "Estefanía", "Eva",
            "Fátima", "Fernanda", "Gabriela", "Guadalupe", "Inés", "Isabel", "Jazmín", "Jennifer", "Jessica", "Josefina",
            "Juliana", "Laura", "Leonor", "Lorena", "Lourdes", "Luisa", "Mabel", "Magdalena", "Micaela", "Natalia",
            "Noelia", "Olivia", "Paola", "Pilar", "Priscila", "Renata", "Sabrina", "Sara", "Silvia", "Tamara",
            "Tatiana", "Teresa", "Vanessa", "Verónica", "Victoria", "Viviana", "Ximena", "Yadira", "Yuliana", "Zoe",
            "Noemí", "Amparo", "Aurora", "Bianca", "Candelaria", "Carmela", "Dayana", "Eliana", "Estrella", "Fabiola",
            "Florencia", "Graciela", "Irma", "Julieta", "Karen", "Kiara", "Mariana", "Marisol", "Martina", "Mayra",
            "Melina", "Mirella", "Mónica", "Nidia", "Paulina", "Soledad", "Susana", "Valentina", "Xiomara", "Yessica",
            "Yolanda", "Zulema", "Isidora", "Lía", "Maite", "Nayeli", "Rafaela", "Romina", "Salomé", "Violeta",
        ],
        last: [
            "Flores", "Quispe", "García", "Rodríguez", "Mamani", "Huamán", "Sánchez", "Rojas", "Chávez", "Vásquez",
            "Torres", "Ramírez", "Castillo", "Díaz", "Mendoza", "Gutiérrez", "Ramos", "Espinoza", "López", "Pérez",
            "Vargas", "Cruz", "Silva", "Gonzales", "Fernández", "Romero", "Salazar", "Morales", "Herrera", "Medina",
            "Aguilar", "Castro", "Ríos", "Paredes", "Cárdenas", "Córdova", "Palomino", "Huanca", "Condori", "Zapata",
            "Valverde", "Delgado", "Benites", "Navarro", "Soto", "Reyes", "Campos", "Villanueva", "Alvarado", "Guerrero",
            "Alarcón", "Alcántara", "Alfaro", "Aliaga", "Almanza", "Alva", "Álvarez", "Amaya", "Andrade", "Angulo",
            "Antayhua", "Arana", "Arce", "Arévalo", "Arellano", "Arias", "Armas", "Arroyo", "Asencios", "Atoche",
            "Asto", "Avendaño", "Ayala", "Baca", "Ballón", "Barboza", "Barrera", "Barreto", "Barrios", "Bautista",
            "Bazán", "Becerra", "Bedoya", "Beltrán", "Bendezú", "Benavente", "Bermúdez", "Bernal", "Berríos", "Betancourt",
            "Blanco", "Blas", "Bolaños", "Bonilla", "Borja", "Bravo", "Briceño", "Bustamante", "Caballero", "Cabrera",
            "Cáceres", "Caldas", "Calderón", "Calle", "Camacho", "Carpio", "Carrasco", "Carranza", "Carreño", "Castañeda",
            "Castellanos", "Cayo", "Ceballos", "Centeno", "Cerrón", "Cervantes", "Chacón", "Chambi", "Chancay", "Chaparro",
            "Chavarría", "Checa", "Chino", "Choque", "Cieza", "Cisneros", "Colán", "Collantes", "Colque", "Cornejo",
            "Coronado", "Correa", "Cortés", "Cuadros", "Dávalos", "Dávila", "De la Cruz", "De la Torre", "Del Águila", "Del Carpio",
            "Del Río", "Del Solar", "Del Valle", "Domínguez", "Donayre", "Durán", "Echevarría", "Escalante", "Escobar", "Espinal",
            "Espino", "Estrada", "Fajardo", "Falcón", "Farfán", "Ferreyra", "Figueroa", "Fonseca", "Franco", "Frías",
            "Fuentes", "Gálvez", "Garay", "Garrido", "Gil", "Godoy", "Gómez", "Grados", "Granados", "Guevara",
            "Guerra", "Guillén", "Guzmán", "Haro", "Henríquez", "Hidalgo", "Huallpa", "Huarcaya", "Huari", "Huayta",
            "Huillca", "Hurtado", "Ibáñez", "Infante", "Jara", "Jiménez", "Juárez", "Lazo", "León", "Linares",
            "Lira", "Loayza", "Loli", "Lora", "Loyola", "Luján", "Luna", "Macedo", "Maldonado", "Manrique",
            "Mariátegui", "Márquez", "Martínez", "Mejía", "Meléndez", "Meneses", "Merino", "Meza", "Miranda", "Molina",
            "Moncada", "Montes", "Montoya", "Mora", "Moreno", "Mosquera", "Muñoz", "Najarro", "Nieto", "Núñez",
            "Ochoa", "Oliva", "Olivares", "Olórtegui", "Orellana", "Oré", "Ortega", "Ortiz", "Osorio", "Pacheco",
            "Pajuelo", "Palacios", "Pantoja", "Patiño", "Paz", "Peña", "Peralta", "Pineda", "Pizarro", "Ponce",
            "Portugal", "Prado", "Prieto", "Pulgar", "Quiroz", "Quintana", "Rengifo", "Reyna", "Robles", "Roldán",
            "Rosales", "Rubio", "Ruiz", "Saavedra", "Salas", "Salcedo", "Salinas", "Sanabria", "Sandoval", "Santillán",
            "Santos", "Segura", "Seminario", "Sierra", "Solano", "Solís", "Soria", "Sotelo", "Sotomayor", "Suárez",
            "Tapia", "Tello", "Terán", "Toledo", "Trujillo", "Ugarte", "Uribe", "Valdivia", "Valencia", "Valle",
            "Varela", "Vega", "Vela", "Velásquez", "Vera", "Vergara", "Vidal", "Vilca", "Villacorta", "Villalobos",
            "Villegas", "Yáñez", "Yupanqui", "Zavala", "Zurita", "Apaza", "Ccahuana", "Ccollana", "Ccollque", "Chura",
            "Cutipa", "Huanaco", "Huayllani", "Huanacuni", "Lipa", "Sucari", "Ticona", "Yucra", "Abarca", "Abascal",
            "Acevedo", "Adame", "Ahumada", "Almonte", "Alvarenga", "Amaro", "Arriaga", "Altamirano", "Avila", "Báez",
            "Barros", "Belmonte", "Benítez", "Borges", "Botero", "Bracamonte", "Bustos", "Cardoso", "Carmona", "Carvalho",
            "Castaño", "Chaves", "Córdoba", "Corral", "Costa", "Dantas", "Da Costa", "Da Silva", "De Almeida", "De Souza",
            "Dias", "Domingues", "Dos Santos", "Duarte", "Escamilla", "Escobedo", "Esparza", "Espinosa", "Estévez", "Ferreira",
            "Furtado", "Galindo", "Gallegos", "Gama", "Garza", "Gatica", "Godínez", "Hernández", "Ibarra", "Lara",
            "Lemus", "Leiva", "Londoño", "Macías", "Marín", "Mármol", "Matos", "Mena", "Mondragón", "Montero",
            "Montiel", "Moreira", "Nascimento", "Nava", "Noriega", "Ocampo", "Olmedo", "Olvera", "Padilla", "Pardo",
            "Perdomo", "Pereira", "Pimentel", "Pinto", "Quintero", "Rangel", "Rendón", "Rentería", "Restrepo", "Rivas",
            "Rocha", "Rosas", "Saldívar", "Salgado", "San Martín", "Sepúlveda", "Serrano", "Soler", "Tavares", "Treviño",
            "Valdez", "Vázquez", "Velasco", "Villalba", "Zambrano", "Zárate", "Arteaga", "Balderas", "Barahona", "Barragán",
            "Barrientos", "Basurto", "Batalla", "Bocanegra", "Bohórquez", "Borrego", "Bustillo", "Calvillo", "Carrillo", "Casillas",
            "Castañón", "Cebrián", "Cepeda", "Cervera", "Chapa", "Cifuentes", "Covarrubias", "Cuenca", "Cuevas", "Corcuera",
            "Cueto", "Daza", "De León", "De los Santos", "De la Rosa", "Del Castillo", "Del Toro", "Enríquez", "Esquivel", "Farías",
            "Galván", "Guardado", "Holguín", "Huerta", "Jaimes", "Jaramillo", "Ledesma", "Llerena", "Mancilla", "Manzo",
            "Marroquín", "Melgar", "Millán", "Montalvo", "Naranjo", "Orozco", "Quezada", "Quesada", "Quevedo", "Reynoso",
            "Rincón", "Roque", "Sáenz", "Santa Cruz", "Sarmiento", "Téllez", "Tejada", "Tirado", "Tobar", "Urrutia",
            "Valenzuela", "Vallejo", "Vargas", "Acuña", "Aguilera", "Aguirre", "Alonso", "Arrieta", "Barrera", "Bernárdez",
            "Carrera", "Castañares", "Cordero", "Cossío", "Delgadillo", "Escudero", "Ferrer", "Gaitán", "Goyeneche", "Heredia",
            "Neira", "Ninahuanca", "Navarrete", "Oliván", "Paredón", "Rebolledo", "Santana", "Tovar", "Vizcarra", "Zelaya",
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
