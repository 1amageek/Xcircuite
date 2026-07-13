import Foundation
import LayoutAutoGen
import LayoutCore
import LayoutIO
import LayoutTech
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifierTests {
    func producedLayoutCorpusCases() -> [ProducedLayoutCorpusCase] {
        [
            ProducedLayoutCorpusCase(
                id: "gds",
                artifactID: "candidate-layout-gds",
                fileName: "candidate-layout-gds.gds",
                layoutFileFormat: .gds,
                xcircuiteFileFormat: .gdsii,
                pexLayoutFormat: "gds"
            ),
            ProducedLayoutCorpusCase(
                id: "oasis",
                artifactID: "candidate-layout-oasis",
                fileName: "candidate-layout-oasis.oas",
                layoutFileFormat: .oasis,
                xcircuiteFileFormat: .oasis,
                pexLayoutFormat: "oas"
            ),
        ]
    }

    func producedDeviceCorpusCases() -> [ProducedDeviceCorpusCase] {
        [
            producedSingleNMOSDeviceCase(),
            ProducedDeviceCorpusCase(
                id: "pmos",
                deviceKindID: "pmos",
                modelName: "pmos",
                instanceName: "M1",
                parameters: ["w": 2.0, "l": 0.18, "nf": 1],
                netByPin: ["drain": "d", "gate": "g", "source": "s", "bulk": "b"]
            ),
        ]
    }

    func producedSingleNMOSDeviceCase() -> ProducedDeviceCorpusCase {
        ProducedDeviceCorpusCase(
            id: "nmos",
            deviceKindID: "nmos",
            modelName: "nmos",
            instanceName: "M1",
            parameters: ["w": 2.0, "l": 0.18, "nf": 1],
            netByPin: ["drain": "d", "gate": "g", "source": "s", "bulk": "b"]
        )
    }

    func producedLVSCircuitCorpusCases() -> [ProducedCircuitCorpusCase] {
        producedDeviceCorpusCases().map { deviceCase in
            ProducedCircuitCorpusCase(
                id: deviceCase.id,
                schematicNetlist: deviceCase.schematicNetlist,
                layoutKind: .mosDevice(deviceCase)
            )
        } + [
            ProducedCircuitCorpusCase(
                id: "cmos-inverter",
                schematicNetlist: """
                .subckt top in out vdd vss
                M1 out in vdd vdd pmos W=2u L=0.18u
                M2 out in vss vss nmos W=2u L=0.18u
                .ends
                """,
                layoutKind: .cmosInverter
            ),
            ProducedCircuitCorpusCase(
                id: "hierarchical-cmos-inverter",
                schematicNetlist: """
                .subckt top in out vdd vss
                M1 out in vdd vdd pmos W=2u L=0.18u
                M2 out in vss vss nmos W=2u L=0.18u
                .ends
                """,
                layoutKind: .hierarchicalCMOSInverter
            ),
            ProducedCircuitCorpusCase(
                id: "arrayed-parallel-nmos",
                schematicNetlist: """
                .subckt top d g s
                M1 d g s s nmos W=2u L=0.18u M=2
                .ends
                """,
                layoutKind: .arrayedParallelNMOS
            ),
            ProducedCircuitCorpusCase(
                id: "horizontal-arrayed-parallel-nmos",
                schematicNetlist: """
                .subckt top d g s
                M1 d g s s nmos W=2u L=0.18u M=2
                .ends
                """,
                layoutKind: .horizontalArrayedParallelNMOS
            ),
        ]
    }

    func producedSingleNMOSCircuitCase() -> ProducedCircuitCorpusCase {
        let deviceCase = producedSingleNMOSDeviceCase()
        return ProducedCircuitCorpusCase(
            id: deviceCase.id,
            schematicNetlist: deviceCase.schematicNetlist,
            layoutKind: .mosDevice(deviceCase)
        )
    }

    func writeProducedLayoutArtifact(
        root: URL,
        runID: String,
        planID: String,
        stepID: String,
        layoutCase: ProducedLayoutCorpusCase,
        circuitCase: ProducedCircuitCorpusCase
    ) throws -> XcircuiteFileReference {
        let tech = LayoutTechDatabase.sampleProcess()
        let document = try makeProducedLayoutDocument(circuitCase: circuitCase, tech: tech)
        let artifactPath = ".xcircuite/runs/\(runID)/planning/executions/\(planID)/\(stepID)/\(layoutCase.fileName)"
        let artifactURL = root.appending(path: artifactPath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try MaskDataFormatConverter(tech: tech).exportDocument(document, to: artifactURL, format: layoutCase.layoutFileFormat)
        return try XcircuitePackageStore().fileReference(
            forProjectRelativePath: artifactPath,
            artifactID: layoutCase.artifactID,
            kind: .layout,
            format: layoutCase.xcircuiteFileFormat,
            inProjectAt: root,
            producedByRunID: runID
        )
    }

    func makeProducedLayoutDocument(
        circuitCase: ProducedCircuitCorpusCase,
        tech: LayoutTechDatabase
    ) throws -> LayoutDocument {
        switch circuitCase.layoutKind {
        case .mosDevice(let deviceCase):
            return try makeProducedMOSLayoutDocument(deviceCase: deviceCase, tech: tech)
        case .cmosInverter:
            return try makeProducedInverterLayoutDocument(tech: tech)
        case .hierarchicalCMOSInverter:
            return try makeProducedHierarchicalInverterLayoutDocument(tech: tech)
        case .arrayedParallelNMOS:
            return try makeProducedArrayedParallelNMOSLayoutDocument(orientation: .verticalRows, tech: tech)
        case .horizontalArrayedParallelNMOS:
            return try makeProducedArrayedParallelNMOSLayoutDocument(orientation: .horizontalColumns, tech: tech)
        }
    }

    func makeProducedMOSLayoutDocument(
        deviceCase: ProducedDeviceCorpusCase,
        tech: LayoutTechDatabase
    ) throws -> LayoutDocument {
        var cell = try MOSFETCellGenerator().generateCell(
            deviceKindID: deviceCase.deviceKindID,
            instanceName: deviceCase.instanceName,
            parameters: deviceCase.parameters,
            tech: tech
        )
        cell.name = "TOP"
        cell.labels = []
        for pin in cell.pins {
            guard let net = deviceCase.netByPin[pin.name] else {
                continue
            }
            cell.labels.append(LayoutLabel(text: net, position: pin.position, layer: pin.layer))
        }
        return LayoutDocument(name: "TOP", cells: [cell], topCellID: cell.id)
    }

    func makeProducedInverterLayoutDocument(tech: LayoutTechDatabase) throws -> LayoutDocument {
        let nmos = try makeProducedMOSCell(
            deviceKindID: "nmos",
            instanceName: "M2",
            netByPin: ["drain": "out", "gate": "in", "source": "vss", "bulk": "vss"],
            tech: tech
        )
        let pmos = try makeProducedMOSCell(
            deviceKindID: "pmos",
            instanceName: "M1",
            netByPin: ["drain": "out", "gate": "in", "source": "vdd", "bulk": "vdd"],
            tech: tech
        )
        let nmosPlaced = translatedCell(nmos, by: .zero)
        let nmosBox = try boundingBox(of: nmosPlaced)
        let pmosBox = try boundingBox(of: pmos)
        let pmosPlaced = translatedCell(
            pmos,
            by: LayoutPoint(x: 0, y: nmosBox.maxY - pmosBox.minY + 2.0)
        )

        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let m1Width = max(tech.ruleSet(for: m1)?.minWidth ?? 0.2, 0.2)
        let routes = try [
            m1Bridge(
                between: pin("gate", in: nmosPlaced).position,
                and: pin("gate", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("drain", in: nmosPlaced).position,
                and: pin("drain", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("source", in: nmosPlaced).position,
                and: pin("bulk", in: nmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("source", in: pmosPlaced).position,
                and: pin("bulk", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
        ].flatMap { $0 }

        let top = LayoutCell(
            name: "TOP",
            shapes: nmosPlaced.shapes + pmosPlaced.shapes + routes,
            vias: nmosPlaced.vias + pmosPlaced.vias,
            labels: nmosPlaced.labels + pmosPlaced.labels
        )
        return LayoutDocument(name: "TOP", cells: [top], topCellID: top.id)
    }

    func makeProducedHierarchicalInverterLayoutDocument(tech: LayoutTechDatabase) throws -> LayoutDocument {
        var nmos = try makeProducedMOSCell(
            deviceKindID: "nmos",
            instanceName: "M2",
            netByPin: ["drain": "out", "gate": "in", "source": "vss", "bulk": "vss"],
            tech: tech
        )
        nmos.name = "NMOS_DEVICE"
        var pmos = try makeProducedMOSCell(
            deviceKindID: "pmos",
            instanceName: "M1",
            netByPin: ["drain": "out", "gate": "in", "source": "vdd", "bulk": "vdd"],
            tech: tech
        )
        pmos.name = "PMOS_DEVICE"

        let nmosTransform = LayoutTransform()
        let nmosPlaced = translatedCell(nmos, by: nmosTransform.translation)
        let nmosBox = try boundingBox(of: nmosPlaced)
        let pmosBox = try boundingBox(of: pmos)
        let pmosTransform = LayoutTransform(
            translation: LayoutPoint(x: 0, y: nmosBox.maxY - pmosBox.minY + 2.0)
        )
        let pmosPlaced = translatedCell(pmos, by: pmosTransform.translation)

        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let m1Width = max(tech.ruleSet(for: m1)?.minWidth ?? 0.2, 0.2)
        let routes = try [
            m1Bridge(
                between: pin("gate", in: nmosPlaced).position,
                and: pin("gate", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("drain", in: nmosPlaced).position,
                and: pin("drain", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("source", in: nmosPlaced).position,
                and: pin("bulk", in: nmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pin("source", in: pmosPlaced).position,
                and: pin("bulk", in: pmosPlaced).position,
                width: m1Width,
                layer: m1
            ),
        ].flatMap { $0 }

        let top = LayoutCell(
            name: "TOP",
            shapes: routes,
            labels: [
                LayoutLabel(
                    text: "in",
                    position: try pin("gate", in: nmosPlaced).position,
                    layer: try pin("gate", in: nmosPlaced).layer
                ),
                LayoutLabel(
                    text: "out",
                    position: try pin("drain", in: nmosPlaced).position,
                    layer: try pin("drain", in: nmosPlaced).layer
                ),
                LayoutLabel(
                    text: "vss",
                    position: try pin("source", in: nmosPlaced).position,
                    layer: try pin("source", in: nmosPlaced).layer
                ),
                LayoutLabel(
                    text: "vdd",
                    position: try pin("source", in: pmosPlaced).position,
                    layer: try pin("source", in: pmosPlaced).layer
                ),
            ],
            instances: [
                LayoutInstance(cellID: nmos.id, name: "XM2", transform: nmosTransform),
                LayoutInstance(cellID: pmos.id, name: "XM1", transform: pmosTransform),
            ]
        )
        return LayoutDocument(name: "TOP", cells: [top, nmos, pmos], topCellID: top.id)
    }

    func makeProducedArrayedParallelNMOSLayoutDocument(
        orientation: ProducedArrayedNMOSOrientation,
        tech: LayoutTechDatabase
    ) throws -> LayoutDocument {
        var nmos = try makeProducedMOSCell(
            deviceKindID: "nmos",
            instanceName: "MARRAY",
            netByPin: ["drain": "d", "gate": "g", "source": "s", "bulk": "s"],
            tech: tech
        )
        nmos.name = "NMOS_ARRAY_DEVICE"

        let nmosBox = try boundingBox(of: nmos)
        let repetition: LayoutRepetition
        let baseTransform: LayoutTransform
        let secondTransform: LayoutTransform
        switch orientation {
        case .verticalRows:
            let secondOffset = LayoutPoint(x: 0, y: nmosBox.maxY - nmosBox.minY + 2.0)
            baseTransform = LayoutTransform()
            secondTransform = LayoutTransform(translation: secondOffset)
            repetition = LayoutRepetition(
                columns: 1,
                rows: 2,
                columnStep: .zero,
                rowStep: secondOffset
            )
        case .horizontalColumns:
            let rotation = LayoutTransform(rotationDegrees: 90)
            let rotatedBox = try transformedBoundingBox(of: nmos, by: rotation)
            let normalizedTransform = LayoutTransform(
                translation: LayoutPoint(x: -rotatedBox.minX, y: -rotatedBox.minY),
                rotationDegrees: 90
            )
            let normalizedBox = try transformedBoundingBox(of: nmos, by: normalizedTransform)
            let secondOffset = LayoutPoint(x: normalizedBox.maxX - normalizedBox.minX + 2.0, y: 0)
            baseTransform = normalizedTransform
            secondTransform = LayoutTransform(
                translation: normalizedTransform.translation.translated(by: secondOffset),
                rotationDegrees: 90
            )
            repetition = LayoutRepetition(
                columns: 2,
                rows: 1,
                columnStep: secondOffset,
                rowStep: .zero
            )
        }

        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let m2 = LayoutLayerID(name: "M2", purpose: "drawing")
        let m1Width = max(tech.ruleSet(for: m1)?.minWidth ?? 0.2, 0.2)
        let m2Width = max(tech.ruleSet(for: m2)?.minWidth ?? 0.28, 0.28)
        let m2Routes = try [
            m2BridgeWithVias(
                between: pinPosition("drain", in: nmos, transform: baseTransform),
                and: pinPosition("drain", in: nmos, transform: secondTransform),
                width: m2Width,
                layer: m2
            ),
            m2BridgeWithVias(
                between: pinPosition("gate", in: nmos, transform: baseTransform),
                and: pinPosition("gate", in: nmos, transform: secondTransform),
                width: m2Width,
                layer: m2
            ),
            m2BridgeWithVias(
                between: pinPosition("source", in: nmos, transform: baseTransform),
                and: pinPosition("source", in: nmos, transform: secondTransform),
                width: m2Width,
                layer: m2
            ),
        ]
        let sourceBulkRoutes = try [
            m1Bridge(
                between: pinPosition("source", in: nmos, transform: baseTransform),
                and: pinPosition("bulk", in: nmos, transform: baseTransform),
                width: m1Width,
                layer: m1
            ),
            m1Bridge(
                between: pinPosition("source", in: nmos, transform: secondTransform),
                and: pinPosition("bulk", in: nmos, transform: secondTransform),
                width: m1Width,
                layer: m1
            ),
        ].flatMap { $0 }

        let top = LayoutCell(
            name: "TOP",
            shapes: m2Routes.flatMap(\.shapes) + sourceBulkRoutes,
            vias: m2Routes.flatMap(\.vias),
            labels: [
                LayoutLabel(
                    text: "d",
                    position: try pinPosition("drain", in: nmos, transform: baseTransform),
                    layer: m2
                ),
                LayoutLabel(
                    text: "g",
                    position: try pinPosition("gate", in: nmos, transform: baseTransform),
                    layer: m2
                ),
                LayoutLabel(
                    text: "s",
                    position: try pinPosition("source", in: nmos, transform: baseTransform),
                    layer: m2
                ),
            ],
            instances: [
                LayoutInstance(
                    cellID: nmos.id,
                    name: "XMN_ARRAY",
                    transform: baseTransform,
                    repetition: repetition
                ),
            ]
        )
        return LayoutDocument(name: "TOP", cells: [top, nmos], topCellID: top.id)
    }

    func makeProducedMOSCell(
        deviceKindID: String,
        instanceName: String,
        netByPin: [String: String],
        tech: LayoutTechDatabase
    ) throws -> LayoutCell {
        var cell = try MOSFETCellGenerator().generateCell(
            deviceKindID: deviceKindID,
            instanceName: instanceName,
            parameters: ["w": 2.0, "l": 0.18, "nf": 1],
            tech: tech
        )
        cell.labels = []
        for pin in cell.pins {
            guard let net = netByPin[pin.name] else {
                continue
            }
            cell.labels.append(LayoutLabel(text: net, position: pin.position, layer: pin.layer))
        }
        return cell
    }

    func translatedCell(_ cell: LayoutCell, by delta: LayoutPoint) -> LayoutCell {
        var moved = cell
        moved.shapes = moved.shapes.map { shape in
            var movedShape = shape
            movedShape.geometry = shape.geometry.translated(by: delta)
            return movedShape
        }
        moved.vias = moved.vias.map { via in
            var movedVia = via
            movedVia.position = via.position.translated(by: delta)
            return movedVia
        }
        moved.labels = moved.labels.map { label in
            var movedLabel = label
            movedLabel.position = label.position.translated(by: delta)
            return movedLabel
        }
        moved.pins = moved.pins.map { pin in
            var movedPin = pin
            movedPin.position = pin.position.translated(by: delta)
            return movedPin
        }
        return moved
    }

    func boundingBox(of cell: LayoutCell) throws -> LayoutRect {
        guard let first = cell.shapes.first.map({ LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }) else {
            throw ProducedLayoutFixtureError.missingBoundingBox
        }
        return cell.shapes.dropFirst().reduce(first) { partial, shape in
            partial.union(LayoutGeometryAnalysis.boundingBox(for: shape.geometry))
        }
    }

    func pin(_ name: String, in cell: LayoutCell) throws -> LayoutPin {
        guard let pin = cell.pins.first(where: { $0.name == name }) else {
            throw ProducedLayoutFixtureError.missingPin(name)
        }
        return pin
    }

    func pinPosition(
        _ name: String,
        in cell: LayoutCell,
        transform: LayoutTransform
    ) throws -> LayoutPoint {
        try transform.apply(to: pin(name, in: cell).position)
    }

    func transformedBoundingBox(
        of cell: LayoutCell,
        by transform: LayoutTransform
    ) throws -> LayoutRect {
        let box = try boundingBox(of: cell)
        let points = [
            LayoutPoint(x: box.minX, y: box.minY),
            LayoutPoint(x: box.minX, y: box.maxY),
            LayoutPoint(x: box.maxX, y: box.minY),
            LayoutPoint(x: box.maxX, y: box.maxY),
        ].map { transform.apply(to: $0) }
        guard let first = points.first else {
            throw ProducedLayoutFixtureError.missingBoundingBox
        }
        let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
        let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
        let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
        let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
        return LayoutRect(
            origin: LayoutPoint(x: minX, y: minY),
            size: LayoutSize(width: maxX - minX, height: maxY - minY)
        )
    }

    func m1Bridge(
        between start: LayoutPoint,
        and end: LayoutPoint,
        width: Double,
        layer: LayoutLayerID
    ) -> [LayoutShape] {
        let corner = LayoutPoint(x: start.x, y: end.y)
        return [
            m1Segment(from: start, to: corner, width: width, layer: layer),
            m1Segment(from: corner, to: end, width: width, layer: layer),
        ].filter { shape in
            guard case .rect(let rect) = shape.geometry else {
                return true
            }
            return rect.size.width > 0 && rect.size.height > 0
        }
    }

    func m1Segment(
        from start: LayoutPoint,
        to end: LayoutPoint,
        width: Double,
        layer: LayoutLayerID
    ) -> LayoutShape {
        let segment = LayoutRect(
            origin: LayoutPoint(
                x: min(start.x, end.x) - width / 2,
                y: min(start.y, end.y) - width / 2
            ),
            size: LayoutSize(
                width: abs(start.x - end.x) + width,
                height: abs(start.y - end.y) + width
            )
        )
        return LayoutShape(layer: layer, geometry: .rect(segment))
    }

    func m2BridgeWithVias(
        between start: LayoutPoint,
        and end: LayoutPoint,
        width: Double,
        layer: LayoutLayerID
    ) -> (shapes: [LayoutShape], vias: [LayoutVia]) {
        (
            shapes: [m1Segment(from: start, to: end, width: width, layer: layer)],
            vias: [
                LayoutVia(viaDefinitionID: "VIA1", position: start),
                LayoutVia(viaDefinitionID: "VIA1", position: end),
            ]
        )
    }

    func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteCandidatePlanVerifierTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func writeText(_ text: String, path: String, root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeJSON<T: Encodable>(_ value: T, path: String, root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                return try decoder.decode(type, from: data)
            }
    }

    func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
