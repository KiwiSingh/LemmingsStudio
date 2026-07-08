import Foundation

extension VisionStudioModel {
    var spatialObjects: [VisionSpatialObject] {
        get {
            ensureSpatialScene()
            return project.spatialScene?.objects ?? []
        }
        set {
            ensureSpatialScene()
            project.spatialScene?.objects = newValue
        }
    }

    func ensureSpatialScene() {
        if project.spatialScene == nil { project.spatialScene = .default }
        if spatialSelectedObjectID == nil { spatialSelectedObjectID = project.spatialScene?.objects.first?.id }
    }

    var selectedSpatialObject: VisionSpatialObject? {
        ensureSpatialScene()
        return project.spatialScene?.objects.first(where: { $0.id == spatialSelectedObjectID })
    }

    func selectSpatialObject(_ id: UUID) {
        spatialSelectedObjectID = id
        if let object = selectedSpatialObject { statusMessage = "Selected spatial surface: \(object.name)" }
    }

    func updateSelectedSpatialTransform(_ transform: VisionSpatialTransform, label: String = "Spatial edit") {
        ensureSpatialScene()
        guard let id = spatialSelectedObjectID,
              let index = project.spatialScene?.objects.firstIndex(where: { $0.id == id }),
              project.spatialScene?.objects[index].isLocked != true else { return }
        let before = project.spatialScene?.objects[index].transform ?? .identity
        project.spatialScene?.objects[index].transform = transform
        spatialUndoStack.append(.init(objectID: id, before: before, after: transform, label: label))
        spatialRedoStack.removeAll()
        recordSpatialTransformAutomation(objectID: id, transform: transform)
        statusMessage = label
    }

    func nudgeSelectedSpatialObject(dx: Double = 0, dy: Double = 0, dz: Double = 0) {
        guard var object = selectedSpatialObject else { return }
        object.transform.position.x += dx
        object.transform.position.y += dy
        object.transform.position.z += dz
        updateSelectedSpatialTransform(object.transform, label: "Nudged \(object.name)")
    }

    func snapSelectedSpatialObject() {
        ensureSpatialScene()
        guard var object = selectedSpatialObject, let scene = project.spatialScene else { return }
        object.transform.quantize(positionStep: scene.snapPositionStep, rotationStep: scene.snapRotationStep, scaleStep: scene.snapScaleStep)
        updateSelectedSpatialTransform(object.transform, label: "Snapped \(object.name)")
    }

    func resetSelectedSpatialObject() {
        guard var object = selectedSpatialObject else { return }
        object.transform = .identity
        updateSelectedSpatialTransform(object.transform, label: "Reset \(object.name)")
    }

    func duplicateSelectedSpatialObject() {
        ensureSpatialScene()
        guard var object = selectedSpatialObject else { return }
        object.id = UUID()
        object.name += " Copy"
        object.transform.position.x += 0.12
        object.transform.position.y -= 0.06
        project.spatialScene?.objects.append(object)
        spatialSelectedObjectID = object.id
        spatialUndoStack.removeAll()
        spatialRedoStack.removeAll()
        statusMessage = "Duplicated spatial surface"
    }

    func deleteSelectedSpatialObject() {
        ensureSpatialScene()
        guard let id = spatialSelectedObjectID else { return }
        project.spatialScene?.objects.removeAll { $0.id == id && !$0.isLocked }
        spatialSelectedObjectID = project.spatialScene?.objects.first?.id
        spatialUndoStack.removeAll()
        spatialRedoStack.removeAll()
        statusMessage = "Deleted spatial surface"
    }

    func setSelectedSpatialVisibility(_ visible: Bool) {
        ensureSpatialScene()
        guard let id = spatialSelectedObjectID,
              let index = project.spatialScene?.objects.firstIndex(where: { $0.id == id }) else { return }
        project.spatialScene?.objects[index].isVisible = visible
    }

    func undoSpatialEdit() {
        guard let record = spatialUndoStack.popLast(),
              let index = project.spatialScene?.objects.firstIndex(where: { $0.id == record.objectID }) else { return }
        let current = project.spatialScene?.objects[index].transform ?? record.after
        project.spatialScene?.objects[index].transform = record.before
        spatialRedoStack.append(.init(objectID: record.objectID, before: record.before, after: current, label: record.label))
        spatialSelectedObjectID = record.objectID
        statusMessage = "Undo: \(record.label)"
    }

    func redoSpatialEdit() {
        guard let record = spatialRedoStack.popLast(),
              let index = project.spatialScene?.objects.firstIndex(where: { $0.id == record.objectID }) else { return }
        project.spatialScene?.objects[index].transform = record.after
        spatialUndoStack.append(record)
        spatialSelectedObjectID = record.objectID
        statusMessage = "Redo: \(record.label)"
    }
}
