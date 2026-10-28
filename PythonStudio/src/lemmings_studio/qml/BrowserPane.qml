import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
Item {
    id: browser
    readonly property var stateData: studio ? studio.state : ({browserTabs:[],catalog:[],tracks:[]})
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 10; spacing: 8
        Flow {
            Layout.fillWidth: true; spacing: 4
            Repeater { model: stateData.browserTabs; LSButton { required property string modelData; text: modelData; selected: stateData.browser === modelData; font.pixelSize: 10; onClicked: studio.command("browser", {value:modelData}) } }
        }
        LSTextField{ Layout.fillWidth: true; placeholderText: "Search library / devices"; selectByMouse: true; onTextEdited: studio.command("search", {value:text}) }
        Label { text: stateData.browser === "FX/Plugins" ? "INSTRUMENTS · EFFECTS · RACKS" : stateData.browser.toUpperCase(); font.pixelSize: 10; font.bold: true; opacity: 0.7 }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 5
                Repeater {
                    model: stateData.browser === "Tracks" ? stateData.tracks : stateData.browser === "Library" || stateData.browser === "FX/Plugins" ? stateData.catalog : []
                    delegate: LSButton {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 42
                        text: modelData.kind ? modelData.kind : modelData.name
                        font.pixelSize: 11
                        ToolTip.visible: hovered
                        ToolTip.text: stateData.browser === "Tracks" ? modelData.name : modelData.category + "\nAdd to selected track. Audio support is checked before rendering."
                        onClicked: {
                            if (stateData.browser === "Tracks") studio.command("selectTrack", {track:modelData.id})
                            else studio.command("addDevice", {kind:modelData.kind})
                        }
                    }
                }
                Label { visible: ["Splice","Sounds"].indexOf(stateData.browser)>=0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: stateData.browser === "Splice" ? "Splice is not available in this Windows development build yet." : "Sound Agent is not available in this Windows development build yet."; opacity: 0.7 }
                LSButton { visible: stateData.browser === "Samples"; Layout.fillWidth: true; text: "Import audio…"; onClicked: studio.command("importAudio", {}) }
                Repeater { model: stateData.browser === "Pads" ? [{name:"Kick",note:36},{name:"808 Sub",note:35},{name:"Snare",note:38},{name:"Clap",note:39},{name:"Closed Hat",note:42},{name:"Open Hat",note:46},{name:"Tom",note:45},{name:"Ride",note:51},{name:"Crash",note:49}] : []; LSButton { required property var modelData; Layout.fillWidth: true; text: modelData.name + " · " + modelData.note; onClicked: studio.command("audition", {pitch:modelData.note}) } }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            LSButton { text: "+ MIDI"; Layout.fillWidth: true; onClicked: studio.command("addTrack", {kind:"Analog Synth"}) }
            LSButton { text: "+ Audio"; Layout.fillWidth: true; onClicked: studio.command("addTrack", {kind:"Audio (Recorded)"}) }
        }
        LSButton { text: "Import audio…"; Layout.fillWidth: true; onClicked: studio.command("importAudio", {}) }
    }
}
