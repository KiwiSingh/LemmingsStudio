import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ScrollView {
    readonly property var stateData: studio ? studio.state : ({selected:{},clip:{},trackKinds:[]})
    clip:true;contentWidth:availableWidth
    ColumnLayout {
        width:parent.width;spacing:10
        Label{text:"INSPECTOR";font.pixelSize:10;font.bold:true;opacity:0.7}
        LSTextField{Layout.fillWidth:true;text:stateData.selected.name||"";placeholderText:"Track name";selectByMouse:true;onEditingFinished:if(stateData.selected.id)studio.command("track",{key:"name",value:text})}
        Label{text:stateData.selected.kind||"Select a track";font.pixelSize:11;opacity:0.7}
        RowLayout {Layout.fillWidth:true;LSButton{text:"Mute";selected:!!stateData.selected.mute;onClicked:studio.command("track",{key:"mute",value:!stateData.selected.mute})}LSButton{text:"Solo";selected:!!stateData.selected.solo;onClicked:studio.command("track",{key:"solo",value:!stateData.selected.solo})}LSButton{text:"Arm";selected:!!stateData.selected.armed;onClicked:studio.command("track",{key:"armed",value:!stateData.selected.armed})}}
        Label{text:"Volume";opacity:0.7}
        LSSlider{Layout.fillWidth:true;from:0;to:1.5;value:stateData.selected.volume||0;onPressedChanged:if(!pressed && stateData.selected.id)studio.command("track",{key:"volume",value:value})}
        Label{text:"Pan";opacity:0.7}
        LSSlider{Layout.fillWidth:true;from:-1;to:1;value:stateData.selected.pan||0;onPressedChanged:if(!pressed && stateData.selected.id)studio.command("track",{key:"pan",value:value})}
        RowLayout{LSButton{text:"Group selected";onClicked:studio.command("group",{})}LSButton{text:"Delete track";onClicked:studio.command("deleteTracks",{})}}
        Rectangle{Layout.fillWidth:true;height:1;color:studio.palette.grid}
        Label{text:"CLIP";font.pixelSize:10;font.bold:true;opacity:0.7}
        Label{visible:!stateData.clip.id;text:"Select a clip in Arrangement or Session.";wrapMode:Text.Wrap;Layout.fillWidth:true;opacity:0.7}
        LSTextField{Layout.fillWidth:true;enabled:!!stateData.clip.id;text:stateData.clip.name||"";placeholderText:"Clip name";selectByMouse:true;onEditingFinished:{var v={};v[stateData.clip.audio ? "displayName" : "name"]=text;studio.command("clip",{values:v})}}
        RowLayout {
            Label{text:"Start beat";Layout.preferredWidth:75}
            LSTextField{Layout.fillWidth:true;enabled:!!stateData.clip.id;text:Number(stateData.clip.startBeat||0).toFixed(2);onEditingFinished:studio.command("clip",{values:{startBeat:Number(text)}})}
        }
        RowLayout {
            Label{text:"Length";Layout.preferredWidth:75}
            LSTextField{Layout.fillWidth:true;enabled:!!stateData.clip.id;text:Number(stateData.clip.lengthBeats||4).toFixed(2);onEditingFinished:{var v={};v[stateData.clip.audio ? "lengthBeatsOverride" : "lengthBeats"]=Number(text);studio.command("clip",{values:v})}}
        }
        RowLayout {LSButton{text:"Loop";enabled:!!stateData.clip.id;selected:!!stateData.clip.loopEnabled;onClicked:studio.command("clip",{values:{loopEnabled:!stateData.clip.loopEnabled}})}LSButton{text:"Duplicate";enabled:!!stateData.clip.id;onClicked:studio.command("duplicateClip",{})}LSButton{text:"Delete";enabled:!!stateData.clip.id;onClicked:studio.command("deleteClip",{})}}
        Label{visible:!!stateData.selectedNote;text:"NOTE · velocity and length";opacity:0.7}
        LSSlider{visible:!!stateData.selectedNote;Layout.fillWidth:true;from:0;to:1;value:stateData.note && stateData.note.velocity!==undefined ? stateData.note.velocity : 0.9;onPressedChanged:if(!pressed)studio.command("note",{note:stateData.selectedNote,values:{velocity:value}})}
        LSButton{text:"New MIDI clip";Layout.fillWidth:true;onClicked:studio.command("createClip",{start:0})}
    }
}
