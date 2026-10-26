import QtQuick
import QtQuick.Controls.Basic
Button {
    id: button
    property bool selected: false
    property color accent: colors.focus
    readonly property var colors: studio ? studio.palette : ({text:"white",dim:"#aaaaaa",focus:"#75dbff",panel2:"#333344",glassStroke:"#444455"})
    padding:4
    implicitHeight: 30
    implicitWidth: Math.max(32, caption.implicitWidth + 20)
    hoverEnabled: true
    contentItem: Text { id: caption; text: button.text; color: !button.enabled ? button.colors.dim : button.selected ? button.accent : button.colors.text; font: button.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    background: Rectangle { radius: 6; color: button.selected || button.down ? button.colors.panel2 : button.hovered ? button.colors.panel2 : "transparent"; border.width: button.activeFocus ? 2 : 0.8; border.color: button.activeFocus || button.selected ? button.accent : button.colors.glassStroke; opacity: button.enabled ? 1 : 0.5 }
}
