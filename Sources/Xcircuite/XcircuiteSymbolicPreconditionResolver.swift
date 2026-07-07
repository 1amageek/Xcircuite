struct XcircuiteSymbolicPreconditionResolver: Sendable {
    func activePreconditions(
        for operation: XcircuiteActionDomainOperation,
        boundInputRefs: [String],
        symbolicState: [String]
    ) -> [String] {
        operation.preconditions.filter {
            isActive(precondition: $0, boundInputRefs: boundInputRefs, symbolicState: symbolicState)
        }
    }

    private func isActive(
        precondition: String,
        boundInputRefs: [String],
        symbolicState: [String]
    ) -> Bool {
        if precondition == "net-ref-exists-when-present" {
            return boundInputRefs.contains("optional-net-ref")
                || symbolicState.contains("ref:optional-net-ref")
                || symbolicState.contains(precondition)
        }
        if precondition.hasPrefix("optional-") {
            return symbolicState.contains(precondition)
        }
        return true
    }
}
