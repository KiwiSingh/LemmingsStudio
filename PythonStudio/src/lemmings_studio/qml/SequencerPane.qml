import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    readonly property var stateData: studio ? studio.state : ({selected:{},kits:[]})
    readonly property var pattern: stateData.selected.stepPattern || ({steps:[],stepCount:16})
    readonly property var voices: [{name:"Kick",note:36},{name:"808 Sub",note:35},{name:"Snare",note:38},{name:"Clap",note:39},{name:"Rim",note:37},{name:"Closed Hat",note:42},{name:"Open Hat",note:46},{name:"Tom",note:45},{name:"Ride",note:51},{name:"Crash",note:49}]
    spacing:8
    RowLayout {
        Layout.fillWidth:true;Layout.margins:8
        Label{text:"Step Sequencer";font.bold:true}
        LSComboBox{model:stateData.kits;Layout.preferredWidth:130;currentIndex:Math.max(0,stateData.kits.indexOf(stateData.selected.drumGenre));onActivated:studio.command("track",{key:"drumGenre",value:currentText})}
        SpinBox{from:4;to:64;value:pattern.stepCount;onValueModified:studio.command("patternLength",{value:value})}
        Item{Layout.fillWidth:true}
        LSButton{text:"Print";enabled:["Drum Machine","Sequencer"].indexOf(stateData.selected.kind)>=0;onClicked:studio.command("printSteps",{})}
        LSButton{text:"Clear";onClicked:studio.command("clearSteps",{})}
    }
    Label{visible:["Drum Machine","Sequencer"].indexOf(stateData.selected.kind)<0;Layout.fillWidth:true;Layout.margins:10;wrapMode:Text.Wrap;text:"Select a Drum Machine or Sequencer track for built-in drum lanes.";opacity:0.7}
    ScrollView {
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        Column {
            spacing:5
            Repeater {
                model:voices
                Row {
                    id: lane
                    required property var modelData
                    spacing:4
                    LSButton {width:108;height:32;text:lane.modelData.name;onClicked:studio.command("audition",{pitch:lane.modelData.note})}
                    Repeater {
                        model:pattern.stepCount
                        LSButton {
                            required property int index
                            width:28;height:32
                            enabled:["Drum Machine","Sequencer"].indexOf(stateData.selected.kind)>=0
                            text:(index+1).toString()
                            selected:!!pattern.steps[index] && (pattern.steps[index].hits || (pattern.steps[index].on ? [pattern.steps[index].note] : [])).indexOf(lane.modelData.note)>=0
                            accent:Math.floor(index/4)%2 ? studio.palette.glowB : studio.palette.play
                            onClicked:studio.command("step",{pitch:lane.modelData.note,step:index})
                        }
                    }
                }
            }
        }
    }
}
