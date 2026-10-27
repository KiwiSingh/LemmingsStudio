import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ScrollView {
    id:autoPane
    readonly property var stateData:studio ? studio.state : ({selected:{},devices:[],automationNodes:[],tempoPoints:[],tracks:[]})
    readonly property var lanes:stateData.selected.automationLanes||[]
    clip:true;contentWidth:availableWidth
    ColumnLayout {
        width:autoPane.availableWidth;spacing:12
        RowLayout{Layout.fillWidth:true;Layout.margins:10;Label{text:"Global Automation";font.bold:true;Layout.fillWidth:true}Switch{text:"Tempo";checked:!!autoPane.stateData.tempoAutomationEnabled;onToggled:studio.command("tempoEnabled",{value:checked})}LSButton{text:"Clear";onClicked:studio.command("tempoClear",{})}}
        CurveEditor{Layout.fillWidth:true;Layout.preferredHeight:96;Layout.leftMargin:10;Layout.rightMargin:10;points:autoPane.stateData.tempoPoints;tracks:autoPane.stateData.tracks;minimum:40;maximum:220;valueKey:"bpm";lengthBeats:autoPane.stateData.lengthBeats||128;onEdited:function(index,beat,value){studio.command("tempoPoint",{index:index,beat:beat,value:value})}onRemoved:function(index){studio.command("tempoDelete",{index:index})}}
        RowLayout{Layout.fillWidth:true;Layout.margins:10;Label{text:"Clip / Track Automation";font.bold:true;Layout.fillWidth:true}LSComboBox{id:target;model:autoPane.stateData.automationNodes;textRole:"name";Layout.preferredWidth:130}LSComboBox{id:parameter;model:target.model[target.currentIndex] ? target.model[target.currentIndex].params : [];textRole:"name";Layout.preferredWidth:130}LSButton{text:"+ Lane";enabled:parameter.currentIndex>=0;onClicked:studio.command("automationLane",{node:target.model[target.currentIndex].id,param:parameter.model[parameter.currentIndex].id})}}
        Label{Layout.fillWidth:true;Layout.margins:10;text:"Click to add/select · drag to move · right-click to delete. Automation drives native playback and export; values leave the saved manual controls intact.";wrapMode:Text.Wrap;opacity:.65;font.pixelSize:10}
        Repeater {
            model:autoPane.lanes
            GlassPanel {
                id:lane
                required property var modelData
                required property int index
                readonly property var node:autoPane.stateData.automationNodes.filter(function(n){return n.id===lane.modelData.nodeID})[0]
                readonly property var param:node ? node.params.filter(function(p){return p.id===lane.modelData.paramID})[0] : null
                Layout.fillWidth:true;Layout.margins:8;implicitHeight:160;radius:8
                ColumnLayout{anchors.fill:parent;anchors.margins:10
                    RowLayout{Layout.fillWidth:true;Label{text:(lane.node ? lane.node.name : lane.modelData.nodeID)+" · "+(lane.param ? lane.param.name : lane.modelData.paramID);Layout.fillWidth:true;elide:Text.ElideRight}Switch{checked:lane.modelData.enabled;onToggled:studio.command("automationLaneEnabled",{lane:lane.index,value:checked})}LSButton{text:"×";onClicked:studio.command("automationLaneDelete",{lane:lane.index})}}
                    CurveEditor{Layout.fillWidth:true;Layout.fillHeight:true;enabled:!!lane.param;points:lane.modelData.points;tracks:[autoPane.stateData.selected];lengthBeats:autoPane.stateData.lengthBeats||128;minimum:lane.param ? lane.param.min : 0;maximum:lane.param ? lane.param.max : 1;logarithmic:lane.param ? lane.param.log : false;onEdited:function(index,beat,value){studio.command("automationEdit",{lane:lane.index,index:index,beat:beat,value:value})}onRemoved:function(index){studio.command("deleteAutomationPoint",{lane:lane.index,index:index})}}
                }
            }
        }
    }
}
