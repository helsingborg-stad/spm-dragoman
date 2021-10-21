import Foundation
import SwiftUI
import Combine
import TextTranslator


/// Dragoman related errors
public enum DragomanError : Error {
    /// In case the isntance is disabled
    case disabled
    /// In case there is no assigned translation service
    case noTranslationService
    /// In case the translated data cannot be converted to a Data object
    case unableToConvertStringsToData
}
/// Dragoman is a localization and translation manager that uses a local device bundle to store .strings -files
public class Dragoman: ObservableObject {
    /// A TranslationTable implementation
    public struct TranslationTable: TextTransaltionTable {
        /// The translation database
        public var db: [LanguageKey: [TranslationKey: TranslatedValue]] = [:]
        /// Merge self with another table. Any value that exists in the new table will overwrite the current database values
        /// - Parameter table: table to merge with
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
        /// Remove all provided strings, in all languages, from database
        /// - Parameter strings: strings to remove
        mutating func remove(strings:[String]) {
            var db = db
            for (lang,dict) in db {
                var dict = dict
                for s in strings {
                    guard let index = dict.index(forKey: s) else {
                        continue
                    }
                    dict.remove(at: index)
                }
                db[lang] = dict
            }
            self.db = db
        }
    }
    /// Used to identify a lanugage. Can be any string you desire but should be Apple Locale.languageCode compatible
    public typealias LanguageKey = String
    /// Used to decribe a value for a key
    public typealias Value = String
    /// Used to identify a value
    public typealias Key = String
    
    /// The base bundle where all .proj folder are stored
    private var baseBundle: Bundle {
        didSet {
            UserDefaults.standard.set(baseBundle.bundleURL.lastPathComponent, forKey: "DragomanCurrentBundleName")
        }
    }
    /// The current app bundle, ie Bundle.main in your application
    private var appBundle: Bundle
    /// The name of the table where all strings are stored
    private let tableName: String = "Localizable"
    /// The translation service used to translate strings
    public var translationService: TextTranslationService?
    /// Cancellables storage
    private var cancellables = Set<AnyCancellable>()
    /// Triggeres when changes occurs
    private let changedSubject = PassthroughSubject<Void, Never>()
    /// Triggeres when a failure occurs
    private let failedSubject = PassthroughSubject<Error, Never>()
    /// Supported locales, must be set on initialization
    public private(set) var supportedLanguages = [LanguageKey]()
    
    /// Indicates whether or not the dragoman translation service and file writes are disabled
    @Published public var disabled: Bool = false
    /// The bundle of the currently selected language
    @Published public private(set) var bundle: Bundle = Bundle.main
    /// The current language. When changed the bundles will update to the current language bundle
    @Published public var language:LanguageKey {
        didSet {
            updateBundles()
        }
    }
    
    /// Publisher that triggers whenever a new file is written to disk
    public let changed: AnyPublisher<Void, Never>
    /// Publisher that triggers whenever an error occurs
    public let failed: AnyPublisher<Error, Never>
    
