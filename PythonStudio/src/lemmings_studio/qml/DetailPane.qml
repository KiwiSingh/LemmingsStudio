import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    readonly property var stateData: studio ? studio.state : ({detail:"Devices",selected:{}})
    spacing:2
    RowLayout{Layout.fillWidth:true;Layout.margins:8;Repeater{model:["Devices","Clip","Mix","Automation"];LSButton{required property string modelData;text:modelData;selected:stateData.detail===modelData;font.pixelSize:10;onClicked:studio.command("detail",{value:modelData})}}Item{Layout.fillWidth:true}Label{text:stateData.selected.name||"";opacity:0.6;font.pixelSize:10}}
    Loader{Layout.fillWidth:true;Layout.fillHeight:true;source:({Devices:"DevicePane.qml",Clip:"InspectorPane.qml",Mix:"MixerPane.qml",Automation:"AutomationPane.qml"})[stateData.detail]||"DevicePane.qml"}
}
