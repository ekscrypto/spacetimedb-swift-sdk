//
//  main.swift
//  spacetime-swift
//
//  Local code generator that turns a SpacetimeDB module schema (JSON)
//  into Swift source files using the BSATNRow / Reducer protocols.
//

import Foundation

func usage() -> String {
    """
    spacetime-swift — Swift codegen for SpacetimeDB schemas

    Usage:
      spacetime-swift generate (--schema <path.json> | --uri <host> --db <name>)
                               --out <dir> [--version <n>]

    Sources (pick one):
      --schema <path>     Local SpacetimeDB schema JSON file.
      --uri <host>        SpacetimeDB host root (e.g. https://maincloud.spacetimedb.com).
      --db <name>         Database name (used with --uri).
      --version <n>       Schema version to fetch (default: 9).

    --out <dir>           Output directory; created if missing.

    Generated files:
      <Table>Row.swift            One per table (BSATNRow or
                                  BSATNTableWithPrimaryKey when the
                                  table has a primary key).
      <Type>.swift                One per named non-table product/sum
                                  type from the schema.
      <Reducer>Reducer.swift      One per non-lifecycle reducer.
    """
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    FileHandle.standardError.write(Data((usage() + "\n").utf8))
    exit(code)
}

struct Options {
    var schemaFile: String?
    var uri: String?
    var db: String?
    var out: String?
    var version: Int = 9
}

func parseArgs(_ args: [String]) -> Options {
    var opts = Options()
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--schema":
            guard i + 1 < args.count else { fail("--schema requires a value") }
            opts.schemaFile = args[i + 1]; i += 2
        case "--uri":
            guard i + 1 < args.count else { fail("--uri requires a value") }
            opts.uri = args[i + 1]; i += 2
        case "--db":
            guard i + 1 < args.count else { fail("--db requires a value") }
            opts.db = args[i + 1]; i += 2
        case "--out":
            guard i + 1 < args.count else { fail("--out requires a value") }
            opts.out = args[i + 1]; i += 2
        case "--version":
            guard i + 1 < args.count, let v = Int(args[i + 1]) else { fail("--version requires an integer") }
            opts.version = v; i += 2
        case "-h", "--help":
            print(usage()); exit(0)
        default:
            fail("unknown argument '\(a)'")
        }
    }
    return opts
}

let argv = Array(CommandLine.arguments.dropFirst())
guard !argv.isEmpty, argv.first == "generate" else {
    fail("missing or unknown subcommand; expected 'generate'")
}

let opts = parseArgs(Array(argv.dropFirst()))
guard let outPath = opts.out else { fail("--out is required") }
let outURL = URL(fileURLWithPath: outPath, isDirectory: true)

func fetchHTTP(uri: String, db: String, version: Int) -> Data {
    var host = uri
    if host.hasPrefix("ws://")  { host = "http://"  + host.dropFirst(5) }
    if host.hasPrefix("wss://") { host = "https://" + host.dropFirst(6) }
    if host.hasSuffix("/")      { host = String(host.dropLast()) }
    guard let url = URL(string: "\(host)/v1/database/\(db)/schema?version=\(version)") else {
        fail("invalid --uri '\(uri)'")
    }

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<Data, Error>?
    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error { result = .failure(error) }
        else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            result = .failure(NSError(domain: "spacetime-swift", code: http.statusCode,
                                       userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(url)"]))
        } else if let data { result = .success(data) }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    switch result {
    case .success(let data): return data
    case .failure(let err):  fail("schema fetch failed: \(err.localizedDescription)")
    case .none:              fail("schema fetch produced no result")
    }
}

let schemaData: Data
switch (opts.schemaFile, opts.uri, opts.db) {
case (let path?, nil, nil):
    do { schemaData = try Data(contentsOf: URL(fileURLWithPath: path)) }
    catch { fail("cannot read '\(path)': \(error.localizedDescription)") }
case (nil, let uri?, let db?):
    schemaData = fetchHTTP(uri: uri, db: db, version: opts.version)
default:
    fail("provide either --schema <path> OR --uri <host> --db <name>")
}

let doc: SchemaDoc
do {
    doc = try JSONDecoder().decode(SchemaDoc.self, from: schemaData)
} catch {
    fail("invalid schema JSON: \(error)")
}

do {
    try validateSchemaNames(doc)
} catch {
    fail("\(error)")
}

try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

let emitter = SwiftEmitter(schema: doc)
let files = emitter.emit()

let outBase = outURL.standardizedFileURL.resolvingSymlinksInPath().path
for (name, contents) in files.sorted(by: { $0.key < $1.key }) {
    let dest = outURL.appendingPathComponent(name)
    let resolved = dest.standardizedFileURL.resolvingSymlinksInPath().path
    let prefix = outBase.hasSuffix("/") ? outBase : outBase + "/"
    guard resolved.hasPrefix(prefix) else {
        fail("refusing to write '\(name)': resolves outside --out (\(resolved))")
    }
    do {
        try contents.write(to: dest, atomically: true, encoding: .utf8)
        print("wrote \(dest.path)")
    } catch {
        fail("cannot write \(dest.path): \(error.localizedDescription)")
    }
}

print("✅ generated \(files.count) file\(files.count == 1 ? "" : "s") in \(outURL.path)")
