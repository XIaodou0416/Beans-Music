import Foundation

extension VideoDetailViewModel {
    var performanceTestMediaURLs: Set<String> {
        var urls = currentPlayURLData?.playbackMediaURLStrings ?? []
        playVariants.forEach { variant in
            [variant.videoURL, variant.audioURL].compactMap { $0 }.forEach {
                urls.insert($0.absoluteString)
            }
            [variant.videoStream, variant.audioStream].compactMap { $0 }.forEach { stream in
                if URL(string: stream.baseURL) != nil {
                    urls.insert(stream.baseURL)
                }
                stream.backupURL?.forEach {
                    if URL(string: $0) != nil {
                        urls.insert($0)
                    }
                }
            }
        }
        return urls
    }
}
