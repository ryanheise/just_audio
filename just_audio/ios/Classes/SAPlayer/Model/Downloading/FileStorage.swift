//
//  FileStorage.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

/**
 Utility class to access audio files saved on the phone.
 */
struct FileStorage {
    private init() {}

    /**
     Generates a URL for a file that would be saved locally.

     Note: It is not guaranteed that the file actually exists.
     */
    static func getUrl(givenAName name: NameFile, inDirectory dir: FileManager.SearchPathDirectory) -> URL {
        let directoryPath = NSSearchPathForDirectoriesInDomains(dir, .userDomainMask, true)[0] as String
        let url = URL(fileURLWithPath: directoryPath)
        return url.appendingPathComponent(name)
    }

    static func isStored(_ url: URL) -> Bool {
        // https://stackoverflow.com/questions/42897844/swift-3-0-filemanager-fileexistsatpath-always-return-false
        // When determining if a file exists, we must use .path not .absolute string!
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func delete(_ url: URL) {
        if !isStored(url) {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.error("Could not delete a file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Audio

extension FileStorage {
    struct Audio {
        private var audioDataManager: AudioDataManager

        init(audioDataManager: AudioDataManager) {
            self.audioDataManager = audioDataManager
        }

        static func isStored(_ id: ID, in directory: FileManager.SearchPathDirectory) -> Bool {
            guard let url = locate(id, in: directory)?.path else {
                return false
            }

            // FIXME: This is an unreliable API. Maybe use a map instead?
            return FileManager.default.fileExists(atPath: url)
        }

        static func delete(_ id: ID, in directory: FileManager.SearchPathDirectory) {
            guard let url = locate(id, in: directory) else {
                Log.warn("trying to delete audio file that doesn't exist with id: \(id)")
                return
            }
            return FileStorage.delete(url)
        }

        static func write(_ id: ID, fileExtension: String, data: Data, in directory: FileManager.SearchPathDirectory) {
            do {
                let url = FileStorage.getUrl(givenAName: getAudioFileName(id, fileExtension: fileExtension), inDirectory: directory)
                try data.write(to: url)
            } catch {
                Log.monitor(error.localizedDescription)
            }
        }

        static func read(_ id: ID, in directory: FileManager.SearchPathDirectory) -> Data? {
            guard let url = locate(id, in: directory) else {
                Log.debug("Trying to get data for audio file that doesn't exist: \(id)")
                return nil
            }
            let data = try? Data(contentsOf: url)
            return data
        }

        static func locate(_ id: ID, in directory: FileManager.SearchPathDirectory) -> URL? {
            let folderUrls = FileManager.default.urls(for: directory, in: .userDomainMask)
            guard folderUrls.count != 0 else { return nil }

            if let urls = try? FileManager.default.contentsOfDirectory(at: folderUrls[0], includingPropertiesForKeys: nil) {
                for url in urls {
                    if url.absoluteString.contains(id) && url.pathExtension != "" {
                        _ = getUrl(givenId: id, andFileExtension: url.pathExtension, in: directory)
                        return url
                    }
                }
            }
            return nil
        }

        static func getUrl(givenId id: ID, andFileExtension fileExtension: String, in directory: FileManager.SearchPathDirectory) -> URL {
            let url = FileStorage.getUrl(givenAName: getAudioFileName(id, fileExtension: fileExtension), inDirectory: directory)
            return url
        }

        private static func getAudioFileName(_ id: ID, fileExtension: String) -> NameFile {
            return "\(id).\(fileExtension)"
        }
    }
}
