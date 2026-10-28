using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using static Halo.App.Interop.Native;

namespace Halo.App.Overlay;

/// <summary>
/// Screen captures: the frosted backdrop for the Glass ring (a small, blurred snapshot of what is
/// behind it, taken just before it appears) and full-resolution captures for screenshot actions.
/// </summary>
internal static class BackdropCapture
{
    /// <summary>Longest side of the downsampled backdrop; upscaling it is part of the blur.</summary>
    private const int BackdropPixels = 120;

    /// <summary>A frozen, blurred snapshot of a screen rectangle (physical pixels), or null on failure.</summary>
    public static BitmapSource? Frosted(int x, int y, int width, int height)
    {
        if (Capture(x, y, width, height) is not { } shot) return null;
        var factor = BackdropPixels / (double)Math.Max(width, height);
        var small = new FormatConvertedBitmap(new TransformedBitmap(shot, new ScaleTransform(factor, factor)), PixelFormats.Bgra32, null, 0);
        var w = small.PixelWidth;
        var h = small.PixelHeight;
        if (w < 2 || h < 2) return null;
        var stride = w * 4;
        var pixels = new byte[stride * h];
        small.CopyPixels(pixels, stride, 0);
        for (var pass = 0; pass < 3; pass++) BoxBlur(pixels, w, h, radius: 2);
        var result = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        result.Freeze();
        return result;
    }

    /// <summary>An opaque, frozen capture of a screen rectangle (physical pixels), or null on failure.</summary>
    public static BitmapSource? Capture(int x, int y, int width, int height)
    {
        if (width <= 0 || height <= 0) return null;
        var screen = GetDC(0);
        if (screen == 0) return null;
        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, width, height);
        var previous = SelectObject(memory, bitmap);
        try
        {
            if (!BitBlt(memory, 0, 0, width, height, screen, x, y, SRCCOPY | CAPTUREBLT)) return null;
            SelectObject(memory, previous);
            var source = Imaging.CreateBitmapSourceFromHBitmap(bitmap, 0, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally
        {
            SelectObject(memory, previous);
            DeleteObject(bitmap);
            DeleteDC(memory);
            ReleaseDC(0, screen);
        }
    }

    /// <summary>One horizontal and one vertical box-blur pass over BGRA pixels, in place.</summary>
    private static void BoxBlur(byte[] pixels, int width, int height, int radius)
    {
        var copy = (byte[])pixels.Clone();
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++) Average(copy, pixels, width, height, x, y, radius, horizontal: true);
        }
        Array.Copy(pixels, copy, pixels.Length);
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++) Average(copy, pixels, width, height, x, y, radius, horizontal: false);
        }
    }

    private static void Average(byte[] source, byte[] target, int width, int height, int x, int y, int radius, bool horizontal)
    {
        int b = 0, g = 0, r = 0, a = 0, n = 0;
        for (var k = -radius; k <= radius; k++)
        {
            var sx = horizontal ? Math.Clamp(x + k, 0, width - 1) : x;
            var sy = horizontal ? y : Math.Clamp(y + k, 0, height - 1);
            var i = (sy * width + sx) * 4;
            b += source[i];
            g += source[i + 1];
            r += source[i + 2];
            a += source[i + 3];
            n++;
        }
        var o = (y * width + x) * 4;
        target[o] = (byte)(b / n);
        target[o + 1] = (byte)(g / n);
        target[o + 2] = (byte)(r / n);
        target[o + 3] = (byte)(a / n);
    }
}
