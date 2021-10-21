import Foundation
import SwiftUI
import Combine
import TextTranslator

struct DragomanListener: ViewModifier {
    @EnvironmentObject var dragoman: Dragoman
    @State private var localId = UUID().uuidString
    func body(content: Content) -> some View {
        return content.id(localId).onReceive(dragoman.changed) {
            localId = UUID().uuidString
        }
    }
}
public extension View {
    func autoUpdate() -> some View {
        self.modifier(DragomanListener())
    }
}
public enum DragomanError : Error {
    case disabled
    case noTranslationService
    case unableToConvertStringsToData
}
public class Dragoman: ObservableObject {
    public struct TranslationTable: TextTransaltionTable {
        public var db: [LanguageKey: [TranslationKey: TranslatedValue]] = [:]
        mutating func merge(with table:TranslationTable) {
            for (lang,vals) in table.db {
                for (k,v) in vals {
                    if db[lang] == nil {
                        db[lang] = [:]
                    }
                    db[lang]?[k] = v
                }
            }
        }
    }
    public typealias LanguageKey = String
    public typealias Value = String
    public typealias Key = String
    
    private let manager = FileManager.default
    private var baseBundle: Bundle {
        didSet {
            UserDefaults.standard.set(baseBundle.bundleURL.lastPathComponent, forKey: "DragomanCurrentBundleName")
        }
    }
    private var appBundle: Bundle
    private var tableName: String
    public var translationService: TextTranslationService?
    private var publishers = Set<AnyCancellable>()
    
    private let changedSubject = PassthroughSubject<Void, Never>()
    private let failedSubject = PassthroughSubject<Error, Never>()
    private let cleanedSubject = PassthroughSubject<Void, Never>()
    private let valueSubject = CurrentValueSubject<Date,Never>(Date())
    
    public private(set) var supportedLanguages = [LanguageKey]()
    
    @Published public var disabled: Bool = false
    @Published public private(set) var bundle: Bundle = Bundle.main
    @Published public var locale:Locale {
        didSet {
            updateBundles()
        }
    }
    
    public let changed: AnyPublisher<Void, Never>
    public let failed: AnyPublisher<Error, Never>
    public let cleaned: AnyPublisher<Void, Never>
    