    /// Initializes a new
    /// - Parameters:
    ///   - translationService: transaltion service to use when calling  translate(texts:from:to:)
    ///   - language: currently selected lanugage
    ///   - supportedLanguages: all supported languages
    public init(translationService: TextTranslationService? = nil, language:LanguageKey, supportedLanguages:[LanguageKey]) {
        self.language = language
        self.supportedLanguages = supportedLanguages
        if let name = UserDefaults.standard.string(forKey: "DragomanCurrentBundleName"), let b = Self.getBundle(for: name) {
            baseBundle = b
        } else if let bundle = try? Self.createBundle(tableName: tableName, languages: supportedLanguages) {
            baseBundle = bundle
        } else {
            baseBundle = Bundle.main
            disabled = true
        }
        appBundle = Self.appBundle(for: language)
        bundle = Self.languageBundle(bundle: baseBundle, for: language)
        self.translationService = translationService
        self.changed = changedSubject.eraseToAnyPublisher()
        self.failed = failedSubject.eraseToAnyPublisher()
    }
    /// Load bundle from document directory (if it exists)
    /// - Parameter name: the bundle name, must include .bundle
    /// - Returns: a bundle if any
    static func getBundle(for name:String) -> Bundle? {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let url = documents.appendingPathComponent(name, isDirectory: true)
        return Bundle(path: url.path)
    }
    /// Create a new bundle within the document directory
    /// - Parameters:
    ///   - tableName: .strings-file table name
    ///   - languages: language specific .lproj-folders to create
    /// - Returns: a new bundle
    static func createBundle(tableName:String, languages:[LanguageKey]) throws -> Bundle {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let bundlePath = documents.appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        try Self.createFoldersAndFiles(bundlePath: bundlePath, tableName: tableName, languages: languages)
        return Bundle(url: bundlePath)!
    }
    /// Creates bundle and language folders in given path
    /// - Parameters:
    ///   - bundlePath: the full path of the .bundle-folder
    ///   - tableName: the name of the .strings-file
    ///   - languages: language specific .lproj-folders to create
    static func createFoldersAndFiles(bundlePath:URL, tableName:String, languages:[LanguageKey]) throws {
        let manager = FileManager.default
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
    }
    /// Loads the a language bundle (LANG.lproj) from an application (typically Bundle.main)
    /// If no language bundle exits Bundle.main will be returned
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle
    static private func appBundle(for language:LanguageKey) -> Bundle {
        if let b = bundleByLanguageCode(bundle: Bundle.main, for: language) {
            return b
        }
        return Bundle.main
    }
    /// Loads the a language bundle (LANG.lproj) from a bundle
    /// If no language bundle exits `bundle` will be returned
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle
    static private func languageBundle(bundle:Bundle, for language:LanguageKey) -> Bundle {
        if let b = bundleByLanguageCode(bundle: bundle, for: language) {
            return b
        }
        return bundle
    }
    /// Loads the a language bundle (LANG.lproj) from a bundle if it exits
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle or nil
    static private func bundleByLanguageCode(bundle:Bundle, for language:LanguageKey) -> Bundle? {
        guard let path = bundle.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        guard let languageBundle = Bundle(path: path) else {
            return nil
        }
        return languageBundle
    }
    /// Remove all files from current bundle
    public func clean() {
        clean(bundle:baseBundle)
    }
    /// Remove all files from bundle
    /// - Parameter bundle: the bundle to remove
    private func clean(bundle:Bundle) {
        do {
            if FileManager.default.fileExists(atPath: bundle.bundlePath) {
                try FileManager.default.removeItem(at: bundle.bundleURL)
            }
        } catch {
            failedSubject.send(error)
        }
    }
    /// Removes all strings in all supported languages related to the specified keys
    /// - Parameter keys: keys to strings that should be removed
    public func remove(keys:[String]) {
        var table = translations(in: supportedLanguages)
        table.remove(strings: keys)
        write(table)
    }
    /// Translate texts from a language to a list of languages
    /// - Parameters:
    ///   - texts: the texts to translate, also used as keys to it's translated values
    ///   - from: original language
    ///   - to: languages to translate into, if nil the supportedLanguages will be used
    /// - Returns: completion publisher
    public func translate(_ texts: [String], from: LanguageKey, to: [LanguageKey]? = nil) -> AnyPublisher<Void,Error> {
        if disabled {
            return Fail(error: DragomanError.disabled).eraseToAnyPublisher()
        }
        var to = to ?? supportedLanguages
        to.removeAll { $0 == from }
        let subj = PassthroughSubject<Void,Error>()
        var all = to
        all.append(from)
        let table = translations(in: all)
        guard let translationService = translationService else {
            return Fail(error: DragomanError.noTranslationService).eraseToAnyPublisher()
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
                self?.cancellables.remove(p)
            }
            subj.send()
        })
        if let p = p {
            cancellables.insert(p)
        }
        return subj.eraseToAnyPublisher()
    }
    /// Reads all translations from disk
    /// - Parameter languages: langauges to include
    /// - Returns: a transaltion table contining all translations and it's keys
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
    /// Checks if the text is translated in provided languages
    /// - Parameters:
    ///   - text: the text
    ///   - languages: languages to use, if nil supportedLanguages will be used as default value
    /// - Returns: true if translations found, false if not
    public func isTranslated(_ text:String, in languages:[LanguageKey]? = nil) -> Bool {
        let lang = languages ?? supportedLanguages
        let error = "## error no translation \(UUID().uuidString) ##"
        for l in lang {
            if string(forKey: text, in: l, value: error) == error {
                return false
            }
        }
        return true
    }
    /// Get string in currently selected language. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, value:String? = nil) -> String {
        let error = "## error no translation \(UUID().uuidString) ##"
        let str = appBundle.localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return str
    }
    /// Get string in the provided language. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter language: the language in which to return the value
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, in language:LanguageKey, value:String? = nil) -> String {
        if language == self.language {
            return string(forKey: key)
        }
        let error = "## error no translation \(UUID().uuidString) ##"
        let str = Self.appBundle(for: language).localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return Self.languageBundle(bundle: baseBundle, for: language).localizedString(forKey: key, value: value, table: tableName)
        }
        return str
    }
    /// Get string in the provided locale. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter locale: the locale in which to return the value (uses `Locale.languageCode`)
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, with locale:Locale, value:String? = nil) -> String {
        guard let languageCode = locale.languageCode, supportedLanguages.contains(languageCode) else {
            return key
        }
        return string(forKey: key, in: languageCode,value: value)
    }
    /// Write a table to disk
    /// - Parameter translations: the transaltion table to be stored
    private func write(_ translations: TranslationTable) {
        if disabled {
            return
        }
        do {
            let old = baseBundle
            let new = try Self.createBundle(tableName: tableName, languages: supportedLanguages)
            for language in translations.db {
                let lang = language.key
                let langPath = new.bundleURL.appendingPathComponent("\(lang).lproj", isDirectory: true)
                if FileManager.default.fileExists(atPath: langPath.path) == false {
                    try FileManager.default.createDirectory(at: langPath, withIntermediateDirectories: true, attributes: [:])
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
        } catch {
            debugPrint(error)
            failedSubject.send(error)
        }
    }
    public func updateBundles() {
        bundle = Self.languageBundle(bundle: baseBundle, for: language)
        appBundle = Self.appBundle(for: language)
        changedSubject.send()
    }
}
