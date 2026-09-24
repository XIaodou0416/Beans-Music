import Foundation

struct VideoDetailViewModelDependencies {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    let sessionStore: SessionStore
    let sponsorBlockService: SponsorBlockService
}

extension VideoDetailViewModel {
    var api: BiliAPIClient {
        serviceDependencies.api
    }

    var libraryStore: LibraryStore {
        serviceDependencies.libraryStore
    }

    var sessionStore: SessionStore {
        serviceDependencies.sessionStore
    }

    var sponsorBlockService: SponsorBlockService {
        serviceDependencies.sponsorBlockService
    }
}
