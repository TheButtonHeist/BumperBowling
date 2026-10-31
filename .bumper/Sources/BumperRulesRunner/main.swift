import BumperBowlingCore
import BumperRules

BumperProject(excluded: ["Sources/BumperBowlingCore/Starter"]) {
    ParsingBoundaryRule.self
    ProcessConstructionRule.self
    ProcessExecutionRule.self
    ImmutableEngineStateRule.self
}.main()
