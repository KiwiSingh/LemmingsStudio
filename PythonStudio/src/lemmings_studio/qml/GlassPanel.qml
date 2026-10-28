import QtQuick
Rectangle {
    readonly property var colors: studio ? studio.palette : ({panel:"#20202e",panel2:"#303042",glassStroke:"#444455"})
    radius: 18
    gradient: Gradient { GradientStop { position: 0; color: colors.panel2 } GradientStop { position: 1; color: colors.panel } }
    border.color: colors.glassStroke
    border.width: 0.8
}
