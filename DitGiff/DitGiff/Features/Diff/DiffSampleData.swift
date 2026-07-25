/// Stand-in for real git and a real agent while the diff screen is a static prototype.
/// Values are lifted from `docs/design-handoff/Dit Giff v2.dc.html`; nothing here is
/// paraphrased, because the copy is what is being reviewed.
nonisolated enum DiffSampleData {
    static let compareBranch = "feature/annual-billing"
    static let baseBranch = "main"

    // The prototype shows a diff of 64 files but ships 31 of them, and counts 47 hunks
    // while showing 8. The list is a sample of a larger diff: the declared totals are
    // what the top bar and the progress claim, and they match the Welcome screen.
    static let declaredFileCount = 64
    static let declaredAdditions = 3242
    static let declaredDeletions = 347
    static let totalHunkCount = 47
    /// Hunks already read outside the sample, so the progress starts where the
    /// prototype starts it.
    static let readHunkBaseline = 16
    /// The prototype's "all-read" scenario, where reading the eight sample hunks
    /// finishes the diff.
    static let allReadHunkBaseline = 39

    /// The two files the prototype opens with already marked as viewed.
    static let defaultViewedPaths: Set<String> = [
        "Sources/HTTP/APIClient.swift",
        "Tests/BillingTests/AnnualBillingTests.swift",
    ]

    /// The viewer's own order — deliberately not the sidebar's.
    static let sectionPaths = [
        "Sources/Billing/BillingGuard.swift",
        "Sources/Billing/PlanResolver.swift",
        "Sources/Billing/InvoiceScheduler.swift",
        "Sources/Billing/ProrationCalculator.swift",
        "Sources/API/SubscriptionHandler.swift",
        "Sources/Models/Subscription.swift",
        "Sources/HTTP/APIClient.swift",
        "Tests/BillingTests/AnnualBillingTests.swift",
    ]

    static let files: [DiffFile] = fileRows.map { row in
        DiffFile(
            path: row.path,
            status: row.status,
            additions: row.additions,
            deletions: row.deletions,
            hunks: row.hunkID.map { [hunk(withID: $0)] } ?? []
        )
    }

    static let sectionFiles: [DiffFile] = sectionPaths.map { path in
        guard let file = files.first(where: { $0.path == path }) else {
            preconditionFailure("Sample data puts \(path) in the viewer but not in the file list.")
        }
        return file
    }

    static func hunk(withID id: String) -> DiffHunk {
        guard let hunk = hunks.first(where: { $0.id == id }) else {
            preconditionFailure("Sample data references hunk \(id), which does not exist.")
        }
        return hunk
    }

    // MARK: - Chat

    static let openingAgentMessage =
        "Ask about any file or hunk in this diff — I keep the whole repository in context."

    /// Where a question with no hunk and no selection is anchored.
    static let threadLocation = "\(compareBranch) → \(baseBranch)"

    /// Every follow-up after the hunk's own canned reply has been spent.
    static let fallbackReply =
        "Noted. I would put that in the MR description — a reviewer will ask either way."

    static let defaultChatModel = DiffChatModelOption.opus5
    static let defaultReasoningEffort = DiffReasoningEffort.high

    static let thinkingIndicator = DiffThinkingIndicator(
        glyphs: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        words: [
            "Thinking",
            "Reading the hunk",
            "Tracing call sites",
            "Weighing the trade-off",
        ]
    )

    /// How long the fake round trip pretends to take.
    static let replyDelayRange = 950...1900

    static func explainSelectionReply(lineCountLabel: String) -> String {
        """
        The \(lineCountLabel) you selected read the plan and force-unwrap the result with \
        try!. If resolvePlan throws — a migrated account or a discontinued plan — this path \
        crashes instead of skipping the invoice. The safe rewrite is a do/catch that logs \
        and returns, which matches the guard-let behavior this replaced.
        """
    }

    static func selectionQuestionReply(location: String, question: String) -> String {
        """
        Looking at \(location) — \(foldedIntoSentence(question)): the short answer is it \
        depends on whether the surrounding call sites already guard for it. Want me to \
        check the callers?
        """
    }

    /// The reader's question is folded into the agent's sentence: first letter lowered,
    /// a trailing question mark dropped.
    private static func foldedIntoSentence(_ question: String) -> String {
        guard let first = question.first else { return question }
        var rest = question.dropFirst()
        if rest.hasSuffix("?") {
            rest = rest.dropLast()
        }
        return first.lowercased() + rest
    }

    // MARK: - Files

    private struct FileRow {
        let path: String
        let status: DiffFileStatus
        let additions: Int
        let deletions: Int
        let hunkID: String?
    }

    private static let fileRows: [FileRow] = [
        FileRow(path: "Sources/API/SubscriptionHandler.swift", status: .modified, additions: 1, deletions: 7, hunkID: "h4"),
        FileRow(path: "Sources/Billing/BillingConfig.swift", status: .modified, additions: 14, deletions: 2, hunkID: nil),
        FileRow(path: "Sources/Billing/BillingGuard.swift", status: .modified, additions: 1, deletions: 1, hunkID: "h1"),
        FileRow(path: "Sources/Billing/InvoiceScheduler.swift", status: .modified, additions: 2, deletions: 2, hunkID: "h3"),
        FileRow(path: "Sources/Billing/PlanResolver.swift", status: .modified, additions: 2, deletions: 2, hunkID: "h2"),
        FileRow(path: "Sources/Billing/ProrationCalculator.swift", status: .modified, additions: 2, deletions: 1, hunkID: "h8"),
        FileRow(path: "Sources/HTTP/APIClient.swift", status: .modified, additions: 2, deletions: 6, hunkID: "h6"),
        FileRow(path: "Sources/HTTP/AuthInterceptor.swift", status: .modified, additions: 19, deletions: 41, hunkID: nil),
        FileRow(path: "Sources/HTTP/AvatarLoader.swift", status: .renamed, additions: 5, deletions: 9, hunkID: nil),
        FileRow(path: "Sources/HTTP/HTTPClientCore.swift", status: .added, additions: 214, deletions: 0, hunkID: nil),
        FileRow(path: "Sources/HTTP/LegacyRequestSigner.swift", status: .deleted, additions: 0, deletions: 118, hunkID: nil),
        FileRow(path: "Sources/HTTP/PaymentGateway.swift", status: .modified, additions: 24, deletions: 31, hunkID: nil),
        FileRow(path: "Sources/HTTP/ReceiptFetcher.swift", status: .modified, additions: 9, deletions: 14, hunkID: nil),
        FileRow(path: "Sources/HTTP/RequestBuilder.swift", status: .modified, additions: 38, deletions: 24, hunkID: nil),
        FileRow(path: "Sources/HTTP/RetryPolicy.swift", status: .added, additions: 52, deletions: 0, hunkID: nil),
        FileRow(path: "Sources/HTTP/SyncService.swift", status: .modified, additions: 31, deletions: 27, hunkID: nil),
        FileRow(path: "Sources/HTTP/WebhookSender.swift", status: .modified, additions: 11, deletions: 16, hunkID: nil),
        FileRow(path: "Sources/Legacy/LegacyImporter.swift", status: .modified, additions: 412, deletions: 412, hunkID: nil),
        FileRow(path: "Sources/Models/Subscription.swift", status: .modified, additions: 3, deletions: 1, hunkID: "h5"),
        FileRow(path: "Package.resolved", status: .modified, additions: 96, deletions: 96, hunkID: nil),
        FileRow(path: "Tests/BillingTests/AnnualBillingTests.swift", status: .added, additions: 9, deletions: 0, hunkID: "h7"),
        FileRow(path: "Tests/BillingTests/APIClientTests.swift", status: .modified, additions: 56, deletions: 34, hunkID: nil),
        FileRow(path: "Tests/BillingTests/BillingGuardTests.swift", status: .modified, additions: 41, deletions: 6, hunkID: nil),
        FileRow(path: "Tests/BillingTests/InvoiceSchedulerTests.swift", status: .modified, additions: 24, deletions: 9, hunkID: nil),
        FileRow(path: "Tests/BillingTests/MigrationSmokeTests.swift", status: .added, additions: 22, deletions: 0, hunkID: nil),
        FileRow(path: "Tests/BillingTests/PlanResolverTests.swift", status: .modified, additions: 38, deletions: 12, hunkID: nil),
        FileRow(path: "Tests/BillingTests/ProrationTests.swift", status: .added, additions: 27, deletions: 0, hunkID: nil),
        FileRow(path: "Tests/BillingTests/RetryPolicyTests.swift", status: .added, additions: 48, deletions: 0, hunkID: nil),
        FileRow(path: "Tests/BillingTests/SubscriptionHandlerTests.swift", status: .modified, additions: 19, deletions: 22, hunkID: nil),
        FileRow(path: "Tests/__Snapshots__/InvoiceView@2x.png", status: .modified, additions: 0, deletions: 0, hunkID: nil),
        FileRow(path: "Tests/__Snapshots__/PlanPicker@2x.png", status: .modified, additions: 0, deletions: 0, hunkID: nil),
    ]

    // MARK: - Hunks

    private static func plain(_ text: String) -> DiffLineSegment {
        DiffLineSegment(text: text)
    }

    private static func marked(_ text: String) -> DiffLineSegment {
        DiffLineSegment(text: text, isHighlighted: true)
    }

    private static func line(
        _ oldNumber: Int?,
        _ newNumber: Int?,
        _ kind: DiffLineKind,
        _ text: String
    ) -> DiffLine {
        DiffLine(oldNumber: oldNumber, newNumber: newNumber, kind: kind, segments: [plain(text)])
    }

    private static func line(
        _ oldNumber: Int?,
        _ newNumber: Int?,
        _ kind: DiffLineKind,
        _ segments: [DiffLineSegment]
    ) -> DiffLine {
        DiffLine(oldNumber: oldNumber, newNumber: newNumber, kind: kind, segments: segments)
    }

    static let hunks: [DiffHunk] = [
        DiffHunk(
            id: "h1",
            filePath: "Sources/Billing/BillingGuard.swift",
            header: "@@ \(DiffFormat.minusSign)139,6 +139,6 @@ func canCharge(_:)",
            location: "BillingGuard.swift:142",
            note: """
            The billing check in BillingGuard.swift:142 changed from >= to >. Accounts \
            exactly at their plan limit now fall on the other side of the guard. Was that \
            intentional?
            """,
            explanation: """
            The limit itself stopped counting as overage: used >= limit used to take the \
            overage path, now only used > limit does. The new test in AnnualBillingTests \
            pins at-limit accounts as chargeable — if that was not the intent, the test is \
            wrong too.
            """,
            reply: """
            Two things worth checking before the MR: whether allowsOverage was ever meant \
            to apply to at-limit accounts, and whether any pricing copy promises usage \
            “up to” the limit. The new test pins at-limit as chargeable — if that is wrong, \
            the test needs to change too.
            """,
            lines: [
                line(139, 139, .context, "func canCharge(_ account: Account) -> Bool {"),
                line(140, 140, .context, "    let limit = account.plan.chargeLimit(for: period)"),
                line(141, 141, .context, "    let used = account.usage.total(in: period)"),
                line(142, nil, .deletion, [
                    plain("    guard used "),
                    marked(">="),
                    plain(" limit else { return true }"),
                ]),
                line(nil, 142, .addition, [
                    plain("    guard used "),
                    marked(">"),
                    plain(" limit else { return true }"),
                ]),
                line(143, 143, .context, "    return account.plan.allowsOverage"),
                line(144, 144, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h2",
            filePath: "Sources/Billing/PlanResolver.swift",
            header: "@@ \(DiffFormat.minusSign)55,7 +55,7 @@ enum PlanCatalog",
            location: "PlanResolver.swift:56",
            note: """
            resolvePlan() used to return nil when the plan was not found; it now throws. \
            Three call sites in this diff handle the return — none of them catch the \
            exception.
            """,
            explanation: """
            resolvePlan moved from an optional return to a typed throw. Call sites that \
            used guard let need do/catch now — in this diff, callers use try! or try \
            without a catch.
            """,
            reply: """
            The three call sites are InvoiceScheduler, SubscriptionHandler and \
            WebhookSender. None of them adds a catch in this diff — InvoiceScheduler even \
            uses try!. If notFound is reachable in production data, that is the first place \
            it surfaces.
            """,
            lines: [
                line(55, 55, .context, "// Resolve a plan from the local catalog"),
                line(56, nil, .deletion, [
                    plain("func resolvePlan(_ id: PlanID) "),
                    marked("-> Plan?"),
                    plain(" {"),
                ]),
                line(nil, 56, .addition, [
                    plain("func resolvePlan(_ id: PlanID) "),
                    marked("throws -> Plan"),
                    plain(" {"),
                ]),
                line(57, 57, .context, "    if let plan = catalog.plan(for: id) {"),
                line(58, 58, .context, "        return plan"),
                line(59, 59, .context, "    }"),
                line(60, nil, .deletion, "    return nil"),
                line(nil, 60, .addition, "    throw PlanError.notFound(id)"),
                line(61, 61, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h3",
            filePath: "Sources/Billing/InvoiceScheduler.swift",
            header: "@@ \(DiffFormat.minusSign)201,7 +201,7 @@ func schedule(for:)",
            location: "InvoiceScheduler.swift:202",
            note: nil,
            explanation: """
            The scheduler force-unwraps with try!. If the plan is missing from the catalog \
            (migrated account, discontinued plan), this crashes the process instead of \
            skipping the invoice like it used to.
            """,
            reply: """
            try! is safe only if every planID in the store is guaranteed to resolve. \
            Migration or plan sunsetting breaks that guarantee — a plain do/catch with a \
            skip keeps the old behavior.
            """,
            lines: [
                line(201, 201, .context, "func schedule(for account: Account) {"),
                line(202, nil, .deletion, "    guard let plan = resolvePlan(account.planID) else { return }"),
                line(nil, 202, .addition, [
                    plain("    let plan = "),
                    marked("try!"),
                    plain(" resolvePlan(account.planID)"),
                ]),
                line(203, 203, .context, "    let months = plan.billingCycle == .annual ? 12 : 1"),
                line(204, nil, .deletion, "    let amount = plan.price"),
                line(nil, 204, .addition, "    let amount = prorate(plan.price, months: months)"),
                line(205, 205, .context, "    enqueue(Invoice(account: account, amount: amount))"),
                line(206, 206, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h8",
            filePath: "Sources/Billing/ProrationCalculator.swift",
            header: "@@ \(DiffFormat.minusSign)8,4 +8,5 @@ func prorate(_:months:)",
            location: "ProrationCalculator.swift:9",
            note: nil,
            explanation: """
            prorate now guards against months <= 0 and multiplies before dividing, avoiding \
            rounding twice with Decimal.
            """,
            reply: """
            The old code divided first, so annual prices under 12 currency units rounded to \
            zero per month. Multiplying first fixes that; the months guard covers a \
            zero-month edge that should not happen but now cannot.
            """,
            lines: [
                line(8, 8, .context, "func prorate(_ price: Decimal, months: Int) -> Decimal {"),
                line(9, nil, .deletion, "    return price / 12"),
                line(nil, 9, .addition, "    guard months > 0 else { return price }"),
                line(nil, 10, .addition, "    return (price * Decimal(months)) / 12"),
                line(10, 11, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h4",
            filePath: "Sources/API/SubscriptionHandler.swift",
            header: "@@ \(DiffFormat.minusSign)87,11 +87,5 @@ func update(_:)",
            location: "SubscriptionHandler.swift:88",
            note: """
            Why did validation move from the handler to the model? A reviewer will ask \
            whether this changes the order of errors returned by the API.
            """,
            explanation: """
            Validation left the handler. The endpoint now relies on Subscription.apply \
            throwing the same errors — but the order changed: store.subscription runs \
            before validation, so an unknown id returns 404 where it used to return 422.
            """,
            reply: """
            If API clients depend on the 422-before-404 order, this is a behavior change. \
            Easiest defense in the MR: state it explicitly and point at the model-level \
            tests covering both errors.
            """,
            lines: [
                line(87, 87, .context, "func update(_ req: UpdateRequest) throws -> Response {"),
                line(88, nil, .deletion, "    guard req.plan.isValid else {"),
                line(89, nil, .deletion, "        throw ValidationError.invalidPlan"),
                line(90, nil, .deletion, "    }"),
                line(91, nil, .deletion, "    guard req.seats > 0 else {"),
                line(92, nil, .deletion, "        throw ValidationError.noSeats"),
                line(93, nil, .deletion, "    }"),
                line(94, 88, .context, "    let sub = try store.subscription(req.id)"),
                line(95, nil, .deletion, "    sub.apply(req)"),
                line(nil, 89, .addition, [
                    plain("    "),
                    marked("try"),
                    plain(" sub.apply(req)"),
                ]),
                line(96, 90, .context, "    return .ok(sub)"),
                line(97, 91, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h5",
            filePath: "Sources/Models/Subscription.swift",
            header: "@@ \(DiffFormat.minusSign)40,5 +40,8 @@ struct Subscription",
            location: "Subscription.swift:42",
            note: nil,
            explanation: """
            The guards were recreated inside the model, which covers call sites beyond the \
            handler. The new throws propagates to every apply call site.
            """,
            reply: """
            Moving guards into apply means every future caller gets them for free. The cost \
            is that ValidationError now escapes from a model type — check no caller matches \
            on the error origin.
            """,
            lines: [
                line(40, 40, .context, "    var plan: Plan"),
                line(41, nil, .deletion, "    mutating func apply(_ req: UpdateRequest) {"),
                line(nil, 41, .addition, [
                    plain("    mutating func apply(_ req: UpdateRequest) "),
                    marked("throws"),
                    plain(" {"),
                ]),
                line(nil, 42, .addition, "        guard req.plan.isValid else { throw ValidationError.invalidPlan }"),
                line(nil, 43, .addition, "        guard req.seats > 0 else { throw ValidationError.noSeats }"),
                line(42, 44, .context, "        self.plan = req.plan"),
                line(43, 45, .context, "        self.seats = req.seats"),
                line(44, 46, .context, "    }"),
            ]
        ),
        DiffHunk(
            id: "h6",
            filePath: "Sources/HTTP/APIClient.swift",
            header: "@@ \(DiffFormat.minusSign)12,9 +12,5 @@ final class APIClient",
            location: "APIClient.swift:12",
            note: nil,
            explanation: """
            A direct swap of URLSession for the new HTTPClient: the callback becomes \
            async/await and the response body is read from .body. Network-error handling \
            now comes from the client, not the dataTask.
            """,
            reply: """
            The new client owns retries and error mapping, so this file loses its \
            continuation boilerplate. The behavior question is timeouts: URLSession default \
            was 60s — confirm HTTPClient .default matches what production expects.
            """,
            lines: [
                line(12, nil, .deletion, "private let session = URLSession.shared"),
                line(nil, 12, .addition, "private let client = HTTPClient(configuration: .default)"),
                line(13, 13, .context, ""),
                line(14, 14, .context, "func fetch(_ request: APIRequest) async throws -> Data {"),
                line(15, nil, .deletion, "    await withCheckedContinuation { cont in"),
                line(16, nil, .deletion, "        session.dataTask(with: request.urlRequest) { data, _, _ in"),
                line(17, nil, .deletion, "            cont.resume(returning: data ?? Data())"),
                line(18, nil, .deletion, "        }.resume()"),
                line(19, nil, .deletion, "    }"),
                line(nil, 15, .addition, "    try await client.send(request).body"),
                line(20, 16, .context, "}"),
            ]
        ),
        DiffHunk(
            id: "h7",
            filePath: "Tests/BillingTests/AnnualBillingTests.swift",
            header: "@@ \(DiffFormat.minusSign)0,0 +1,9 @@",
            location: "AnnualBillingTests.swift:6",
            note: nil,
            explanation: """
            A regression test that pins the exact-limit decision: an account .atLimit must \
            stay chargeable. It is the anchor for answering “was that intentional?” in \
            review.
            """,
            reply: """
            This test is the answer to the >= note: it documents at-limit-still-charges as \
            a decision, not an accident. Reference it in the MR description.
            """,
            lines: [
                line(nil, 1, .addition, "import XCTest"),
                line(nil, 2, .addition, "@testable import Billing"),
                line(nil, 3, .addition, ""),
                line(nil, 4, .addition, "final class AnnualBillingTests: XCTestCase {"),
                line(nil, 5, .addition, "    func testAccountAtExactLimitStillCharges() {"),
                line(nil, 6, .addition, "        let account = Account.fixture(plan: .annual, usage: .atLimit)"),
                line(nil, 7, .addition, "        XCTAssertTrue(BillingGuard().canCharge(account))"),
                line(nil, 8, .addition, "    }"),
                line(nil, 9, .addition, "}"),
            ]
        ),
    ]
}
