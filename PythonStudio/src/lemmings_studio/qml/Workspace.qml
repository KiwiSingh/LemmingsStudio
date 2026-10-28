import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
ApplicationWindow {
    id:window
    objectName:"lemmingsWorkspace"
    visible:false;minimumWidth:640;minimumHeight:480;width:1600;height:960
    readonly property var stateData: studio ? studio.state : ({tracks:[],workspaces:[],theme:"Liquid Glass",themes:[],selected:{},clip:{},status:"",projectName:"Untitled"})
    readonly property var colours: studio ? studio.palette : ({backgroundA:"#101018",backgroundB:"#202030",backgroundC:"#101018",text:"white",dim:"#aaaaaa",panel:"#20202e",panel2:"#303044",grid:"#445566",focus:"cyan",play:"lime",record:"red",glowA:"cyan",glowB:"purple"})
    property bool showDetails:true
    readonly property bool wide:width>=1450
    readonly property bool browserInline:width>=1050
    title:(stateData.dirty ? "* " : "")+stateData.projectName+" — LemmingsStudio"
    font.pixelSize:12;font.family:Qt.platform.os==="windows" ? "Segoe UI" : "Helvetica Neue"
    palette.window:colours.backgroundA;palette.windowText:colours.text;palette.text:colours.text;palette.buttonText:colours.text;palette.base:colours.backgroundA;palette.button:colours.panel2;palette.highlight:colours.focus;palette.highlightedText:colours.backgroundA
    onClosing:function(event){event.accepted=studio.requestClose()}
    background:Canvas {
        id:backdrop
        onWidthChanged:requestPaint();onHeightChanged:requestPaint()
        Connections{target:studio;function onChanged(){backdrop.requestPaint()}}
        onPaint:{var c=getContext("2d"),p=window.colours;c.clearRect(0,0,width,height);var base=c.createLinearGradient(0,0,width,height);base.addColorStop(0,p.backgroundA);base.addColorStop(.5,p.backgroundB);base.addColorStop(1,p.backgroundC);c.fillStyle=base;c.fillRect(0,0,width,height);var fields=[[width,0,20,620,p.glowA,.25],[0,height,40,720,p.glowB,.20],[width/2,height/2,120,900,p.glassHighlight,.55]];for(var i=0;i<fields.length;i++){var f=fields[i],colour=Qt.tint("transparent",f[4]),g=c.createRadialGradient(f[0],f[1],f[2],f[0],f[1],f[3]);g.addColorStop(0,Qt.rgba(colour.r,colour.g,colour.b,colour.a*f[5]));g.addColorStop(1,"transparent");c.fillStyle=g;c.fillRect(0,0,width,height)}}
    }
    menuBar:MenuBar {
        Menu{title:"File";MenuItem{text:"New Project";onTriggered:studio.command("new",{})}MenuItem{text:"Open Project…";onTriggered:studio.command("open",{})}MenuItem{text:"Save";onTriggered:studio.command("save",{})}MenuItem{text:"Save As…";onTriggered:studio.command("save",{asNew:true})}MenuSeparator{}MenuItem{text:"Import Audio…";onTriggered:studio.command("importAudio",{})}MenuItem{text:"Recover Recording…";onTriggered:studio.command("recoverRecording",{})}MenuItem{text:"Export WAV…";onTriggered:studio.command("export",{})}}
        Menu{title:"Edit";MenuItem{text:"Undo";enabled:stateData.canUndo;onTriggered:studio.command("undo",{})}MenuItem{text:"Redo";enabled:stateData.canRedo;onTriggered:studio.command("redo",{})}MenuItem{text:"Duplicate Clip";enabled:!!stateData.clip.id;onTriggered:studio.command("duplicateClip",{})}MenuItem{text:"Delete Clip";enabled:!!stateData.clip.id;onTriggered:studio.command("deleteClip",{})}MenuItem{text:"Split Clip at Playhead";enabled:!!stateData.clip.id;onTriggered:studio.command("splitClip",{})}MenuItem{text:"Duplicate Track";enabled:!!stateData.selected.id;onTriggered:studio.command("duplicateTrack",{})}MenuItem{text:"Group Selected Tracks";onTriggered:studio.command("group",{})}}
        Menu{id:trackMenu;title:"Track";MenuItem{text:stateData.selected.frozen ? "Unfreeze Track" : "Freeze Track";enabled:!!stateData.selected.id;onTriggered:studio.command(stateData.selected.frozen ? "unfreeze" : "freeze",{})}MenuSeparator{}Instantiator{model:stateData.trackKinds;delegate:MenuItem{required property string modelData;text:"Add "+modelData;onTriggered:studio.command("addTrack",{kind:modelData})}onObjectAdded:function(index,object){trackMenu.insertItem(index,object)}onObjectRemoved:function(index,object){trackMenu.removeItem(object)}}}
        Menu{id:viewMenu;title:"View";MenuItem{text:"Browser";onTriggered:leftDrawer.open()}MenuItem{text:"Right Dock";onTriggered:rightDrawer.open()}MenuItem{text:"Detail Deck";checkable:true;checked:showDetails;onTriggered:showDetails=!showDetails}MenuSeparator{}Instantiator{model:stateData.workspaces;delegate:MenuItem{required property string modelData;text:modelData;onTriggered:studio.command("workspace",{value:modelData})}onObjectAdded:function(index,object){viewMenu.insertItem(index,object)}onObjectRemoved:function(index,object){viewMenu.removeItem(object)}}}
        Menu{id:themeMenu;title:"Theme";Instantiator{model:stateData.themes;delegate:MenuItem{required property string modelData;text:modelData;checkable:true;checked:stateData.theme===modelData;onTriggered:studio.command("theme",{value:modelData})}onObjectAdded:function(index,object){themeMenu.insertItem(index,object)}onObjectRemoved:function(index,object){themeMenu.removeItem(object)}}}
    }
    function editingText(){return activeFocusItem && activeFocusItem.cursorPosition!==undefined}
    Shortcut{sequences:[StandardKey.Save];onActivated:studio.command("save",{})}
    Shortcut{sequences:[StandardKey.Open];onActivated:studio.command("open",{})}
    Shortcut{sequences:[StandardKey.New];onActivated:studio.command("new",{})}
    Shortcut{sequences:[StandardKey.Undo];enabled:!window.editingText();onActivated:studio.command("undo",{})}
    Shortcut{sequences:[StandardKey.Redo];enabled:!window.editingText();onActivated:studio.command("redo",{})}
    Shortcut{sequence:"Space";enabled:!window.editingText();onActivated:studio.command("play",{})}
    Shortcut{sequence:"Delete";enabled:!window.editingText();onActivated:studio.command(stateData.selectedNote ? "deleteNote" : "deleteClip",{})}
    Shortcut{sequence:Qt.platform.os==="osx" ? "Meta+D" : "Ctrl+D";enabled:!window.editingText();onActivated:studio.command("duplicateClip",{})}
    Shortcut{sequence:"Ctrl+Tab";onActivated:studio.command("workspace",{value:stateData.workspaces[(stateData.workspaces.indexOf(stateData.workspace)+1)%7]})}
    Drawer{id:leftDrawer;objectName:"browserDrawer";edge:Qt.LeftEdge;width:Math.min(330,window.width-30);height:window.height;BrowserPane{anchors.fill:parent;anchors.margins:12}}
    Drawer{id:rightDrawer;objectName:"dockDrawer";edge:Qt.RightEdge;width:Math.min(420,window.width-30);height:window.height;DockPane{anchors.fill:parent;anchors.margins:12}}
    ColumnLayout {
        anchors.fill:parent;spacing:0
        ScrollView {
            Layout.fillWidth:true;Layout.preferredHeight:66;clip:true;contentWidth:transportRow.implicitWidth;contentHeight:58
            RowLayout {
                id:transportRow;height:58;spacing:7
                Column{Layout.preferredWidth:158;leftPadding:12;Label{text:"LemmingsStudio";font.bold:true;font.pixelSize:13}Label{text:"creative DAW · "+(stateData.glyph||"");font.pixelSize:8;color:colours.dim}}
                LSButton{objectName:"openBrowser";text:"Browser";onClicked:leftDrawer.open()}
                LSButton{objectName:"openInspector";text:"Inspect";onClicked:{studio.command("dock",{value:"Inspect"});rightDrawer.open()}}
                LSButton{text:studio && studio.transport.playing ? "Ⅱ" : "▶";accent:colours.play;selected:studio && studio.transport.playing;onClicked:studio.command("play",{})}
                LSButton{text:"■";onClicked:studio.command("stop",{})}
                LSButton{text:"|◀";onClicked:studio.command("return",{})}
                LSButton{objectName:"recordButton";text:stateData.recordState!=="idle" ? "■ REC" : "●";accent:colours.record;selected:stateData.recordState!=="idle";enabled:!!stateData.nativeInputAvailable && !stateData.busy;onClicked:studio.command("record",{});ToolTip.visible:hovered;ToolTip.text:"Dry recording · select an armed audio track. Monitoring and overdubbing are not enabled."}
                LSButton{objectName:"inputDeviceButton";text:"Input";enabled:!!stateData.nativeInputAvailable && stateData.recordState==="idle" && !stateData.busy;onClicked:studio.command("inputDevice",{});ToolTip.visible:hovered;ToolTip.text:stateData.inputName||"Recording input"}
                Label{visible:stateData.recordState!=="idle";text:Number(stateData.recordSeconds||0).toFixed(1)+" s · "+(Number(stateData.inputPeak||0)>=1 ? "CLIP" : Math.round(Number(stateData.inputPeak||0)*100)+"%");color:colours.record;font.pixelSize:10}
                LSButton{text:"♩";selected:!!stateData.metronome;onClicked:studio.command("metronome",{});ToolTip.visible:hovered;ToolTip.text:"Metronome"}
                LSButton{text:"1·2";enabled:false;ToolTip.visible:hovered;ToolTip.text:"Count-in awaits the recording engine."}
                Column{Layout.preferredWidth:95;Label{text:"POSITION";font.pixelSize:8;color:colours.dim}Label{text:studio ? studio.transport.position : "1:1:000";font.pixelSize:12}}
                Column{Layout.preferredWidth:75;Label{text:"TIME";font.pixelSize:8;color:colours.dim}Label{text:studio ? studio.transport.time : "0.00 s";font.pixelSize:12}}
                Label{text:"BPM";font.pixelSize:10;color:colours.dim}
                LSTextField{Layout.preferredWidth:65;text:Number(stateData.tempo||124).toFixed(1);selectByMouse:true;onEditingFinished:studio.command("tempo",{value:Number(text)})}
                LSButton{text:"Tap";onClicked:studio.command("tap",{})}
                LSComboBox{model:["C","C♯","D","E♭","E","F","F♯","G","A♭","A","B♭","B"];Layout.preferredWidth:64;currentIndex:stateData.keyRoot||0;onActivated:studio.command("key",{root:currentIndex,scale:stateData.scale})}
                LSComboBox{model:stateData.scales;Layout.preferredWidth:132;currentIndex:Math.max(0,model.indexOf(stateData.scale));onActivated:studio.command("key",{root:stateData.keyRoot,scale:currentText})}
                LSButton{text:"Export";onClicked:studio.command("export",{})}
            }
        }
        SplitView {
            objectName:"workspaceSplit"
            Layout.fillWidth:true;Layout.fillHeight:true;Layout.margins:8;orientation:Qt.Horizontal
            handle:Rectangle{implicitWidth:8;implicitHeight:8;color:"transparent";Rectangle{anchors.centerIn:parent;width:1;height:parent.height;color:SplitHandle.hovered ? colours.focus : "transparent"}}
            GlassPanel{objectName:"inlineBrowser";visible:window.browserInline;SplitView.preferredWidth:310;SplitView.minimumWidth:265;SplitView.maximumWidth:390;BrowserPane{anchors.fill:parent;anchors.margins:4}}
            GlassPanel {
                SplitView.fillWidth:true;SplitView.minimumWidth:420
                ColumnLayout {
                    anchors.fill:parent;anchors.margins:5;spacing:1
                    ScrollView{Layout.fillWidth:true;Layout.preferredHeight:42;contentWidth:tabs.implicitWidth;clip:true;Row{id:tabs;spacing:3;Repeater{model:stateData.workspaces;LSButton{required property string modelData;objectName:"workspaceTab-"+modelData;text:modelData;selected:stateData.workspace===modelData;onClicked:studio.command("workspace",{value:modelData})}}}}
                    SplitView {
                        Layout.fillWidth:true;Layout.fillHeight:true;orientation:Qt.Vertical
                        Loader {
                            id:page
                            objectName:"workspacePage"
                            readonly property bool ready:status===Loader.Ready
                            SplitView.fillHeight:true;SplitView.minimumHeight:200
                            property bool pianoMode:stateData.workspace==="Piano Roll"
                            onPianoModeChanged:if(item && item.piano!==undefined)item.piano=pianoMode
                            onLoaded:if(item && item.piano!==undefined)item.piano=pianoMode
                            source:({Session:"SessionPane.qml",Arrangement:"TimelinePane.qml","Piano Roll":"TimelinePane.qml","Step Sequencer":"SequencerPane.qml",Devices:"DevicePane.qml",Automation:"AutomationPane.qml",Mixer:"MixerPane.qml"})[stateData.workspace]||"TimelinePane.qml"
                        }
                        DetailPane {visible:showDetails && window.height>=620;SplitView.preferredHeight:220;SplitView.minimumHeight:130;SplitView.maximumHeight:330}
                    }
                }
            }
            GlassPanel{objectName:"inlineDock";visible:window.wide;SplitView.preferredWidth:405;SplitView.minimumWidth:350;SplitView.maximumWidth:520;DockPane{anchors.fill:parent;anchors.margins:10}}
        }
        RowLayout {
            Layout.fillWidth:true;Layout.margins:6;spacing:8
            LSButton{text:"↶ Undo";enabled:stateData.canUndo;onClicked:studio.command("undo",{})}
            LSButton{text:"↷ Redo";enabled:stateData.canRedo;onClicked:studio.command("redo",{})}
            Label{text:stateData.status;Layout.fillWidth:true;elide:Text.ElideRight;color:colours.dim;font.pixelSize:11;ToolTip.visible:statusHover.hovered;ToolTip.text:stateData.status;HoverHandler{id:statusHover}}
            BusyIndicator{running:!!stateData.busy;visible:running;Layout.preferredWidth:22;Layout.preferredHeight:22}
            LSButton{text:"Cancel";visible:!!stateData.busy;onClicked:studio.command("cancel",{})}
        }
    }
}
