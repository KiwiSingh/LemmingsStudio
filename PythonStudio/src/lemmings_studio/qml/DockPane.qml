import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    id:dock
    readonly property var stateData: studio ? studio.state : ({dockTabs:[],dock:"Inspect",tracks:[]})
    spacing:8
    Flow{Layout.fillWidth:true;spacing:4;Repeater{model:stateData.dockTabs;LSButton{required property string modelData;text:modelData;selected:stateData.dock===modelData;font.pixelSize:10;onClicked:studio.command("dock",{value:modelData})}}}
    InspectorPane{visible:stateData.dock==="Inspect";Layout.fillWidth:true;Layout.fillHeight:true}
    ColumnLayout{
        visible:stateData.dock==="Fifths";Layout.fillWidth:true;Layout.fillHeight:true
        Label{text:"Circle of Fifths";font.bold:true}
        Item{Layout.fillWidth:true;Layout.preferredHeight:280
            Repeater{model:["C","G","D","A","E","B","F♯","D♭","A♭","E♭","B♭","F"];LSButton{required property string modelData;required property int index;width:42;height:34;x:parent.width/2-21+Math.sin(index*Math.PI/6)*Math.min(110,parent.width/2-25);y:120-Math.cos(index*Math.PI/6)*110;text:modelData;selected:stateData.keyRoot===(index*7)%12;onClicked:studio.command("key",{root:(index*7)%12,scale:stateData.scale})}}
        }
        LSButton{text:"Insert tonic triad";Layout.fillWidth:true;onClicked:studio.command("chord",{})}
        Item{Layout.fillHeight:true}
    }
    ScrollView {
        visible:["Inspect","Fifths"].indexOf(stateData.dock)<0;Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentWidth:availableWidth
        ColumnLayout {
            width:parent.width;spacing:10
            Label{text:({"Chat":"General Chat","AI":"AI Assistant","Sound":"Describe a Sound","Splice":"Splice","Voices":"Voice AI Studio"})[stateData.dock]||stateData.dock;font.pixelSize:16;font.bold:true}
            LSComboBox{visible:["Chat","AI","Sound"].indexOf(stateData.dock)>=0;Layout.fillWidth:true;model:["Claude API","Local (Ollama)"]}
            Label{visible:stateData.dock==="AI";text:"Target: "+(stateData.selected.name||"Project");opacity:0.7}
            LSTextField{visible:stateData.dock==="Splice";Layout.fillWidth:true;placeholderText:"Search samples, loops, instruments…";selectByMouse:true}
            LSComboBox{visible:stateData.dock==="Splice";Layout.fillWidth:true;model:["All samples","One-shots","Loops","MIDI"]}
            RowLayout{visible:stateData.dock==="Splice";Layout.fillWidth:true;LSTextField{Layout.fillWidth:true;placeholderText:"BPM min"}LSTextField{Layout.fillWidth:true;placeholderText:"BPM max"}}
            LSComboBox{visible:stateData.dock==="Voices";Layout.fillWidth:true;model:stateData.tracks.filter(function(t){return t.kind==="Audio (Recorded)"}).map(function(t){return t.name})}
            TextArea{id:promptInput;color:studio.palette.text;placeholderTextColor:studio.palette.dim;selectionColor:studio.palette.focus;background:Rectangle{radius:6;color:studio.palette.panel;border.color:promptInput.activeFocus ? studio.palette.focus : studio.palette.glassStroke;border.width:.8}
                visible:stateData.dock!=="Splice";Layout.fillWidth:true;Layout.preferredHeight:160;placeholderText:stateData.dock==="Sound" ? "Describe the timbre, envelope and motion…" : stateData.dock==="Voices" ? "Lyrics / voice-render notes…" : "Describe what you want to create or change…";wrapMode:TextEdit.Wrap;selectByMouse:true}
            LSButton{Layout.fillWidth:true;text:stateData.dock==="Splice" ? "Connect / Search" : stateData.dock==="Voices" ? "Transform voice" : stateData.dock==="Sound" ? "Design sound" : "Preview changes";enabled:false;ToolTip.visible:hovered;ToolTip.text:"Not available in this Windows development build yet."}
            Label{Layout.fillWidth:true;wrapMode:Text.Wrap;text:"Not available in this Windows development build yet.";opacity:0.65;font.pixelSize:11}
        }
    }
}
