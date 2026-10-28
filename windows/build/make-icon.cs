// Renders Halo's Windows app icon (the macOS icon's design: a deep indigo rounded square holding a
// ring of eight frosted segments, the top one lit blue, around a hub) and packs it into an .ico.
// Pure .NET: shapes are signed-distance fields with analytic anti-aliasing; PNGs are encoded here.
//
//   dotnet run windows/build/make-icon.cs -- windows/src/Halo.App/Assets
//
// Writes Halo.ico (16–256 px) and HaloLogo.png (256 px) into the given folder.
using System.Buffers.Binary;
using System.IO.Compression;

var outDir = args.Length > 0 ? args[0] : ".";
Directory.CreateDirectory(outDir);
int[] sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];
var pngs = sizes.Select(s => Png.Encode(Icon.Render(s), s)).ToArray();
File.WriteAllBytes(Path.Combine(outDir, "Halo.ico"), Ico.Pack(sizes, pngs));
File.WriteAllBytes(Path.Combine(outDir, "HaloLogo.png"), pngs[^1]);
Console.WriteLine($"Wrote Halo.ico ({string.Join(", ", sizes)} px) and HaloLogo.png to {outDir}");

/// <summary>Straight-alpha RGBA colour, components 0…1.</summary>
readonly record struct Rgba(double R, double G, double B, double A)
{
    public static Rgba Hex(uint rgb, double a = 1) => new(((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, a);
    public Rgba WithAlpha(double a) => this with { A = a };
    public static Rgba Lerp(Rgba x, Rgba y, double t) => new(x.R + (y.R - x.R) * t, x.G + (y.G - x.G) * t, x.B + (y.B - x.B) * t, x.A + (y.A - x.A) * t);
}

/// <summary>The icon on a 1024-unit canvas (y down), sampled at any pixel size.</summary>
static class Icon
{
    const double BodyMin = 100, BodyMax = 924, BodyRadius = 185;
    const double Inner = 176, Outer = 318, Corner = 16, HubRadius = 128;
    static readonly (double X, double Y) C = (512, 512);

    public static double[] Render(int size)
    {
        var pixels = new double[size * size * 4];   // premultiplied RGBA
        var unit = 1024.0 / size;                   // canvas units per pixel (anti-aliasing width)
        for (var py = 0; py < size; py++)
        for (var px = 0; px < size; px++)
        {
            var x = (px + 0.5) * unit;
            var y = (py + 0.5) * unit;
            var o = (py * size + px) * 4;
            void Over(Rgba c, double coverage)
            {
                var a = c.A * Math.Clamp(coverage, 0, 1);
                if (a <= 0) return;
                pixels[o] = c.R * a + pixels[o] * (1 - a);
                pixels[o + 1] = c.G * a + pixels[o + 1] * (1 - a);
                pixels[o + 2] = c.B * a + pixels[o + 2] * (1 - a);
                pixels[o + 3] = a + pixels[o + 3] * (1 - a);
            }

            var body = Box(x, y, BodyMin, BodyMax, BodyRadius);
            Over(Rgba.Hex(0x000000, 0.45), Soft(Box(x, y - 10, BodyMin, BodyMax, BodyRadius), 24));
            var inBody = Cover(body, unit);
            if (inBody <= 0) continue;

            // Body: indigo-to-ink gradient with a blue bloom behind the ring.
            var t = (y - BodyMin) / (BodyMax - BodyMin);
            var bg = t < 0.55 ? Rgba.Lerp(Rgba.Hex(0x272C6B), Rgba.Hex(0x12153A), t / 0.55) : Rgba.Lerp(Rgba.Hex(0x12153A), Rgba.Hex(0x06070F), (t - 0.55) / 0.45);
            Over(bg, inBody);
            var bloom = Math.Max(0, 1 - Distance(x, y, 512, 464) / 430);
            Over(Rgba.Hex(0x4C6BFF, 0.42 * bloom), inBody);

            // Ring of eight segments; the top one lit.
            var lit = Segment(x, y, 0);
            Over(Rgba.Hex(0x3D8BFF, 0.95), Soft(lit, 56) * inBody);
            for (var i = 0; i < 8; i++)
            {
                var d = i == 0 ? lit : Segment(x, y, i);
                var cover = Cover(d, unit) * inBody;
                if (cover <= 0) continue;
                if (i == 0)
                {
                    var r = Distance(x, y, C.X, C.Y);
                    var u = Math.Clamp((Outer - r) / (Outer - Inner), 0, 1);
                    var fill = u < 0.6 ? Rgba.Lerp(Rgba.Hex(0x8FE3FF), Rgba.Hex(0x3D8BFF), u / 0.6) : Rgba.Lerp(Rgba.Hex(0x3D8BFF), Rgba.Hex(0x2B5CFF), (u - 0.6) / 0.4);
                    Over(fill, cover);
                }
                else
                {
                    var v = Math.Clamp((y - (C.Y - Outer)) / (2 * Outer), 0, 1);
                    Over(Rgba.Hex(0xFFFFFF, 0.20 + (0.08 - 0.20) * v), cover);
                }
                var mid = (Inner + Outer) / 2;
                var angle = -Math.PI / 2 + i * Math.PI / 4;
                var dot = Distance(x, y, C.X + Math.Cos(angle) * mid, C.Y + Math.Sin(angle) * mid) - (i == 0 ? 15 : 11);
                Over(Rgba.Hex(0xFFFFFF, i == 0 ? 1 : 0.55), Cover(dot, unit) * inBody);
            }

            // Hub with a soft shadow, a gradient, a hairline and the small ring mark.
            var hubShadow = Distance(x, y - 6, C.X, C.Y) - HubRadius;
            Over(Rgba.Hex(0x000000, 0.5), Soft(hubShadow, 22) * inBody);
            var hub = Distance(x, y, C.X, C.Y) - HubRadius;
            var hubT = Math.Clamp((y - (C.Y - HubRadius)) / (2 * HubRadius), 0, 1);
            Over(Rgba.Lerp(Rgba.Hex(0x2E3470), Rgba.Hex(0x12152F), hubT), Cover(hub, unit) * inBody);
            Over(Rgba.Hex(0xFFFFFF, 0.16), Cover(Math.Abs(hub + 2) - 2, unit) * inBody);
            var mark = Math.Abs(Distance(x, y, C.X, C.Y) - 38) - 7;
            Over(Rgba.Hex(0xBFD4FF, 0.9), Cover(mark, unit) * inBody);

            // Top gloss and a hairline edge.
            Over(Rgba.Hex(0xFFFFFF, 0.10 * Math.Clamp(1 - (y - BodyMin) / (464 - BodyMin), 0, 1)), inBody);
            Over(Rgba.Hex(0xFFFFFF, 0.14), Cover(Math.Abs(body + 2) - 2, unit) * inBody);
        }
        return pixels;
    }

    /// <summary>Signed distance to slot <paramref name="i"/>'s rounded annular sector (12-unit gaps).</summary>
    static double Segment(double x, double y, int i)
    {
        var dx = x - C.X;
        var dy = y - C.Y;
        var r = Math.Sqrt(dx * dx + dy * dy);
        var centre = -Math.PI / 2 + i * Math.PI / 4;
        var half = Math.PI / 8 - 6 / ((Inner + Outer) / 2);
        var delta = Math.Abs(Math.IEEERemainder(Math.Atan2(dy, dx) - centre, 2 * Math.PI)) - half;
        // The core is the sector inset by the corner radius; rounding adds it back.
        var radial = Math.Max(Inner + Corner - r, r - (Outer - Corner));
        var angular = r * Math.Sin(Math.Clamp(delta, -Math.PI / 2, Math.PI / 2)) + Corner;
        var outside = Math.Sqrt(Math.Pow(Math.Max(radial, 0), 2) + Math.Pow(Math.Max(angular, 0), 2));
        return outside + Math.Min(Math.Max(radial, angular), 0) - Corner;
    }

    static double Box(double x, double y, double min, double max, double radius)
    {
        var c = (min + max) / 2;
        var half = (max - min) / 2 - radius;
        var qx = Math.Abs(x - c) - half;
        var qy = Math.Abs(y - c) - half;
        return Math.Sqrt(Math.Pow(Math.Max(qx, 0), 2) + Math.Pow(Math.Max(qy, 0), 2)) + Math.Min(Math.Max(qx, qy), 0) - radius;
    }

    static double Distance(double x, double y, double cx, double cy) => Math.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));

    /// <summary>Pixel coverage of a shape from its signed distance (one pixel of anti-aliasing).</summary>
    static double Cover(double distance, double unit) => Math.Clamp(0.5 - distance / unit, 0, 1);

    /// <summary>A blurred edge: 1 well inside, fading to 0 about <paramref name="blur"/> units outside.</summary>
    static double Soft(double distance, double blur) => 1 / (1 + Math.Exp(distance / (blur / 3)));
}

