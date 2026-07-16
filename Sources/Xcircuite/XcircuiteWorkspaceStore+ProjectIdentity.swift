import DesignFlowKernel

extension XcircuiteWorkspaceStore {
    /// Updates the canonical top-design identity while preserving the project identifier and display name.
    public func updateTopDesignName(_ topDesignName: String) throws {
        var manifest = try loadManifest()
        manifest.identity = FlowProjectIdentity(
            projectID: manifest.identity.projectID,
            displayName: manifest.identity.displayName,
            topDesignName: topDesignName
        )
        try saveManifest(manifest)
    }
}
