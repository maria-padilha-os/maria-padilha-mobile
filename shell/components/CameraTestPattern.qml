// Deterministic generated preview used when no camera is available.
//
// This is deliberately not a bundled photograph. Colour bars, a checkerboard,
// a centre reticle and a border make it obvious that the surface is showing a
// test pattern. The camera surface labels it as generated; the bridge can
// write the same pattern to a runtime PNG for the automated tests.

import QtQuick

Item {
    id: root

    property color borderColor: "#201a18"

    Canvas {
        id: pattern
        anchors.fill: parent
        antialiasing: false
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            const w = width;
            const h = height;
            ctx.reset();
            ctx.clearRect(0, 0, w, h);

            const bars = [
                "#ebebeb", "#ebeb20", "#20ebeb", "#20eb20",
                "#eb20eb", "#eb2020", "#2020eb"
            ];
            const split = Math.round(h * 0.60);
            for (let i = 0; i < bars.length; ++i) {
                const x = Math.floor(w * i / bars.length);
                const right = Math.floor(w * (i + 1) / bars.length);
                ctx.fillStyle = bars[i];
                ctx.fillRect(x, 0, right - x, split);
            }

            ctx.fillStyle = "#262626";
            ctx.fillRect(0, split, w, h - split);
            const size = Math.max(8, Math.floor(Math.min(w, h) / 16));
            ctx.fillStyle = "#b0b0b0";
            for (let y = split; y < h; y += size) {
                for (let x = 0; x < w; x += size) {
                    if (((Math.floor(x / size) + Math.floor(y / size)) % 2) === 0)
                        ctx.fillRect(x, y, size, size);
                }
            }

            ctx.strokeStyle = "#ffffff";
            ctx.lineWidth = Math.max(2, Math.floor(Math.min(w, h) / 160));
            ctx.beginPath();
            ctx.moveTo(w / 2 - w / 8, h / 2);
            ctx.lineTo(w / 2 + w / 8, h / 2);
            ctx.moveTo(w / 2, h / 2 - h / 10);
            ctx.lineTo(w / 2, h / 2 + h / 10);
            ctx.stroke();

            ctx.strokeStyle = root.borderColor;
            ctx.lineWidth = Math.max(3, Math.floor(Math.min(w, h) / 80));
            ctx.strokeRect(ctx.lineWidth / 2, ctx.lineWidth / 2,
                           w - ctx.lineWidth, h - ctx.lineWidth);
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
}
