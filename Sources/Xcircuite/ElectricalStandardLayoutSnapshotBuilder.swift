import Foundation
import LayoutCore
import LayoutTech
import PhysicalDesignCore

public struct ElectricalStandardLayoutSnapshotBuilder: Sendable {
    private struct NetContext: Sendable {
        var nameByID: [UUID: String]
        var idByName: [String: UUID]
    }

    public init() {}

    public func build(
        document: LayoutDocument,
        technology: LayoutTechDatabase,
        topCellName: String? = nil,
        sourceFormat: String,
        connectivityDocument: LayoutDocument? = nil,
        connectivitySourceFormat: String? = nil
    ) throws -> PhysicalDesignSnapshot {
        let geometryCell = try resolveTopCell(document, requestedName: topCellName)
        let electricalCell = try resolveTopCell(
            connectivityDocument ?? document,
            requestedName: topCellName
        )
        guard geometryCell.name == electricalCell.name else {
            throw ElectricalStandardLayoutImportError.malformedGeometry(
                "geometry top cell \(geometryCell.name) does not match connectivity top cell \(electricalCell.name)"
            )
        }

        let dbuPerMicron = document.units.dbuPerMicron
        guard dbuPerMicron.isFinite, dbuPerMicron > 0 else {
            throw ElectricalStandardLayoutImportError.malformedGeometry("DBU per micron must be positive")
        }
        let unitsPerMicron = max(1, Int(dbuPerMicron.rounded()))
        let netContext = makeNetContext(electricalCell)
        let pins = makePins(topCell: electricalCell, netContext: netContext, scale: dbuPerMicron)
        let nets = makeNets(topCell: electricalCell, pins: pins, netContext: netContext)
        let routes = try makeRoutes(
            topCell: electricalCell,
            netContext: netContext,
            technology: technology,
            scale: dbuPerMicron
        )
        let vias = makeVias(
            topCell: electricalCell,
            netContext: netContext,
            technology: technology,
            scale: dbuPerMicron
        )
        guard !nets.isEmpty, !routes.isEmpty else {
            throw ElectricalStandardLayoutImportError.missingElectricalConnectivity
        }

        let cells = makeCells(document: document, topCell: geometryCell, scale: dbuPerMicron)
        let bounds = boundingBox(
            geometryCell: geometryCell,
            electricalCell: electricalCell,
            scale: dbuPerMicron
        )
        let powerStructures = makePowerStructures(
            topCell: electricalCell,
            netContext: netContext,
            technology: technology,
            scale: dbuPerMicron
        )
        return PhysicalDesignSnapshot(
            topCell: geometryCell.name,
            unitsPerMicron: unitsPerMicron,
            die: bounds,
            core: bounds,
            cells: cells,
            pins: pins,
            nets: nets,
            powerStructures: powerStructures,
            routes: routes,
            vias: vias,
            metadata: [
                "sourceFormat": sourceFormat,
                "sourceTopCell": geometryCell.name,
                "sourceUnitsPerMicron": String(unitsPerMicron),
                "standardFormatSemantics": "layout-geometry-and-routed-connectivity",
                "connectivitySourceFormat": connectivitySourceFormat ?? sourceFormat,
            ]
        )
    }

    private func resolveTopCell(
        _ document: LayoutDocument,
        requestedName: String?
    ) throws -> LayoutCell {
        if let requestedName,
           let namedCell = document.cells.first(where: { $0.name == requestedName }) {
            return namedCell
        }
        if let topCellID = document.topCellID,
           let identifiedCell = document.cell(withID: topCellID) {
            return identifiedCell
        }
        if let firstCell = document.cells.first {
            return firstCell
        }
        throw ElectricalStandardLayoutImportError.invalidTopCell
    }

    private func makeNetContext(_ topCell: LayoutCell) -> NetContext {
        let nameByID = Dictionary(uniqueKeysWithValues: topCell.nets.map { ($0.id, $0.name) })
        let idByName = Dictionary(uniqueKeysWithValues: topCell.nets.map { ($0.name, $0.id) })
        return NetContext(nameByID: nameByID, idByName: idByName)
    }

