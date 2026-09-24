import SwiftUI

struct UploaderIdentityRow: View {
    let owner: VideoOwner
    let card: UploaderCard?
    @ObservedObject var viewModel: UploaderViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AvatarRemoteImage(urlString: card?.face ?? owner.face, pixelSize: 160) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(card?.name ?? owner.name)
                    .font(.title3.weight(.bold))

                UploaderFollowButton(owner: owner, viewModel: viewModel)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
    }
}
