/// Reusable minimap widget: miniature document preview with click/drag navigation.
/// Use with any text-based editor. Attach via onScrollRequested callback.
module modules.repo_tools.minimap_widget;

import dlangui;
import dlangui.graphics.drawbuf : DrawBuf;
import std.conv : to;
import std.string : splitLines;
import std.algorithm : max, min;

/// Miniature document preview. Shows document structure and current visible region.
/// Click or drag to navigate. Reusable for any text editor.
class MinimapWidget : Widget
{
    string _text;
    float _scrollRatio = 0f;   /// 0..1, current scroll position (top)
    float _visibleRatio = 1f; /// 0..1, fraction of doc visible
    void delegate(float scrollRatio) _onScrollRequested;

    this()
    {
        super("minimap");
        layoutWidth(12).layoutHeight(FILL_PARENT);
        backgroundColor(0x1A1A1A);
    }

    /// Set document text. Rebuilds line count for drawing.
    void setText(string text)
    {
        _text = text;
        invalidate();
    }

    /// Set visible region: scrollRatio (0..1) and visibleRatio (0..1).
    void setVisibleRegion(float scrollRatio, float visibleRatio)
    {
        _scrollRatio = max(0f, min(1f, scrollRatio));
        _visibleRatio = max(0.01f, min(1f, visibleRatio));
        invalidate();
    }

    /// Callback when user requests scroll (e.g. from click). Pass 0..1.
    void onScrollRequested(void delegate(float) cb) { _onScrollRequested = cb; }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        auto rect = contentRect;
        if (rect.isEmpty) return;

        buf.fillRect(rect, 0x1A1A1A);
        auto lines = _text.splitLines();
        int lineCount = cast(int)lines.length;
        if (lineCount < 1) lineCount = 1;

        float lineHeight = rect.height / cast(float)lineCount;
        if (lineHeight < 1) lineHeight = 1f;

        int blockHeight = cast(int)max(1f, lineHeight);
        int y = 0;
        foreach (i; 0 .. lineCount)
        {
            int bh = (i == lineCount - 1 && y + blockHeight > rect.height)
                ? (rect.height - y) : blockHeight;
            if (bh < 1) bh = 1;
            uint color = 0x333333;
            buf.fillRect(Rect(rect.left, rect.top + y, rect.right, rect.top + y + bh), color);
            y += bh;
        }

        float visTop = _scrollRatio * rect.height;
        float visH = _visibleRatio * rect.height;
        buf.fillRect(Rect(rect.left, cast(int)(rect.top + visTop), rect.right,
            cast(int)(rect.top + min(visTop + visH, cast(float)rect.height))), 0x007AFF44);
    }

    override bool onMouseEvent(MouseEvent event)
    {
        auto rect = contentRect;
        if (rect.isEmpty || !_onScrollRequested) return false;

        if (event.action == MouseAction.ButtonDown || event.action == MouseAction.Move)
        {
            if ((event.flags & MouseFlag.LButton) == 0 && event.action == MouseAction.Move)
                return false;
            float relY = (event.y - rect.top) / cast(float)rect.height;
            float req = max(0f, min(1f, relY - _visibleRatio / 2f));
            _scrollRatio = req;
            _onScrollRequested(req);
            invalidate();
            return true;
        }
        return false;
    }
}
