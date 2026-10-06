import SwiftUI

struct PrivacyPolicyView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("개인정보 처리방침")
                    .font(.title2.bold())

                ForEach(sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.text(sections[index].title))
                            .font(.headline)
                        Text(AppLocalization.text(sections[index].body))
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .textSelection(.enabled)
        }
        .background(AppTheme.background)
        .navigationTitle("개인정보")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    private let sections: [(title: String, body: String)] = [
        ("기기에 저장되는 정보",
         "Kava는 읽기 기능을 제공하기 위해 서버 주소, 입력한 계정 정보와 API Key, 앱 설정, 읽기 기록, 즐겨찾기, 작품 정보와 캐시를 기기에 저장합니다. 직접 가져온 파일은 앱 내부에 복사해 오프라인 읽기에 사용합니다. 인증 토큰은 기기의 Keychain에 저장합니다."),
        ("Kavita 서버 연결",
         "서버를 연결하면 인증 정보와 작품 조회, 읽기 진행률, 즐겨찾기 등의 요청을 사용자가 지정한 Kavita 서버로 직접 전송합니다. 서버에 저장되는 정보의 처리와 보관은 해당 서버 운영자의 정책을 따릅니다."),
        ("외부 작품 정보",
         "자동 작품 정보 보완 또는 직접 AniList 연결을 사용할 때 작품 제목이나 AniList 작품 ID를 AniList에 전송하고 작품 정보와 표지 이미지를 받아옵니다. 네트워크 요청 과정에서 해당 서비스에 IP 주소 등의 접속 정보가 전달될 수 있습니다. 가져온 파일의 본문이나 Kavita 인증 정보를 AniList로 전송하지 않습니다."),
        ("다른 언어 제목으로 재검색", "다른 언어 제목으로 재검색을 켜면 작품 제목을 위키백과에도 전송하여 연결된 영어 제목을 확인합니다."),
        ("정보의 사용 목적",
         "저장된 정보는 서버 인증, 라이브러리 표시, 작품 정보 보완, 읽기 위치 복원과 앱 설정 유지에 사용합니다. Kava는 별도의 개발자 서버로 읽기 기록이나 가져온 파일을 전송하지 않으며, 광고 또는 사용 분석 SDK를 포함하지 않습니다."),
        ("고객지원 문의",
         "고객지원에서 입력한 이메일과 문의 내용은 사용자가 메일 작성창에서 전송할 때 kavareader@gmail.com으로 전달됩니다. 문의 정보는 답변과 문제 해결을 위해 사용합니다. 메일 전송에는 사용자가 선택한 메일 서비스와 수신자의 Gmail 서비스가 사용됩니다. 개인정보 관련 문의와 문의 정보 삭제 요청도 이 주소로 보낼 수 있습니다."),
        ("정보 보관 및 삭제",
         "기기에 저장한 정보는 앱 기능을 위해 보관합니다. 가져온 파일은 작품의 파일 관리에서 삭제할 수 있고, 커버 캐시는 설정의 캐시 설정에서 삭제할 수 있습니다. 서버 설정에서 저장된 연결 정보를 수정할 수 있습니다. 기기의 데이터를 삭제해도 Kavita 서버에 저장된 기록은 삭제되지 않으므로 서버의 정보 삭제는 서버 운영자에게 요청해야 합니다."),
        ("외부 서비스 및 백업",
         "Kavita 서버와 AniList 등 외부 서비스에는 각 서비스의 개인정보 처리방침이 적용됩니다. 기기 백업을 사용하는 경우 앱의 로컬 데이터가 운영체제의 백업 설정에 따라 백업에 포함될 수 있습니다."),
    ]
}
