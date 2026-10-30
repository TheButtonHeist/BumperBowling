import Foundation

struct LintRunEngine: Sendable {
    let root: URL
    let configuration: ArchitectureConfiguration
    let progress: BumperProgressReporter

    init(
        root: URL,
        configuration: ArchitectureConfiguration,
        progress: BumperProgressReporter = .disabled
    ) {
        self.root = root.standardizedFileURL
        self.configuration = configuration
        self.progress = progress
    }

    func run() async throws -> LintRunResult {
        let reducer = LintRunReducer()
        var state = LintRunState.idle
        var event = LintRunEvent.start(configuration)
        let clock = ContinuousClock()
        var phases = LintPhaseTimings()

        while true {
            let transition = reducer.reduce(state: state, event: event)
            state = transition.state
            progress.report(state.progressMessage)

            if case .reporting(let result) = state {
                return result.withPhases(phases)
            }

            guard let effect = transition.effect else {
                throw BumperError.configurationOutputMalformed("lint run reached state without an effect")
            }

            do {
                let effectStart = clock.now
                event = try await perform(effect)
                phases = phases.recording(effect, seconds: (clock.now - effectStart).secondsValue)
            } catch {
                let failure = LintRunFailure(message: String(describing: error))
                let failedTransition = reducer.reduce(state: state, event: .failed(failure))
                progress.report(failedTransition.state.progressMessage)
                throw error
            }
        }
    }

    private func perform(_ effect: LintRunEffect) async throws -> LintRunEvent {
        switch effect {
        case .prepareRules(let configuration):
            return .preparedRules(
                LintPreparedRules(
                    configuration: configuration,
                    rules: try ArchitectureRules(configuration: configuration)
                )
            )

        case .scanSources(let preparedRules):
            let input = try await RepositoryScanner(rules: preparedRules.rules).scanInput(root: root)
            return .scannedSources(preparedRules: preparedRules, files: input.files, coverage: input.coverage)

        case .evaluateRules(let plan):
            let root = root
            let input = RepositoryInput(architecture: plan.configuration, files: plan.files, coverage: plan.coverage)
            let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
            let run: EvaluationRun
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                run = try await Task.detached {
                    try ConfigurationLoader.evaluateRun(root: root, input: input)
                }.value
            } else {
                // No authored BumperBowling.swift means no project rules, so
                // built-in rules evaluate in process without the runner.
                run = try RuleSet(rules: BuiltInRules.rules(from: input.architecture.rules))
                    .evaluationRun(configuration: input.architecture, repository: RepositorySyntax(input: input))
            }
            return .evaluatedRules(plan: plan, run: run)
        }
    }
}

struct LintRunReducer: Sendable {
    func reduce(state: LintRunState, event: LintRunEvent) -> LintRunTransition {
        switch (state, event) {
        case (.idle, .start(let configuration)):
            return LintRunTransition(
                state: .preparingRules(configuration),
                effect: .prepareRules(configuration)
            )

        case (.preparingRules, .preparedRules(let preparedRules)):
            return LintRunTransition(
                state: .scanningSources(preparedRules),
                effect: .scanSources(preparedRules)
            )

        case (.scanningSources, .scannedSources(let preparedRules, let files, let coverage)):
            let plan = LintEvaluationPlan(
                configuration: preparedRules.configuration,
                rules: preparedRules.rules,
                files: files,
                coverage: coverage
            )
            return LintRunTransition(
                state: .evaluatingRules(plan),
                effect: .evaluateRules(plan)
            )

        case (.evaluatingRules, .evaluatedRules(let plan, let run)):
            let result = LintRunResult(
                rules: plan.rules,
                scannedFileCount: plan.files.count,
                report: run.report,
                telemetry: run.telemetry,
                coverage: plan.coverage
            )
            return LintRunTransition(state: .reporting(result), effect: nil)

        case (_, .failed(let failure)):
            return LintRunTransition(state: .failed(failure), effect: nil)

        default:
            let failure = LintRunFailure(message: "invalid transition from \(state) on \(event)")
            return LintRunTransition(state: .failed(failure), effect: nil)
        }
    }
}

enum LintRunState: Sendable {
    case idle
    case preparingRules(ArchitectureConfiguration)
    case scanningSources(LintPreparedRules)
    case evaluatingRules(LintEvaluationPlan)
    case reporting(LintRunResult)
    case failed(LintRunFailure)

    var progressMessage: String {
        switch self {
        case .idle:
            "Starting lint run"
        case .preparingRules:
            "Preparing architecture rules"
        case .scanningSources:
            "Scanning Swift source files"
        case .evaluatingRules(let plan):
            "Evaluating rules over \(plan.files.count) source file(s)"
        case .reporting(let result):
            "Found \(result.report.violations.count) architecture violation(s)"
        case .failed(let failure):
            "Lint run failed: \(failure.message)"
        }
    }
}

enum LintRunEvent: Equatable, Sendable {
    case start(ArchitectureConfiguration)
    case preparedRules(LintPreparedRules)
    case scannedSources(preparedRules: LintPreparedRules, files: [SourceInput], coverage: SourceCoverageSummary? = nil)
    case evaluatedRules(plan: LintEvaluationPlan, run: EvaluationRun)
    case failed(LintRunFailure)
}

enum LintRunEffect: Sendable, Equatable {
    case prepareRules(ArchitectureConfiguration)
    case scanSources(LintPreparedRules)
    case evaluateRules(LintEvaluationPlan)
}

struct LintRunTransition: Sendable {
    let state: LintRunState
    let effect: LintRunEffect?
}

struct LintPreparedRules: Sendable, Equatable {
    let configuration: ArchitectureConfiguration
    let rules: ArchitectureRules
}

struct LintEvaluationPlan: Sendable, Equatable {
    let configuration: ArchitectureConfiguration
    let rules: ArchitectureRules
    let files: [SourceInput]
    let coverage: SourceCoverageSummary?
}

struct LintRunFailure: Error, Sendable, Equatable {
    let message: String
}
