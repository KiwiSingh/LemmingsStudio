import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    readonly property var stateData: studio ? studio.state : ({tracks:[],scenes:8})
    spacing: 8
    RowLayout { Layout.fillWidth:true;Layout.margins:10; Label{text:"Session";font.bold:true} Label{text:"Launch clips/scenes · double-click empty slots to create MIDI clips";font.pixelSize:10;Layout.fillWidth:true;wrapMode:Text.Wrap;opacity:0.7} SpinBox{from:4;to:16;value:stateData.scenes;onValueModified:studio.command("scenes",{value:value})} }
    ScrollView {
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        Column {
            spacing:1
            Row { spacing:1; Label {width:86;height:36;text:"SCENES";verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter;font.pixelSize:10}
                Repeater{model:stateData.tracks;LSButton{required property var modelData;width:138;height:36;text:modelData.name;selected:stateData.selectedTrack===modelData.id;onClicked:studio.command("selectTrack",{track:modelData.id})}}
            }
            Repeater {
                model:stateData.scenes
                Row {
                    id: sceneRow
                    required property int index
                    spacing:1
                    LSButton {width:86;height:58;text:"▶ Scene "+(sceneRow.index+1);onClicked:studio.command("launchScene",{scene:sceneRow.index})}
                    Repeater {
                        model:stateData.tracks
                        delegate: Rectangle {
                            required property var modelData
                            readonly property var slot: modelData.clips[sceneRow.index] || null
                            width:138;height:58;radius:4;color:slot ? Qt.darker(modelData.color,3) : "#18000000";border.color:studio.palette.grid
                            Text {anchors.fill:parent;anchors.margins:9;text:slot ? "▶  "+slot.name : "+";color:slot ? modelData.color : studio.palette.dim;elide:Text.ElideRight;verticalAlignment:Text.AlignVCenter;font.pixelSize:11}
                            MouseArea {anchors.fill:parent;onClicked: {if(parent.slot)studio.command("launchClip",{track:parent.modelData.id,clip:parent.slot.id})} onDoubleClicked: {if(!parent.slot)studio.command("createClip",{track:parent.modelData.id,start:sceneRow.index*16,length:4})}}
                        }
                    }
                }
            }
        }
    }
}
