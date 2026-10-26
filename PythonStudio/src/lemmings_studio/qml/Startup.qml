import QtQuick
import QtQuick.Window

Window {
    id: panel
    readonly property var presentation: startup || ({stage: "splash", frameNumber: 0,
        displayScale: 1, artworkUrl: "", statusText: ""})
    objectName: "startupPanel"
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.Tool | Qt.WindowStaysOnTopHint
    title: panel.presentation.stage === "video" ? "MagmaVance" : "LemmingsStudio"
    width: Math.round(canvas.width * panel.presentation.displayScale)
    height: Math.round(canvas.height * panel.presentation.displayScale)
    Item {
        id: canvas
        anchors.centerIn: parent
        width: panel.presentation.stage === "video" ? 360 : 460
        height: panel.presentation.stage === "video" ? 640 : 548
        scale: panel.presentation.displayScale
        Rectangle {
            anchors.fill: parent
            radius: panel.presentation.stage === "video" ? 30 : 28
            color: panel.presentation.stage === "video" ? "#db000000" : "#c7000000"
            border.color: "#29ffffff"
            border.width: 1
        }
        Image {
            objectName: "magmaVideo"
            visible: panel.presentation.stage === "video"
            anchors.fill: parent
            anchors.margins: 10
            source: panel.presentation.frameNumber > 0 ? "image://magma/frame/" + panel.presentation.frameNumber : ""
            cache: false
            fillMode: Image.PreserveAspectCrop
            clip: true
        }
        Item {
            visible: panel.presentation.stage !== "video"
            anchors.fill: parent
            Image {
                objectName: "lemmingsArtwork"
                x: 70; y: 28; width: 320; height: 320
                source: panel.presentation.artworkUrl
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                x: 28; y: 362; width: 404; height: 40
                text: "LemmingsStudio"
                color: "white"; font.pixelSize: 30; font.weight: Font.Black
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                x: 28; y: 416; width: 404
                text: panel.presentation.statusText
                color: "#a6ffffff"; font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }
            Item {
                x: 220; y: 449; width: 20; height: 20
                Repeater {
                    model: 8
                    Rectangle {
                        width: 3; height: 5; radius: 1.5
                        x: 9 + Math.sin(index * Math.PI / 4) * 7
                        y: 8 - Math.cos(index * Math.PI / 4) * 7
                        color: "white"; opacity: (index + 1) / 8
                    }
                }
                RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: true }
            }
            Text {
                x: 28; y: 489; width: 404
                text: "© MagmaVance LLC. All rights reserved."
                color: "#94ffffff"; font.pixelSize: 10; font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
