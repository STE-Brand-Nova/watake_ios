import Foundation
import WatakeDomain

extension WatermarkEditorModel {
    public func loadPresets() {
        let operation = beginPresetOperation()
        presetLibraryState = .loading
        presetTask = Task { [weak self] in
            guard let self else { return }
            do {
                let presets = try await presetStore.watermarkPresets().sortedForWatermarkLibrary()
                guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
                let items = presets.map(WatermarkPresetLibraryItem.init)
                presetLibraryState = items.isEmpty ? .empty : .loaded(items)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
                presetLibraryState = .failure
            }
        }
    }

    public func savePreset(named rawName: String) {
        guard case .valid(let name) = WatermarkPresetNameValidation.validate(rawName) else {
            presetSaveState = .invalidName(WatermarkPresetNameValidation.validate(rawName))
            return
        }
        guard canPersistImagePreset else {
            presetSaveState = .imageUnsupported
            return
        }

        let operation = beginPresetOperation()
        let savedDraftRevision = draftRevision
        let snapshot = draft.watermarkConfig
        let timestamp = now()
        let preset = WatermarkPreset(
            id: makeUUID(),
            name: name,
            config: snapshot,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        presetSaveState = .saving
        presetTask = Task { [weak self] in
            guard let self else { return }
            await persistPreset(preset, operation: operation, savedDraftRevision: savedDraftRevision)
        }
    }

    /// Copies the immutable stored configuration into a fresh editable draft.
    /// Image bytes are loaded through the asset boundary before publication.
    public func applyPreset(_ item: WatermarkPresetLibraryItem) {
        let operation = beginPresetOperation()
        guard isCurrentPresetOperation(operation) else { return }
        draft = WatermarkEditorDraft(config: item.preset.config)
        imageData = nil
        imageImportTask?.cancel()
        imageImportState = .empty
        imageImportError = nil
        refreshEditorInputs()
        draftRevision += 1
        activePresetState = .selected(id: item.preset.id, name: item.preset.name)
        schedulePreview(draftDidChange: false)
        guard let reference = item.preset.config.image?.assetRef else { return }
        presetTask = Task { [weak self] in
            guard let self, let assetStore else { return }
            do {
                let data = try await assetStore.readAsset(reference)
                guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
                imageData = data
                imageImportState = .loaded
                schedulePreview(draftDidChange: false)
            } catch {
                guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
                imageImportError = .undecodable
                imageImportState = .rejected(.undecodable)
                schedulePreview(draftDidChange: false)
            }
        }
    }

    public func resetPresetSaveState() {
        guard presetSaveState != .saving else { return }
        presetSaveState = .idle
    }

    /// Test synchronization seam for preset load and save work.
    public func waitForPresetWork() async {
        await presetTask?.value
    }

    func beginPresetOperation() -> Int {
        presetOperationRevision += 1
        presetTask?.cancel()
        return presetOperationRevision
    }

    func isCurrentPresetOperation(_ operation: Int) -> Bool {
        presetOperationRevision == operation
    }

    func markDraftModifiedIfNeeded() {
        guard case .selected(let id, let name) = activePresetState else { return }
        activePresetState = .modified(id: id, name: name)
    }

    func refreshEditorInputs() {
        imageTintInput = draft.image.tintHex ?? ""
        colorInputs = Dictionary(
            uniqueKeysWithValues: WatermarkTextLayerKind.allCases.map { kind in
                (kind, draft.layer(for: kind).colorHex)
            }
        )
    }

    private func persistPreset(
        _ preset: WatermarkPreset,
        operation: Int,
        savedDraftRevision: Int
    ) async {
        do {
            try await persistPresetImageIfNeeded(preset)
            try await presetStore.saveWatermarkPreset(preset)
            guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
            presetSaveState = .saved
            let presets = await (try? presetStore.watermarkPresets()) ?? [preset]
            guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
            presetLibraryState = .loaded(presets.map(WatermarkPresetLibraryItem.init))
            guard draftRevision == savedDraftRevision else { return }
            activePresetState = .selected(id: preset.id, name: preset.name)
        } catch is CancellationError {
            return
        } catch WatermarkPresetStoreError.duplicateName {
            guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
            presetSaveState = .conflict
        } catch PresetImagePersistenceError.missingImageData {
            presetSaveState = .imageUnsupported
        } catch {
            guard isCurrentPresetOperation(operation), !Task.isCancelled else { return }
            presetSaveState = .failure
        }
    }

    private func persistPresetImageIfNeeded(_ preset: WatermarkPreset) async throws {
        guard let reference = preset.config.image?.assetRef else { return }
        guard let assetStore, let imageData else { throw PresetImagePersistenceError.missingImageData }
        if try await !assetStore.containsAsset(reference) {
            try await assetStore.saveAsset(imageData, reference: reference)
        }
    }
}

private enum PresetImagePersistenceError: Error {
    case missingImageData
}