    public init(tableName: String = "Localizable", translationService: TextTranslationService? = nil, locale:Locale, supportedLanguages:[LanguageKey]) {
        self.locale = locale
        self.supportedLanguages = supportedLanguages
        self.tableName = tableName
        if let name = UserDefaults.standard.string(forKey: "DragomanCurrentBundleName"),let b = Self.getBundle(for: name) {
            baseBundle = b
        } else {
            baseBundle = Self.createBundle(tableName: tableName, languages: supportedLanguages)
        }
        appBundle = Self.appBundle(for: locale)
        bundle = Self.languageBundle(bundle: baseBundle, for: locale)
        self.translationService = translationService
        self.changed = changedSubject.eraseToAnyPublisher()
        self.failed = failedSubject.eraseToAnyPublisher()
        self.cleaned = cleanedSubject.eraseToAnyPublisher()
    }
    static func getBundle(for name:String) -> Bundle? {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let url = documents.appendingPathComponent(name, isDirectory: true)
        return Bundle(path: url.path)
    }
    static func createBundle(tableName:String, languages:[LanguageKey]) -> Bundle {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let bundlePath = documents.appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        Self.createFoldersAndFiles(bundlePath: bundlePath, tableName: tableName, languages: languages)
        return Bundle(url: bundlePath)!
    }
    static func createFoldersAndFiles(bundlePath:URL, tableName:String, languages:[LanguageKey]) {
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: bundlePath.path) == false {
                try manager.createDirectory(at: bundlePath, withIntermediateDirectories: true, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
            }
            for lang in languages {
                let langPath = bundlePath.appendingPathComponent("\(lang).lproj", isDirectory: true)
                if manager.fileExists(atPath: langPath.path) == false {
                    try manager.createDirectory(at: langPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
                }
                let filePath = langPath.appendingPathComponent("\(tableName).strings")
                if manager.fileExists(atPath: filePath.path) == false {
                    manager.createFile(atPath: filePath.path, contents: nil, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
                }
            }
            print(bundlePath)
        } catch {
            print(error)
        }
    }
    static private func appBundle(for locale:Locale) -> Bundle {
        if let b = bundleByLanguageCode(bundle: Bundle.main, for: locale) {
            return b
        }
        return Bundle.main
    }
    static private func languageBundle(bundle:Bundle, for locale:Locale) -> Bundle {
        if let b = bundleByLanguageCode(bundle: bundle, for: locale) {
            return b
        }
        return bundle
    }
    static private func bundleByIdentifier(bundle:Bundle, for locale:Locale) -> Bundle? {
        guard let path = bundle.path(forResource: locale.identifier, ofType: "lproj") else {
            return nil
        }
        guard let languageBundle = Bundle(path: path) else {
            return nil
        }
        return languageBundle
    }
    static private func bundleByLanguageCode(bundle:Bundle, for locale:Locale) -> Bundle? {
        guard let languageCode = locale.languageCode else {
            return nil
        }
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        guard let languageBundle = Bundle(path: path) else {
            return nil
        }
        return languageBundle
    }
    public func clean() {
        clean(bundle:baseBundle)
    }
    private func clean(bundle:Bundle) {
        do {
            if manager.fileExists(atPath: bundle.bundlePath) {
                try manager.removeItem(at: bundle.bundleURL)
            }
            cleanedSubject.send()
        } catch {
            failedSubject.send(error)
        }
    }
    public func translate(_ texts: [String], from: LanguageKey, to: [LanguageKey]) -> AnyPublisher<Void,Error> {
        if disabled {
            return Fail(error: DragomanError.disabled).eraseToAnyPublisher()
        }
        let subj = PassthroughSubject<Void,Error>()
        var all = to
        all.append(from)
        let table = translations(in: all)
        guard let translationService = translationService else {
            return Fail(error: DragomanError.disabled).eraseToAnyPublisher()
        }
        var p:AnyCancellable?
        p = translationService.translate(texts, from: from, to: to, storeIn: table).receive(on: DispatchQueue.main).sink(receiveCompletion: { compl in
            switch compl {
            case .failure(let error): subj.send(completion: .failure(error))
            case .finished: break
            }
        }, receiveValue: { [weak self] table in
            guard let this = self, let table = table as? TranslationTable else {
                return
            }
            var curr = this.translations(in: all)
            curr.merge(with: table)
            self?.write(curr)
            if let p = p {
                self?.publishers.remove(p)
            }
            subj.send()
        })
        if let p = p {
            publishers.insert(p)
        }
        return subj.eraseToAnyPublisher()
    }
    public func translations(in languages: [LanguageKey]) -> TranslationTable {
        var t = TranslationTable()
        for language in languages {
            if let url = baseBundle.url(forResource: tableName, withExtension: "strings", subdirectory: nil, localization: language), let stringsDict = NSDictionary(contentsOf: url) as? [String: String] {
                for (key, value) in stringsDict {
                    t[language, key] = value
                }
            }
        }
        return t
    }
    public func publisher(for key:String) -> AnyPublisher<String,Never> {
        return valueSubject.map { _ in
            return self.string(forKey: key)
        }.eraseToAnyPublisher()
    }
    public func string(forKey key:String) -> String {
        let error = "## error no translation ##"
        let str = appBundle.localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return bundle.localizedString(forKey: key, value: nil, table: tableName)
        }
        return str
    }
    public func string(forKey key:String, in language:LanguageKey) -> String {
        if language == self.locale.languageCode {
            return string(forKey: key)
        }
        let error = "## error no translation ##"
        let str = Self.appBundle(for: Locale(identifier: language)).localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return Self.languageBundle(bundle: baseBundle, for: Locale(identifier: language)).localizedString(forKey: key, value: nil, table: tableName)
        }
        return str
    }
    public func string(forKey key:String, with locale:Locale) -> String {
        if locale.languageCode == self.locale.languageCode {
            return string(forKey: key)
        }
        let error = "## error no translation ##"
        let str = Self.appBundle(for: locale).localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return Self.languageBundle(bundle: baseBundle, for: locale).localizedString(forKey: key, value: nil, table: tableName)
        }
        return str
    }
    public func write(_ translations: TranslationTable) {
        if disabled {
            return
        }
        do {
            let old = baseBundle
            let new = Self.createBundle(tableName: tableName, languages: supportedLanguages)
            for language in translations.db {
                let lang = language.key
                let langPath = new.bundleURL.appendingPathComponent("\(lang).lproj", isDirectory: true)
                if manager.fileExists(atPath: langPath.path) == false {
                    try manager.createDirectory(at: langPath, withIntermediateDirectories: true, attributes: [:])
                }
                let sentences = language.value
                let res = sentences.reduce("", { $0 + "\"\($1.key)\" = \"\($1.value)\";\n" })
                let filePath = langPath.appendingPathComponent("\(tableName).strings")
                guard let data = res.data(using: .utf8) else {
                    throw DragomanError.unableToConvertStringsToData
                }
                try data.write(to: filePath)
            }
            baseBundle = new
            updateBundles()
            clean(bundle: old)
            changedSubject.send()
            valueSubject.send(Date())
        } catch {
            debugPrint(error)
            failedSubject.send(error)
        }
    }
    private func updateBundles() {
        bundle = Self.languageBundle(bundle: baseBundle, for: locale)
        appBundle = Self.appBundle(for: locale)
    }
}
