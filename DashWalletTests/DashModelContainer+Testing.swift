import SwiftData
import SwiftDashSDK

extension DashModelContainer {
    /// `DashModelContainer.createInMemory()` leaves `cloudKitDatabase` at `.automatic`,
    /// which the dashpay host app's iCloud entitlement turns into a CloudKit-backed
    /// store that refuses the schema's non-optional relationships. Tests only
    /// need the models, so they build the in-memory container without CloudKit.
    static func inMemoryWithoutCloudKit() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
