import SwiftUI

struct DrawingWorkDetails: View {
    @Binding var title:String
    @Binding var details:String
    @Binding var priority:Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Arbeitsanweisung (optional)") {
                    TextField("Titel",text:$title,axis:.vertical).lineLimit(1...3).accessibilityIdentifier("drawing.title")
                    TextField("Beschreibung",text:$details,axis:.vertical).lineLimit(3...8)
                    Text("\(title.count) / 240 Zeichen im Titel").font(.caption).foregroundStyle(title.count>240 ? .red : .secondary)
                    Picker("Priorität",selection:$priority) { Text("Niedrig").tag(0); Text("Normal").tag(1); Text("Hoch").tag(2) }
                }
            }.navigationTitle("Arbeitsanweisung").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Übernehmen") { dismiss() }.disabled(title.count>240) } }
        }
    }
}
struct DrawingPlacementSettings: View {
    @Binding var measured:Bool
    @Binding var distance:Double
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Gemessenen Abstand verwenden",isOn:$measured)
                if measured { TextField("Abstand in Metern",value:$distance,format:.number).keyboardType(.decimalPad) }
                Text("Nur verwenden, wenn keine Oberfläche erkannt wird. Miss den Abstand von der Kamera selbst. Nach der ersten Platzierung bleibt die Zeichenebene fixiert.").font(.footnote)
            }.navigationTitle("Platzierung").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fertig") { dismiss() }.disabled(measured && (!distance.isFinite || distance<0.1 || distance>10)) } }
        }
    }
}