    private func makePins(
        topCell: LayoutCell,
        netContext: NetContext,
        scale: Double
    ) -> [PhysicalDesignSnapshot.Pin] {
        topCell.pins.map { pin in
            PhysicalDesignSnapshot.Pin(
                id: pin.id.uuidString,
                name: pin.name,
                x: coordinate(pin.position.x, scale: scale),
                y: coordinate(pin.position.y, scale: scale),
                netID: pin.netID.flatMap { netContext.nameByID[$0] },
                direction: direction(for: pin.role)
            )
        }.sorted { $0.id < $1.id }
    }

    private func makeNets(
        topCell: LayoutCell,
        pins: [PhysicalDesignSnapshot.Pin],
        netContext: NetContext
    ) -> [PhysicalDesignSnapshot.Net] {
        let pinIDByName = Dictionary(grouping: pins, by: { $0.name })
        return topCell.nets.map { net in
            let pinIDs = topCell.pins
                .filter { $0.netID == net.id }
                .map { $0.id.uuidString }
                + (netContext.nameByID[net.id].flatMap { pinIDByName[$0] } ?? []).map(\.id)
            return PhysicalDesignSnapshot.Net(
                id: net.name,
                pinIDs: Array(Set(pinIDs)).sorted()
            )
        }.sorted { $0.id < $1.id }
    }

    private func makeRoutes(
        topCell: LayoutCell,
        netContext: NetContext,
        technology: LayoutTechDatabase,
        scale: Double
    ) throws -> [PhysicalDesignSnapshot.Route] {
        var routes: [PhysicalDesignSnapshot.Route] = []
        for shape in topCell.shapes {
            guard let netID = resolvedNetName(shape: shape, netContext: netContext),
                  let layer = technology.layerDefinition(for: shape.layer)?.gdsLayer else {
                continue
            }
            let segments = routeSegments(
                shape: shape,
                layer: layer,
                scale: scale
            )
            guard !segments.isEmpty else {
                throw ElectricalStandardLayoutImportError.malformedGeometry(
                    "routed shape \(shape.id.uuidString) has no valid segment"
                )
            }
            routes.append(PhysicalDesignSnapshot.Route(
                id: shape.id.uuidString,
                netID: netID,
                segments: segments
            ))
        }
        return routes.sorted { $0.id < $1.id }
    }

    private func routeSegments(
        shape: LayoutShape,
        layer: Int,
        scale: Double
    ) -> [PhysicalDesignSnapshot.RouteSegment] {
        let points: [LayoutPoint]
        switch shape.geometry {
        case let .path(path):
            points = path.points
        case let .rect(rect):
            let center = rect.center
            if rect.size.width >= rect.size.height {
                points = [LayoutPoint(x: rect.minX, y: center.y), LayoutPoint(x: rect.maxX, y: center.y)]
            } else {
                points = [LayoutPoint(x: center.x, y: rect.minY), LayoutPoint(x: center.x, y: rect.maxY)]
            }
        case let .polygon(polygon):
            points = polygon.points + (polygon.points.first.map { [$0] } ?? [])
        }
        guard points.count >= 2 else { return [] }
        return points.dropLast().enumerated().compactMap { index, point in
            let end = points[index + 1]
            guard point.x != end.x || point.y != end.y else { return nil }
            return PhysicalDesignSnapshot.RouteSegment(
                id: "\(shape.id.uuidString)-\(index)",
                layer: layer,
                x1: coordinate(point.x, scale: scale),
                y1: coordinate(point.y, scale: scale),
                x2: coordinate(end.x, scale: scale),
                y2: coordinate(end.y, scale: scale)
            )
        }
    }

    private func makeVias(
        topCell: LayoutCell,
        netContext: NetContext,
        technology: LayoutTechDatabase,
        scale: Double
    ) -> [PhysicalDesignSnapshot.Via] {
        topCell.vias.compactMap { via in
            guard let netID = via.netID.flatMap({ netContext.nameByID[$0] }),
                  let definition = technology.viaDefinition(for: via.viaDefinitionID),
                  let lowerLayer = technology.layerDefinition(for: definition.bottomLayer)?.gdsLayer,
                  let upperLayer = technology.layerDefinition(for: definition.topLayer)?.gdsLayer else {
                return nil
            }
            return PhysicalDesignSnapshot.Via(
                id: via.id.uuidString,
                netID: netID,
                x: coordinate(via.position.x, scale: scale),
                y: coordinate(via.position.y, scale: scale),
                lowerLayer: lowerLayer,
                upperLayer: upperLayer
            )
        }.sorted { $0.id < $1.id }
    }

