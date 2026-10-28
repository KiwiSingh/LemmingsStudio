import QtQuick
import QtQuick.Controls.Basic
Slider {
    id:control
    readonly property var colours:studio ? studio.palette : ({focus:"#8bcaff",grid:"#334455",text:"#eeeeee"})
    implicitWidth:orientation===Qt.Horizontal ? 140 : 24
    implicitHeight:orientation===Qt.Horizontal ? 24 : 160
    padding:4
    background:Rectangle {
        x:control.leftPadding+(control.orientation===Qt.Horizontal ? 0 : (control.availableWidth-width)/2)
        y:control.topPadding+(control.orientation===Qt.Horizontal ? (control.availableHeight-height)/2 : 0)
        width:control.orientation===Qt.Horizontal ? control.availableWidth : 4
        height:control.orientation===Qt.Horizontal ? 4 : control.availableHeight
        radius:2;color:control.colours.grid
        Rectangle{width:control.orientation===Qt.Horizontal ? parent.width*control.position : parent.width;height:control.orientation===Qt.Horizontal ? parent.height : parent.height*control.position;y:control.orientation===Qt.Horizontal ? 0 : parent.height-height;radius:2;color:control.colours.focus;opacity:control.enabled ? .8 : .3}
    }
    handle:Rectangle {
        x:control.leftPadding+(control.orientation===Qt.Horizontal ? control.visualPosition*(control.availableWidth-width) : (control.availableWidth-width)/2)
        y:control.topPadding+(control.orientation===Qt.Horizontal ? (control.availableHeight-height)/2 : control.visualPosition*(control.availableHeight-height))
        width:control.orientation===Qt.Horizontal ? 15 : 24;height:control.orientation===Qt.Horizontal ? 15 : 12
        radius:control.orientation===Qt.Horizontal ? 8 : 3
        color:control.pressed ? control.colours.focus : "#e3e5eb"
        border.width:control.activeFocus ? 2 : 1;border.color:control.activeFocus ? control.colours.focus : "#707781"
        Rectangle{visible:control.orientation===Qt.Vertical;anchors.centerIn:parent;width:14;height:1;color:"#7c828b"}
    }
}