/// <summary>A minimal PNG encoder (8-bit RGBA, no filtering).</summary>
static class Png
{
    static readonly uint[] Crc = Enumerable.Range(0, 256).Select(n =>
    {
        var c = (uint)n;
        for (var k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
        return c;
    }).ToArray();

    public static byte[] Encode(double[] premultiplied, int size)
    {
        var raw = new byte[size * (size * 4 + 1)];
        for (var y = 0; y < size; y++)
        {
            raw[y * (size * 4 + 1)] = 0;
            for (var x = 0; x < size; x++)
            {
                var i = (y * size + x) * 4;
                var a = premultiplied[i + 3];
                var o = y * (size * 4 + 1) + 1 + x * 4;
                for (var k = 0; k < 3; k++) raw[o + k] = (byte)Math.Round(Math.Clamp(a > 0 ? premultiplied[i + k] / a : 0, 0, 1) * 255);
                raw[o + 3] = (byte)Math.Round(Math.Clamp(a, 0, 1) * 255);
            }
        }
        using var compressed = new MemoryStream();
        using (var z = new ZLibStream(compressed, CompressionLevel.SmallestSize, leaveOpen: true)) z.Write(raw);

        using var png = new MemoryStream();
        png.Write([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        var header = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(header, size);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), size);
        header[8] = 8;   // bit depth
        header[9] = 6;   // RGBA
        Chunk(png, "IHDR", header);
        Chunk(png, "IDAT", compressed.ToArray());
        Chunk(png, "IEND", []);
        return png.ToArray();
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(length, data.Length);
        s.Write(length);
        var typeBytes = type.Select(ch => (byte)ch).ToArray();
        s.Write(typeBytes);
        s.Write(data);
        var crc = 0xFFFFFFFFu;
        foreach (var b in typeBytes.Concat(data)) crc = Crc[(crc ^ b) & 0xFF] ^ (crc >> 8);
        Span<byte> crcBytes = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(crcBytes, crc ^ 0xFFFFFFFF);
        s.Write(crcBytes);
    }
}

/// <summary>Packs PNG images into an .ico (PNG entries are supported for every size since Vista).</summary>
static class Ico
{
    public static byte[] Pack(int[] sizes, byte[][] pngs)
    {
        using var ico = new MemoryStream();
        using var w = new BinaryWriter(ico);
        w.Write((ushort)0);
        w.Write((ushort)1);
        w.Write((ushort)sizes.Length);
        var offset = 6 + 16 * sizes.Length;
        for (var i = 0; i < sizes.Length; i++)
        {
            w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
            w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
            w.Write((byte)0);   // palette
            w.Write((byte)0);   // reserved
            w.Write((ushort)1); // planes
            w.Write((ushort)32);
            w.Write(pngs[i].Length);
            w.Write(offset);
            offset += pngs[i].Length;
        }
        foreach (var png in pngs) w.Write(png);
        w.Flush();
        return ico.ToArray();
    }
}