    private func makeCells(
        document: LayoutDocument,
        topCell: LayoutCell,
        scale: Double
    ) -> [PhysicalDesignSnapshot.Cell] {
        topCell.instances.flatMap { instance -> [PhysicalDesignSnapshot.Cell] in
            guard let master = document.cell(withID: instance.cellID) else { return [] }
            let masterBounds = bounds(of: master)
            return instance.occurrenceTransforms().enumerated().map { index, transform in
                let identifier = instance.occurrenceTransforms().count == 1
                    ? instance.name
                    : "\(instance.name)#\(index)"
                return PhysicalDesignSnapshot.Cell(
                    id: identifier,
                    master: master.name,
                    x: coordinate(transform.translation.x + masterBounds.minX, scale: scale),
                    y: coordinate(transform.translation.y + masterBounds.minY, scale: scale),
                    width: coordinate(masterBounds.size.width * transform.magnification, scale: scale),
                    height: coordinate(masterBounds.size.height * transform.magnification, scale: scale),
                    placed: true
                )
            }
        }.sorted { $0.id < $1.id }
    }

    private func makePowerStructures(
        topCell: LayoutCell,
        netContext: NetContext,
        technology: LayoutTechDatabase,
        scale: Double
    ) -> [PhysicalDesignSnapshot.PowerStructure] {
        topCell.shapes.compactMap { shape in
            guard let netID = resolvedNetName(shape: shape, netContext: netContext),
                  isPowerNet(netID),
                  let layer = technology.layerDefinition(for: shape.layer)?.gdsLayer else {
                return nil
            }
            let box = LayoutGeometryAnalysis.boundingBox(for: shape.geometry)
            return PhysicalDesignSnapshot.PowerStructure(
                id: shape.id.uuidString,
                netID: netID,
                kind: isGroundNet(netID) ? "ground-structure" : "power-structure",
                layer: layer,
                geometry: PhysicalDesignSnapshot.Rect(
                    x: coordinate(box.minX, scale: scale),
                    y: coordinate(box.minY, scale: scale),
                    width: coordinate(box.size.width, scale: scale),
                    height: coordinate(box.size.height, scale: scale)
                )
            )
        }.sorted { $0.id < $1.id }
    }

    private func boundingBox(
        geometryCell: LayoutCell,
        electricalCell: LayoutCell,
        scale: Double
    ) -> PhysicalDesignSnapshot.Rect? {
        let boxes = geometryCell.shapes.map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
            + geometryCell.pins.map {
                LayoutRect(origin: $0.position, size: $0.size)
            }
            + electricalCell.shapes.map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
        guard let first = boxes.first else { return nil }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        return PhysicalDesignSnapshot.Rect(
            x: coordinate(union.minX, scale: scale),
            y: coordinate(union.minY, scale: scale),
            width: coordinate(union.size.width, scale: scale),
            height: coordinate(union.size.height, scale: scale)
        )
    }

    private func bounds(of cell: LayoutCell) -> LayoutRect {
        let boxes = cell.shapes.map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
            + cell.pins.map { LayoutRect(origin: $0.position, size: $0.size) }
        guard let first = boxes.first else {
            return LayoutRect(origin: .zero, size: LayoutSize(width: 1, height: 1))
        }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    private func resolvedNetName(shape: LayoutShape, netContext: NetContext) -> String? {
        if let netID = shape.netID {
            return netContext.nameByID[netID]
        }
        if let routeName = shape.properties["def.route.netName"] {
            return netContext.idByName[routeName].flatMap { netContext.nameByID[$0] }
        }
        return nil
    }

    private func coordinate(_ value: Double, scale: Double) -> Int64 {
        Int64((value * scale).rounded())
    }

    private func direction(for role: LayoutPinRole) -> String {
        switch role {
        case .gate, .source, .drain, .bulk, .power, .ground, .signal:
            return "input"
        }
    }

    private func isGroundNet(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.contains("gnd") || value.contains("vss") || value.contains("ground")
    }

    private func isPowerNet(_ name: String) -> Bool {
        let value = name.lowercased()
        return isGroundNet(name) || value.contains("vdd") || value.contains("vcc") || value.contains("power")
    }
}
