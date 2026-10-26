import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
Item {
    id: timeline
    property bool piano: false
    readonly property var stateData: studio ? studio.state : ({tracks:[],clip:{},selected:{}})
    readonly property var colours: studio ? studio.palette : ({grid:"#334455",dim:"#aabbcc",focus:"cyan",text:"white",panel:"#202020"})
    property real zoom: piano ? 72 : 44
    property real noteHeight: 14
    property real labelWidth: piano ? 58 : 154
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 8
            Label { text: piano ? "Piano Roll" : "Arrangement"; font.bold: true }
            LSButton { text: "+ Clip"; onClicked: studio.command("createClip", {start:0}) }
            LSButton { text: "Quantize"; visible: piano; enabled: !!stateData.clip.id; onClicked: studio.command("quantize", {}) }
            Label { text: "Snap"; opacity: 0.7 }
            LSComboBox{ model: ["1/16","1/8","1/4","1/2","1 bar"]; implicitWidth: 86; currentIndex: [0.25,0.5,1,2,4].indexOf(stateData.snap); onActivated: studio.command("snap", {value:[0.25,0.5,1,2,4][currentIndex]}) }
            Item { Layout.fillWidth: true }
            LSButton { text: "−"; onClicked: timeline.zoom=Math.max(16,timeline.zoom/1.25) }
            LSButton { text: "+"; onClicked: timeline.zoom=Math.min(180,timeline.zoom*1.25) }
        }
        Label { visible: piano && !stateData.clip.id; text: "Select a MIDI clip in Arrangement, or create a clip on an instrument track."; Layout.margins: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Flickable {
            id: viewport
            objectName:timeline.piano ? "pianoViewport" : "arrangementViewport"
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: Math.max(width, labelWidth + Math.max(32, timeline.piano ? stateData.clip.lengthBeats || 0 : stateData.lengthBeats || 128)*zoom)
            contentHeight: piano ? 48*noteHeight+32 : Math.max(height,stateData.tracks.length*82+34)
            ScrollBar.horizontal: ScrollBar {}
            ScrollBar.vertical: ScrollBar {}
            Canvas {
                id: grid
                width: viewport.contentWidth; height: viewport.contentHeight
                onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                Connections { target: studio; function onChanged(){grid.requestPaint()} }
                onPaint: {
                    var c=getContext("2d"); c.clearRect(0,0,width,height)
                    c.strokeStyle=colours.grid; c.lineWidth=1; c.font="10px sans-serif"; c.fillStyle=colours.dim
                    for(var b=0;b<(width-labelWidth)/zoom;b++) {var x=labelWidth+b*zoom;c.beginPath();c.moveTo(x,28);c.lineTo(x,height);c.stroke();if(b%4===0)c.fillText((b/4+1).toString(),x+4,18)}
                    if(piano) {
                        for(var i=0;i<48;i++){var pitch=83-i; var y=28+i*noteHeight;var black=[1,3,6,8,10].indexOf(pitch%12)>=0;c.fillStyle=black ? "#22000000" : "#11ffffff";c.fillRect(labelWidth,y,width-labelWidth,noteHeight);c.fillStyle=black ? "#20232a" : "#b7bdc8";c.fillRect(0,y,labelWidth-4,noteHeight-1);if(pitch%12===0){c.fillStyle="#20232a";c.fillText("C"+(Math.floor(pitch/12)-1),4,y+11)}}
                    } else {for(var t=0;t<stateData.tracks.length;t++){c.beginPath();c.moveTo(0,30+t*82);c.lineTo(width,30+t*82);c.stroke()}}
                }
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.LeftButton
                onDoubleClicked: function(mouse) {
                    if(piano) {if(stateData.clip.id && mouse.x>=labelWidth)studio.command("addNote", {beat:Math.max(0,(mouse.x-labelWidth)/zoom),pitch:Math.max(0,83-Math.floor((mouse.y-28)/noteHeight))})}
                    else {var index=Math.floor((mouse.y-30)/82);if(index>=0 && index<stateData.tracks.length)studio.command("createClip", {track:stateData.tracks[index].id,start:Math.max(0,Math.floor((mouse.x-labelWidth)/zoom/4)*4)})}
                }
                onClicked: function(mouse) {if(mouse.y<28)studio.command("seek", {beat:Math.max(0,(mouse.x-labelWidth)/zoom)})}
            }
            Repeater {
                model: piano ? [] : stateData.tracks
                delegate: Item {
                    id: trackRow
                    required property var modelData
                    required property int index
                    x: 0; y: 30+index*82; width: viewport.contentWidth; height: 82
                    Rectangle { width: labelWidth-5; height: 78; color: stateData.selectedTrack === trackRow.modelData.id ? "#334488aa" : colours.panel; radius: 5
                        Rectangle { width: 4; height: parent.height; color: trackRow.modelData.color }
                        Column { x: 12; y: 12; spacing: 6; Text { text: trackRow.modelData.name; color: colours.text; font.pixelSize: 12 } Text { text: trackRow.modelData.kind; color: colours.dim; font.pixelSize: 9 } }
                        MouseArea { anchors.fill: parent; onClicked: function(mouse){studio.command("selectTrack",{track:trackRow.modelData.id,extend:!!(mouse.modifiers&(Qt.ControlModifier|Qt.ShiftModifier))})} }
                    }
                    Repeater {
                        model: trackRow.modelData.clips
                        delegate: Rectangle {
                            id: clipRegion
                            objectName:"clip-"+modelData.id
                            required property var modelData
                            x: labelWidth+modelData.startBeat*zoom; y: 6; width: Math.max(10,modelData.lengthBeats*zoom); height: 64
                            radius: 6; color: Qt.darker(trackRow.modelData.color,2.8); opacity: modelData.isActive === false ? 0.35 : 1
                            border.color: trackRow.modelData.color; border.width: stateData.selectedClip===modelData.id ? 2 : 1
                            Text { x: 7;y: 6;width:parent.width-14;elide:Text.ElideRight;text:clipRegion.modelData.name;color:colours.text;font.pixelSize:11 }
                            Canvas { anchors.fill: parent; anchors.topMargin: 23; visible: !!clipRegion.modelData.audio
                                onPaint: {var c=getContext("2d");c.clearRect(0,0,width,height);var a=clipRegion.modelData.waveform||[];c.strokeStyle=trackRow.modelData.color;c.beginPath();for(var i=0;i<a.length;i++){var x=i/Math.max(1,a.length-1)*width;c.moveTo(x,height/2-a[i]*height/2);c.lineTo(x,height/2+a[i]*height/2)}c.stroke()}
                            }
                            MouseArea {
                                anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                property real initialX: 0; property real pressY: 0;property bool resizing:false
                                onPressed: function(mouse){ initialX=clipRegion.modelData.startBeat;pressY=mouse.y;pressedX=mouse.x;resizing=mouse.x>width-9;if(mouse.button===Qt.RightButton)clipMenu.popup() }
                                onReleased: function(mouse){if(mouse.button===Qt.LeftButton && resizing && Math.abs(mouse.x-pressedX)>4){var values={};values[clipRegion.modelData.audio ? "lengthBeatsOverride" : "lengthBeats"]=Math.max(stateData.snap,Math.round((clipRegion.modelData.lengthBeats+(mouse.x-pressedX)/zoom)/stateData.snap)*stateData.snap);studio.command("clip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id,values:values})}else if(mouse.button===Qt.LeftButton && (Math.abs(mouse.x-pressedX)>4 || Math.abs(mouse.y-pressY)>4)){var target=Math.max(0,Math.min(stateData.tracks.length-1,trackRow.index+Math.round((mouse.y-pressY)/82)));studio.command("moveClip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id,target:stateData.tracks[target].id,start:initialX+(mouse.x-pressedX)/zoom})}else if(mouse.button===Qt.LeftButton){studio.command("selectClip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id})}}
                                property real pressedX: 0
                                onPositionChanged: function(mouse){ }
                                onDoubleClicked: studio.command("workspace",{value:"Piano Roll"})
                                Component.onCompleted: pressedX=0
                                onClicked: function(mouse){ }
                                onPressAndHold: clipMenu.popup()
                            }
                            Menu { id: clipMenu
                                MenuItem { text: "Duplicate"; onTriggered: studio.command("duplicateClip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id}) }
                                MenuItem { text: "Activate / deactivate"; onTriggered: studio.command("clip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id,values:{isActive:clipRegion.modelData.isActive===false}}) }
                                MenuItem { text: "Delete"; onTriggered: studio.command("deleteClip",{track:trackRow.modelData.id,clip:clipRegion.modelData.id}) }
                            }
                        }
                    }
                }
            }
            Repeater {
                model: piano ? (stateData.clip.notes || []) : []
                delegate: Rectangle {
                    id: note
                    objectName:"note-"+modelData.id
                    required property var modelData
                    x: labelWidth+modelData.start*zoom; y: 28+(83-modelData.pitch)*noteHeight
                    width: Math.max(6,modelData.length*zoom); height: noteHeight-1; radius: 3
                    color: stateData.selectedNote===modelData.id ? colours.focus : (stateData.selected.color || "#87c8ff")
                    opacity: 0.45+modelData.velocity*0.55
                    MouseArea {
                        anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        property real pressX: 0; property real pressY: 0; property bool resizing: false
                        onPressed: function(mouse){pressX=mouse.x;pressY=mouse.y;resizing=mouse.x>width-8;if(mouse.button===Qt.RightButton)noteMenu.popup()}
                        onReleased: function(mouse){if(mouse.button!==Qt.LeftButton)return;var values={};if(resizing)values.length=Math.max(0.0625,note.modelData.length+(mouse.x-pressX)/zoom);else{values.start=Math.max(0,Math.round((note.modelData.start+(mouse.x-pressX)/zoom)/stateData.snap)*stateData.snap);values.pitch=Math.max(0,Math.min(127,note.modelData.pitch-Math.round((mouse.y-pressY)/noteHeight)))}studio.command("note",{note:note.modelData.id,values:values})}
                    }
                    Menu { id: noteMenu; MenuItem { text:"Delete note";onTriggered:studio.command("deleteNote",{note:note.modelData.id}) } }
                }
            }
            Rectangle { x:labelWidth+(studio ? studio.transport.beat : 0)*zoom; y:26; width:1; height:viewport.contentHeight-26; color: studio ? studio.palette.play : "lime" }
        }
    }
}
