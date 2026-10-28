import QtQuick
Item {
    id:editor
    property var points:[]
    property var tracks:[]
    property real lengthBeats:128
    property real minimum:0
    property real maximum:1
    property bool logarithmic:false
    property string valueKey:"value"
    property int selected:-1
    signal edited(int index,real beat,real value)
    signal removed(int index)
    implicitHeight:110
    function normalize(v){return Math.max(0,Math.min(1,logarithmic && minimum>0 ? Math.log(v/minimum)/Math.log(maximum/minimum) : (v-minimum)/Math.max(0.00001,maximum-minimum)))}
    function denormalize(v){return logarithmic && minimum>0 ? minimum*Math.pow(maximum/minimum,v) : minimum+v*(maximum-minimum)}
    function nearest(x,y){var best=-1,dist=12;for(var i=0;i<points.length;i++){var dx=x-points[i].beat/lengthBeats*width,dy=y-(1-normalize(points[i][valueKey]))*height,d=Math.sqrt(dx*dx+dy*dy);if(d<dist){best=i;dist=d}}return best}
    Rectangle{anchors.fill:parent;color:"#28000000";radius:6}
    Canvas {
        id:canvas;anchors.fill:parent
        onWidthChanged:requestPaint();onHeightChanged:requestPaint()
        Connections{target:editor;function onPointsChanged(){canvas.requestPaint()}function onTracksChanged(){canvas.requestPaint()}function onMinimumChanged(){canvas.requestPaint()}function onMaximumChanged(){canvas.requestPaint()}function onSelectedChanged(){canvas.requestPaint()}}
        Connections{target:studio;function onChanged(){canvas.requestPaint()}}
        onPaint:{
            var c=getContext("2d");c.clearRect(0,0,width,height)
            for(var t=0;t<editor.tracks.length;t++){var track=editor.tracks[t];c.fillStyle=track.color||"#33448866";c.globalAlpha=.16;var clips=track.clips||[];for(var k=0;k<clips.length;k++){var clip=clips[k],x=clip.startBeat/editor.lengthBeats*width,w=clip.lengthBeats/editor.lengthBeats*width;c.fillRect(x,3,w,height-6);var notes=clip.notes||[];for(var n=0;n<notes.length;n++){c.fillRect(x+notes[n].start/editor.lengthBeats*width,height*(1-notes[n].pitch/128),Math.max(2,notes[n].length/editor.lengthBeats*width),2)}}}c.globalAlpha=1
            c.strokeStyle=studio.palette.grid;c.lineWidth=1;var stride=Math.max(1,Math.ceil(editor.lengthBeats/32));for(var b=0;b<=editor.lengthBeats;b+=stride){var gx=b/editor.lengthBeats*width;c.beginPath();c.moveTo(gx,0);c.lineTo(gx,height);c.stroke()}
            c.strokeStyle=studio.palette.focus;c.lineWidth=2.25;c.beginPath();for(var i=0;i<editor.points.length;i++){var p=editor.points[i],px=p.beat/editor.lengthBeats*width,py=(1-editor.normalize(p[editor.valueKey]))*height;if(i===0)c.moveTo(px,py);else c.lineTo(px,py)}c.stroke()
            for(var j=0;j<editor.points.length;j++){c.fillStyle=j===editor.selected ? studio.palette.text : studio.palette.focus;c.beginPath();c.arc(editor.points[j].beat/editor.lengthBeats*width,(1-editor.normalize(editor.points[j][editor.valueKey]))*height,j===editor.selected ? 5 : 4,0,Math.PI*2);c.fill()}
            c.fillStyle=studio.palette.dim;c.font="9px sans-serif";c.fillText(editor.maximum.toString(),4,12);c.fillText(editor.minimum.toString(),4,height-4)
        }
    }
    MouseArea {
        anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton
        property int pointIndex:-1
        property real pressX:0;property real pressY:0
        onPressed:function(mouse){pointIndex=editor.nearest(mouse.x,mouse.y);editor.selected=pointIndex;pressX=mouse.x;pressY=mouse.y}
        onReleased:function(mouse){if(mouse.button===Qt.RightButton){if(pointIndex>=0)editor.removed(pointIndex);return}if(pointIndex>=0 && Math.abs(mouse.x-pressX)+Math.abs(mouse.y-pressY)<4)return;editor.edited(pointIndex,Math.max(0,Math.min(editor.lengthBeats,mouse.x/width*editor.lengthBeats)),editor.denormalize(Math.max(0,Math.min(1,1-mouse.y/height))))}
    }
}
