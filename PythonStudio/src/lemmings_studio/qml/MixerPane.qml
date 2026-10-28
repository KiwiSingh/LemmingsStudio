import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ColumnLayout {
    readonly property var stateData:studio ? studio.state : ({tracks:[],groups:[],returns:[],masterDevices:[],masterGain:1})
    spacing:0
    RowLayout{Layout.fillWidth:true;Layout.margins:10;Label{text:"Mixer";font.bold:true}Label{text:stateData.tracks.length+" channels";opacity:.65;Layout.fillWidth:true}LSButton{text:"+ Return";onClicked:studio.command("addReturn",{})}LSButton{text:"Group";onClicked:studio.command("group",{})}LSButton{text:"Ungroup";onClicked:studio.command("ungroup",{})}}
    ScrollView {
        id:mixScroll
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        Row {
            spacing:2;padding:10
            Repeater {
                model:stateData.tracks
                GlassPanel {
                    id:strip
                    required property var modelData
                    width:104;height:Math.max(360,mixScroll.availableHeight-20);radius:6
                    ColumnLayout {
                        anchors.fill:parent;anchors.margins:8;spacing:6
                        LSButton{text:strip.modelData.name;Layout.fillWidth:true;selected:stateData.selectedTrack===strip.modelData.id;accent:strip.modelData.color;onClicked:studio.command("selectTrack",{track:strip.modelData.id})}
                        Label{text:strip.modelData.kind;font.pixelSize:8;Layout.fillWidth:true;elide:Text.ElideRight;opacity:.7}
                        LSSlider{Layout.fillWidth:true;from:-1;to:1;value:strip.modelData.pan;onPressedChanged:if(!pressed)studio.command("track",{track:strip.modelData.id,key:"pan",value:value})}
                        Repeater{model:stateData.returns;RowLayout{required property var modelData;Layout.fillWidth:true;spacing:1;Label{text:modelData.name.substring(0,1);font.pixelSize:9}LSSlider{Layout.fillWidth:true;from:0;to:1;value:{var s=(strip.modelData.sends||[]).filter(function(s){return s.returnBusID===parent.modelData.id})[0];return s ? s.amount : 0}onPressedChanged:if(!pressed)studio.command("send",{track:strip.modelData.id,bus:parent.modelData.id,amount:value})}}}
                        Repeater{model:strip.modelData.devices;LSButton{required property var modelData;Layout.fillWidth:true;text:modelData.kind;font.pixelSize:8;onClicked:{studio.command("selectTrack",{track:strip.modelData.id});studio.command("workspace",{value:"Devices"})}}}
                                                LSSlider{orientation:Qt.Vertical;Layout.fillHeight:true;Layout.minimumHeight:100;Layout.maximumHeight:200;Layout.alignment:Qt.AlignHCenter;from:0;to:1.5;value:strip.modelData.volume;onPressedChanged:if(!pressed)studio.command("track",{track:strip.modelData.id,key:"volume",value:value})}
                        Label{text:(20*Math.log10(Math.max(.00001,strip.modelData.volume))).toFixed(1)+" dB";Layout.alignment:Qt.AlignHCenter;font.pixelSize:10}
                        RowLayout{Layout.fillWidth:true;LSButton{text:"M";selected:strip.modelData.mute;Layout.fillWidth:true;onClicked:studio.command("track",{track:strip.modelData.id,key:"mute",value:!strip.modelData.mute})}LSButton{text:"S";selected:strip.modelData.solo;Layout.fillWidth:true;onClicked:studio.command("track",{track:strip.modelData.id,key:"solo",value:!strip.modelData.solo})}}
                    }
                }
            }
            Repeater {
                model:stateData.returns
                GlassPanel {
                    id:busStrip
                    required property var modelData
                    width:104;height:Math.max(360,mixScroll.availableHeight-20);radius:6
                    ColumnLayout{anchors.fill:parent;anchors.margins:8;spacing:8
                        Label{text:busStrip.modelData.name.toUpperCase();Layout.fillWidth:true;elide:Text.ElideRight;font.bold:true;font.pixelSize:10;color:studio.palette.glowB}
                        Label{text:"Return";font.pixelSize:8;opacity:.7}
                        LSSlider{Layout.fillWidth:true;from:-1;to:1;value:busStrip.modelData.pan;onPressedChanged:if(!pressed)studio.command("returnBus",{bus:busStrip.modelData.id,key:"pan",value:value})}
                        Repeater{model:busStrip.modelData.devices;Label{required property var modelData;text:modelData.kind;font.pixelSize:8;Layout.fillWidth:true;elide:Text.ElideRight}}
                                                LSSlider{orientation:Qt.Vertical;Layout.fillHeight:true;Layout.minimumHeight:100;Layout.maximumHeight:200;Layout.alignment:Qt.AlignHCenter;from:0;to:1.5;value:busStrip.modelData.volume;onPressedChanged:if(!pressed)studio.command("returnBus",{bus:busStrip.modelData.id,key:"volume",value:value})}
                        Label{text:"FX "+busStrip.modelData.devices.length;Layout.alignment:Qt.AlignHCenter;font.pixelSize:9}
                        LSButton{text:"M";selected:busStrip.modelData.mute;Layout.fillWidth:true;onClicked:studio.command("returnBus",{bus:busStrip.modelData.id,key:"mute",value:!busStrip.modelData.mute})}
                    }
                }
            }
            GlassPanel{width:116;height:Math.max(360,mixScroll.availableHeight-20);radius:6
                ColumnLayout{anchors.fill:parent;anchors.margins:8;spacing:8
                    Label{text:"MASTER";font.bold:true;color:studio.palette.focus}
                    Label{text:"Stereo output";font.pixelSize:8;opacity:.7}
                    Repeater{model:stateData.masterDevices;Label{required property var modelData;text:modelData.kind;font.pixelSize:9;Layout.fillWidth:true;elide:Text.ElideRight}}
                                        LSSlider{orientation:Qt.Vertical;Layout.fillHeight:true;Layout.minimumHeight:100;Layout.maximumHeight:200;Layout.alignment:Qt.AlignHCenter;from:0;to:1;value:stateData.masterGain;onPressedChanged:if(!pressed)studio.command("masterGain",{value:value})}
                    Label{text:(20*Math.log10(Math.max(.00001,stateData.masterGain))).toFixed(1)+" dB";Layout.alignment:Qt.AlignHCenter;font.pixelSize:10}
                    Label{text:"Live meters unavailable";wrapMode:Text.Wrap;Layout.fillWidth:true;font.pixelSize:8;opacity:.65}
                }
            }
        }
    }
}
