import QtQuick
import QtQuick.Controls.Basic
ComboBox {
    id:control
    readonly property var colours:studio ? studio.palette : ({focus:"#8bcaff",panel2:"#252732",text:"#eeeeee",glassStroke:"#50545f"})
    implicitHeight:30
    padding:6;rightPadding:24
    font.pixelSize:11
    contentItem:Text{text:control.displayText;font:control.font;color:control.colours.text;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight}
    indicator:Canvas{x:control.width-width-8;y:(control.height-height)/2;width:9;height:5;onPaint:{var c=getContext("2d");c.clearRect(0,0,width,height);c.strokeStyle=control.colours.text;c.lineWidth=1.4;c.beginPath();c.moveTo(0,0);c.lineTo(width/2,height);c.lineTo(width,0);c.stroke()}}
    background:Rectangle{radius:6;color:control.colours.panel2;border.color:control.activeFocus ? control.colours.focus : control.colours.glassStroke;border.width:control.activeFocus ? 1.5 : .8}
}
