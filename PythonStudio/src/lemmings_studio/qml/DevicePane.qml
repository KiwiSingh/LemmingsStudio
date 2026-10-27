import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    readonly property var stateData: studio ? studio.state : ({selected:{},devices:[]})
    spacing:8
    RowLayout {Layout.fillWidth:true;Layout.margins:10;Label{text:"Device Rack";font.bold:true} Label{text:stateData.selected.name || "Select a track";opacity:0.7;Layout.fillWidth:true} LSButton{text:"Add Device";onClicked:studio.command("browser",{value:"FX/Plugins"})}}
    ScrollView {
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentWidth:availableWidth
        ColumnLayout {
            width:parent.width;spacing:10
            Label{visible:stateData.devices.length===0;Layout.fillWidth:true;wrapMode:Text.Wrap;text:(stateData.selected.kind || "Instrument")+" · Add stock devices from FX/Plugins. Parameters and chains are saved in the shared project.";opacity:0.7;padding:12}
            Repeater{model:stateData.selected.externalPluginSlots||[];GlassPanel{required property var modelData;Layout.fillWidth:true;implicitHeight:90;radius:10;ColumnLayout{anchors.fill:parent;anchors.margins:12;Label{text:modelData.name||"Unavailable plugin";font.bold:true}Label{text:(modelData.format||"Plugin")+" · "+(modelData.role||"");font.pixelSize:10;opacity:.7}Label{text:"Unavailable here · identity, automation and saved state retained";Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:10;opacity:.7}}}}
            Repeater {
                model:stateData.devices
                GlassPanel {
                    id: card
                    required property var modelData
                    Layout.fillWidth:true;implicitHeight:content.implicitHeight+24;radius:10
                    ColumnLayout {
                        id:content;anchors.fill:parent;anchors.margins:12;spacing:8
                        RowLayout {
                            Layout.fillWidth:true
                            LSButton{visible:!card.modelData.nativeInstrument;text:card.modelData.bypassed ? "○" : "●";selected:!card.modelData.bypassed;onClicked:studio.command("bypassDevice",{device:card.modelData.id})}
                            Label{text:card.modelData.kind;font.bold:true;Layout.fillWidth:true}
                            LSButton{visible:!card.modelData.nativeInstrument;text:"Mono";selected:!!card.modelData.mono;onClicked:studio.command("monoDevice",{device:card.modelData.id})}
                            LSButton{text:"↑";onClicked:studio.command("moveDevice",{device:card.modelData.id,offset:-1})}
                            LSButton{text:"↓";onClicked:studio.command("moveDevice",{device:card.modelData.id,offset:1})}
                            LSButton{text:"×";onClicked:studio.command("removeDevice",{device:card.modelData.id})}
                        }
                        ColumnLayout {
                            Layout.fillWidth:true;spacing:8
                            Repeater {
                                model:card.modelData.controls
                                ColumnLayout {
                                    id:paramRow
                                    required property var modelData
                                    Layout.fillWidth:true;spacing:1
                                    function normalized(v){return modelData.log && modelData.min>0 ? Math.log(Math.max(modelData.min,v)/modelData.min)/Math.log(modelData.max/modelData.min) : (v-modelData.min)/(modelData.max-modelData.min)}
                                    function natural(v){return modelData.log && modelData.min>0 ? modelData.min*Math.pow(modelData.max/modelData.min,v) : modelData.min+v*(modelData.max-modelData.min)}
                                    RowLayout{Layout.fillWidth:true;Text{text:paramRow.modelData.name;color:studio.palette.text;font.pixelSize:11;Layout.fillWidth:true}Text{text:control.pressed ? paramRow.natural(control.value).toFixed(2)+" "+paramRow.modelData.unit : Number(paramRow.modelData.value).toFixed(2)+" "+paramRow.modelData.unit;color:studio.palette.dim;font.pixelSize:10}}
                                    LSSlider{id:control;Layout.fillWidth:true;from:0;to:1;value:paramRow.normalized(paramRow.modelData.value);onPressedChanged:if(!pressed)studio.command("deviceParam",{device:card.modelData.id,param:paramRow.modelData.id,value:paramRow.natural(value)})}
                                }
                            }
                        }
                        Label{Layout.fillWidth:true;wrapMode:Text.Wrap;text:card.modelData.nativeInstrument ? "Original native Analog Synth · parameters restored from the shared project. Automation awaits the native graph." : "Playback for this device is not available in this Windows build yet. Its settings are saved with the project.";font.pixelSize:10;opacity:0.65}
                    }
                }
            }
        }
    }
}
