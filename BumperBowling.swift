import BumperBowlingCore

// Bumper Bowling's own architecture, asserted against itself.
// - core is the engine. It depends on nothing of ours and stays typed and boring.
// - cli is a thin interface over core. It forwards; it holds no state.
let bumper = BumperProject {
    Included {
        "Sources"
    }

    Excluded {
        ".build"
        "DerivedData"
    }

    Architecture {
        Component(.core) {
            Owns("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
            Applies(.bumperEngine)
        }

        Component(.tests) {
            Owns("Sources/BumperBowlingTestSupport")
            Modules("BumperBowlingTestSupport")
            MayDependOn(.core)
        }

        Component(.cli) {
            Owns("Sources/BumperBowling")
            Modules("BumperBowling")
            Applies(.thinCommandAdapter)
        }
    }

    Rules {
        ApplyAssertions(.bumperGlobal)
        parsingBoundary
        processConstructionBoundary
        processExecutionBoundary
        immutableEngineState
    }
}
