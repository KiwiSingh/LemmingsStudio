import QtQuick
import QtQuick.Controls.Basic
TextField {
    id:control
    readonly property var colours:studio ? studio.palette : ({focus:"#8bcaff",panel:"#252732",text:"#eeeeee",dim:"#aaaaaa",glassStroke:"#50545f"})
    implicitHeight:30
    padding:7
    color:colours.text;placeholderTextColor:colours.dim;selectionColor:colours.focus
    background:Rectangle{radius:6;color:control.colours.panel;border.width:control.activeFocus ? 1.5 : .8;border.color:control.activeFocus ? control.colours.focus : control.colours.glassStroke}
}
