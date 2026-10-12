//
//  OnboardingMemoryPhotoTests.swift
//  TwofoldTests
//
//  Adding a memory with photos before a couple exists — the onboarding case, and the same path
//  anyone takes who adds a memory while still solo.
//
//  Reported: photos picked on onboarding's memory screen do not end up on the memory.
//

import Foundation
import Testing
@testable import Twofold

extension PendingMemoryDiskTests {
    @Suite("A memory drafted before pairing keeps its photos", .serialized)
    @MainActor
    struct OnboardingMemoryPhotoTests {

        private var samplePhoto: Data {
            Data([0xFF, 0xD8, 0xFF, 0xDB] + Array(repeating: 0x42, count: 512))
        }

        @Test("addMemory returns a memory carrying the photos")
        func addMemoryKeepsPhotos() async {
            PendingMemoryStore.clear()
            let model = AppModel()

            let memory = await model.addMemory(
                title: "Where we met",
                place: nil,
                date: Date(),
                note: "",
                imagesData: [samplePhoto]
            )

            #expect(memory.photos.count == 1, "the returned memory should carry the photo it was given")
            #expect(model.memories.first(where: { $0.id == memory.id })?.photos.count == 1)
        }

        @Test("and the bytes are on disk, readable back for the upload that happens on pairing")
        func photoBytesSurviveToDisk() async {
            PendingMemoryStore.clear()
            let model = AppModel()

            let memory = await model.addMemory(
                title: "Where we met",
                place: nil,
                date: Date(),
                note: "",
                imagesData: [samplePhoto]
            )

            let restored = PendingMemoryStore.loadAll().first { $0.memory.id == memory.id }
            #expect(restored != nil, "the draft should be on disk")
            #expect(restored?.photosData.count == 1, "its photo bytes should be readable back — this is what performAdopt uploads on pairing")
            #expect(restored?.memory.photos.count == 1)
        }

        @Test("adding a photo to a draft keeps the ids of the photos already on it")
        func photoIDsSurviveAnotherSave() async {
            PendingMemoryStore.clear()
            let model = AppModel()

            let memory = await model.addMemory(title: "Where we met", place: nil, date: Date(), note: "", imagesData: [samplePhoto])
            let firstID = memory.photos.first?.id
            await model.updateMemory(memory, newImagesData: [samplePhoto])

            let updated = model.memories.first { $0.id == memory.id }
            #expect(updated?.photos.count == 2)
            #expect(updated?.photos.first?.id == firstID, "the existing photo should keep its id, or nothing holding it can find it again")
        }

    }
}
