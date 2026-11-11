// Small dependency-free icon set drawn with Qt Canvas.
//
// Keeping the icons vector-drawn avoids shipping a 14 MB icon font and keeps
// the shell usable in a minimal QEMU guest. Every stroke/fill uses `color`, so
// a theme change repaints with the palette's guarded foreground token.

import QtQuick

Item {
    id: root

    property string name: "apps"
    property color color: "#201a18"
    property real level: 1.0
    property real strokeWidth: 1.9

    implicitWidth: 24
    implicitHeight: 24

    function _paintColor() {
        return root.color.toString();
    }

    function _roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + w - r, y);
        ctx.quadraticCurveTo(x + w, y, x + w, y + r);
        ctx.lineTo(x + w, y + h - r);
        ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        ctx.lineTo(x + r, y + h);
        ctx.quadraticCurveTo(x, y + h, x, y + h - r);
        ctx.lineTo(x, y + r);
        ctx.quadraticCurveTo(x, y, x + r, y);
        ctx.closePath();
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            const scale = Math.min(width, height) / 24;
            ctx.save();
            ctx.scale(scale, scale);
            ctx.strokeStyle = root._paintColor();
            ctx.fillStyle = root._paintColor();
            ctx.lineWidth = root.strokeWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            if (root.name === "wifi") {
                for (const radius of [8.5, 5.7, 2.9]) {
                    ctx.beginPath();
                    ctx.arc(12, 18, radius, Math.PI * 1.20, Math.PI * 1.80);
                    ctx.stroke();
                }
                ctx.beginPath();
                ctx.arc(12, 18, 1.1, 0, Math.PI * 2);
                ctx.fill();
            } else if (root.name === "wifi_off") {
                ctx.beginPath();
                ctx.arc(12, 18, 8.5, Math.PI * 1.20, Math.PI * 1.80);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 18, 5.7, Math.PI * 1.20, Math.PI * 1.80);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 18, 1.1, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(6, 4);
                ctx.lineTo(18, 20);
                ctx.stroke();
            } else if (root.name === "battery") {
                const pct = Math.max(0, Math.min(1, root.level));
                root._roundRect(ctx, 2.5, 7, 17, 10, 2.5);
                ctx.stroke();
                root._roundRect(ctx, 20.2, 9.8, 2.0, 4.4, 1);
                ctx.fill();
                if (pct > 0.01) {
                    const fillWidth = Math.max(1.5, 13.5 * pct);
                    root._roundRect(ctx, 4.2, 8.7, fillWidth, 6.6, 1.4);
                    ctx.fill();
                }
            } else if (root.name === "bell" || root.name === "notifications") {
                ctx.beginPath();
                ctx.moveTo(5, 17.2);
                ctx.lineTo(7, 14.8);
                ctx.lineTo(7, 11.2);
                ctx.bezierCurveTo(7, 7.4, 9.1, 5.8, 12, 5.8);
                ctx.bezierCurveTo(14.9, 5.8, 17, 7.4, 17, 11.2);
                ctx.lineTo(17, 14.8);
                ctx.lineTo(19, 17.2);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(10, 19.2);
                ctx.quadraticCurveTo(12, 21.1, 14, 19.2);
                ctx.stroke();
            } else if (root.name === "grid") {
                for (let row = 0; row < 3; ++row) {
                    for (let col = 0; col < 3; ++col) {
                        root._roundRect(ctx, 4.5 + col * 5.5, 4.5 + row * 5.5, 3.3, 3.3, 0.9);
                        ctx.fill();
                    }
                }
            } else if (root.name === "apps") {
                for (let row = 0; row < 2; ++row) {
                    for (let col = 0; col < 2; ++col) {
                        root._roundRect(ctx, 4 + col * 9, 4 + row * 9, 7, 7, 2);
                        ctx.stroke();
                    }
                }
            } else if (root.name === "lock" || root.name === "unlock") {
                root._roundRect(ctx, 5, 10.8, 14, 9.4, 2.2);
                ctx.stroke();
                ctx.beginPath();
                if (root.name === "lock")
                    ctx.arc(12, 10.8, 4.8, Math.PI, Math.PI * 2);
                else
                    ctx.arc(12, 10.8, 4.8, Math.PI, Math.PI * 1.82);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 15.2, 1.2, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(12, 16.2);
                ctx.lineTo(12, 18.0);
                ctx.stroke();
            } else if (root.name === "close") {
                ctx.beginPath();
                ctx.moveTo(6, 6);
                ctx.lineTo(18, 18);
                ctx.moveTo(18, 6);
                ctx.lineTo(6, 18);
                ctx.stroke();
            } else if (root.name === "back") {
                ctx.beginPath();
                ctx.moveTo(14.5, 5);
                ctx.lineTo(7.5, 12);
                ctx.lineTo(14.5, 19);
                ctx.stroke();
            } else if (root.name === "chevron_right") {
                ctx.beginPath();
                ctx.moveTo(9, 5);
                ctx.lineTo(16, 12);
                ctx.lineTo(9, 19);
                ctx.stroke();
            } else if (root.name === "search") {
                ctx.beginPath();
                ctx.arc(10.5, 10.5, 5.6, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(14.8, 14.8);
                ctx.lineTo(19.5, 19.5);
                ctx.stroke();
            } else if (root.name === "check") {
                ctx.beginPath();
                ctx.moveTo(4.5, 12.5);
                ctx.lineTo(9.7, 17.5);
                ctx.lineTo(19.5, 6.5);
                ctx.stroke();
            } else if (root.name === "backspace") {
                ctx.beginPath();
                ctx.moveTo(8.5, 5);
                ctx.lineTo(20.5, 5);
                ctx.lineTo(16.5, 12);
                ctx.lineTo(20.5, 19);
                ctx.lineTo(8.5, 19);
                ctx.lineTo(3.2, 12);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(9.5, 9);
                ctx.lineTo(15, 15);
                ctx.moveTo(15, 9);
                ctx.lineTo(9.5, 15);
                ctx.stroke();
            } else if (root.name === "power") {
                ctx.beginPath();
                ctx.arc(12, 12.6, 7.2, Math.PI * 1.25, Math.PI * 1.75, true);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(12, 3.5);
                ctx.lineTo(12, 11);
                ctx.stroke();
            } else if (root.name === "moon") {
                ctx.beginPath();
                ctx.arc(12.5, 12, 7.4, Math.PI * 0.42, Math.PI * 1.58);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(16.6, 9.6, 6.4, Math.PI * 0.55, Math.PI * 1.45);
                ctx.stroke();
            } else if (root.name === "sun" || root.name === "brightness") {
                ctx.beginPath();
                ctx.arc(12, 12, 4.2, 0, Math.PI * 2);
                ctx.stroke();
                for (let i = 0; i < 8; ++i) {
                    const angle = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(12 + Math.cos(angle) * 6.6, 12 + Math.sin(angle) * 6.6);
                    ctx.lineTo(12 + Math.cos(angle) * 9.2, 12 + Math.sin(angle) * 9.2);
                    ctx.stroke();
                }
            } else if (root.name === "settings") {
                ctx.beginPath();
                ctx.arc(12, 12, 3.4, 0, Math.PI * 2);
                ctx.stroke();
                for (let i = 0; i < 8; ++i) {
                    const angle = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(12 + Math.cos(angle) * 6.2, 12 + Math.sin(angle) * 6.2);
                    ctx.lineTo(12 + Math.cos(angle) * 8.6, 12 + Math.sin(angle) * 8.6);
                    ctx.stroke();
                }
            } else if (root.name === "home") {
                ctx.beginPath();
                ctx.moveTo(3.5, 11);
                ctx.lineTo(12, 3.5);
                ctx.lineTo(20.5, 11);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(6, 10.5);
                ctx.lineTo(6, 20);
                ctx.lineTo(18, 20);
                ctx.lineTo(18, 10.5);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(10, 20);
                ctx.lineTo(10, 14.5);
                ctx.lineTo(14, 14.5);
                ctx.lineTo(14, 20);
                ctx.stroke();
            } else if (root.name === "volume") {
                ctx.beginPath();
                ctx.moveTo(4, 9.5);
                ctx.lineTo(8, 9.5);
                ctx.lineTo(12.5, 5.5);
                ctx.lineTo(12.5, 18.5);
                ctx.lineTo(8, 14.5);
                ctx.lineTo(4, 14.5);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(14.5, 12, 4.6, -Math.PI * 0.45, Math.PI * 0.45);
                ctx.stroke();
            } else if (root.name === "dots") {
                for (const x of [6, 12, 18]) {
                    ctx.beginPath();
                    ctx.arc(x, 12, 1.5, 0, Math.PI * 2);
                    ctx.fill();
                }
            } else if (root.name === "person") {
                ctx.beginPath();
                ctx.arc(12, 8, 3.6, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 21.5, 7.2, Math.PI * 1.15, Math.PI * 1.85);
                ctx.stroke();
            } else if (root.name === "warning") {
                ctx.beginPath();
                ctx.moveTo(12, 3.2);
                ctx.lineTo(21.2, 20.2);
                ctx.lineTo(2.8, 20.2);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(12, 8.2);
                ctx.lineTo(12, 14.2);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 17.2, 1.05, 0, Math.PI * 2);
                ctx.fill();
            } else if (root.name === "bolt") {
                ctx.beginPath();
                ctx.moveTo(13, 2.5);
                ctx.lineTo(5.5, 13.5);
                ctx.lineTo(11.2, 13.5);
                ctx.lineTo(10, 21.5);
                ctx.lineTo(18.5, 10.2);
                ctx.lineTo(12.7, 10.2);
                ctx.closePath();
                ctx.fill();
            } else if (root.name === "phone") {
                ctx.beginPath();
                ctx.moveTo(6.2, 3.8);
                ctx.lineTo(9.8, 5.2);
                ctx.lineTo(9.2, 8.2);
                ctx.quadraticCurveTo(11.6, 12.8, 15.8, 14.8);
                ctx.lineTo(18.8, 14.2);
                ctx.lineTo(20.2, 17.8);
                ctx.quadraticCurveTo(17.8, 20.6, 13.8, 19.4);
                ctx.quadraticCurveTo(7.6, 17.2, 4.6, 11.0);
                ctx.quadraticCurveTo(3.4, 7.0, 6.2, 3.8);
                ctx.closePath();
                ctx.stroke();
            } else if (root.name === "message") {
                root._roundRect(ctx, 3.5, 4.5, 17, 12.5, 4);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(8.0, 17.0);
                ctx.lineTo(8.0, 21.0);
                ctx.lineTo(12.5, 17.0);
                ctx.stroke();
                for (const x of [8.5, 12.0, 15.5]) {
                    ctx.beginPath();
                    ctx.arc(x, 10.7, 1.05, 0, Math.PI * 2);
                    ctx.fill();
                }
            } else if (root.name === "send") {
                ctx.beginPath();
                ctx.moveTo(3.2, 11.5);
                ctx.lineTo(21.0, 3.5);
                ctx.lineTo(14.3, 20.5);
                ctx.lineTo(11.4, 13.6);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(11.4, 13.6);
                ctx.lineTo(21.0, 3.5);
                ctx.stroke();
            } else if (root.name === "signal") {
                const filled = root.level >= 0
                    ? Math.max(0, Math.min(4, Math.ceil(root.level * 4))) : 0;
                for (let i = 0; i < 4; ++i) {
                    const x = 4.0 + i * 4.6;
                    const height = 4.0 + i * 3.4;
                    root._roundRect(ctx, x, 20.0 - height, 3.0, height, 0.9);
                    if (i < filled)
                        ctx.fill();
                    else
                        ctx.stroke();
                }
            } else if (root.name === "delete") {
                ctx.beginPath();
                ctx.moveTo(5.0, 7.0);
                ctx.lineTo(19.0, 7.0);
                ctx.moveTo(9.0, 7.0);
                ctx.lineTo(9.0, 4.0);
                ctx.lineTo(15.0, 4.0);
                ctx.lineTo(15.0, 7.0);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(6.5, 7.0);
                ctx.lineTo(7.5, 20.0);
                ctx.lineTo(16.5, 20.0);
                ctx.lineTo(17.5, 7.0);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(10.5, 10.0);
                ctx.lineTo(11.0, 17.0);
                ctx.moveTo(13.5, 10.0);
                ctx.lineTo(13.0, 17.0);
                ctx.stroke();
            } else if (root.name === "arrow_up") {
                ctx.beginPath();
                ctx.moveTo(12, 20);
                ctx.lineTo(12, 4.5);
                ctx.moveTo(5.5, 11);
                ctx.lineTo(12, 4.5);
                ctx.lineTo(18.5, 11);
                ctx.stroke();
            } else if (root.name === "camera") {
                root._roundRect(ctx, 3.5, 7.0, 17.0, 12.5, 3.0);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(8.5, 7.0);
                ctx.lineTo(9.8, 4.5);
                ctx.lineTo(14.2, 4.5);
                ctx.lineTo(15.5, 7.0);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(12, 13.2, 3.7, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(17.7, 9.8, 0.9, 0, Math.PI * 2);
                ctx.fill();
            } else if (root.name === "image") {
                root._roundRect(ctx, 3.5, 4.5, 17.0, 15.0, 3.0);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(8.5, 9.5, 1.6, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.moveTo(4.5, 17.5);
                ctx.lineTo(9.5, 12.5);
                ctx.lineTo(13.0, 16.0);
                ctx.lineTo(15.5, 13.5);
                ctx.lineTo(19.5, 17.5);
                ctx.stroke();
            } else {
                // Unknown icon: a hollow dot is a deliberate, visible fallback.
                ctx.beginPath();
                ctx.arc(12, 12, 6.5, 0, Math.PI * 2);
                ctx.stroke();
            }

            ctx.restore();
        }
    }

    onNameChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onLevelChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
