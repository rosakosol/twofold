//
//  AddFlightView.swift
//  Twofold
//
//  Thin wrapper around the shared AddFlightFlowView wizard (real AeroAPI-backed search via the
//  resolve-flight Edge Function — the API key never touches this client). Selecting a result
//  opens FlightConfirmationView (link to a trip, notifications) before it's actually persisted
//  and tracked, via add-flight.
//

import SwiftUI

struct AddFlightView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AddFlightFlowView(
            nearCoordinate: appModel.currentUser.homeCity?.coordinate,
            topBarTitle: "Cancel",
            onTopBarAction: { dismiss() },
            completion: .confirmAndTrack(onDone: { dismiss() })
        )
    }
}

#Preview {
    AddFlightView()
        .environment(AppModel())
}
