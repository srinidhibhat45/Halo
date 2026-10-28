using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using static Halo.App.Interop.Native;

namespace Halo.App.Interop;

/// <summary>
/// Shell lookups: high-quality icons for files, executables, shortcuts and packaged apps
/// (<c>IShellItemImageFactory</c>), shortcut targets (<c>IShellLinkW</c>) and known folders.
/// </summary>
/// <remarks>Uses classic COM interop; call from an STA thread (the UI thread) for icons.</remarks>
internal static unsafe class ShellItems
{
    private static readonly Guid ScreenshotsFolder = new("b7bede81-df94-4682-a7d8-57a52620b86f");
    private static readonly Guid PicturesFolder = new("33E28130-4E1E-4676-835A-98395C3BC3BB");

    /// <summary>
    /// The shell's icon for a parsing name (a path, or <c>shell:AppsFolder\&lt;AUMID&gt;</c>) at
    /// <paramref name="pixels"/> square, with transparency; null when the shell has none.
    /// </summary>
    public static BitmapSource? Icon(string parsingName, int pixels)
    {
        IShellItemImageFactory? factory = null;
        nint bitmap = 0;
        try
        {
            if (SHCreateItemFromParsingName(parsingName, 0, typeof(IShellItemImageFactory).GUID, out factory) != 0 || factory is null) return null;
            if (factory.GetImage(new SIZE { cx = pixels, cy = pixels }, SIIGBF_ICONONLY, out bitmap) != 0 || bitmap == 0) return null;
            return ToBitmapSource(bitmap);
        }
        catch (Exception e) when (e is COMException or ArgumentException or InvalidCastException)
        {
            return null;
        }
        finally
        {
            if (bitmap != 0) DeleteObject(bitmap);
            if (factory is not null) Marshal.ReleaseComObject(factory);
        }
    }

    /// <summary>The executable a <c>.lnk</c> points at, or null (advertised or non-file shortcuts).</summary>
    public static string? ShortcutTarget(string lnkPath)
    {
        object? link = null;
        try
        {
            link = new ShellLinkCoClass();
            ((IPersistFile)link).Load(lnkPath, 0);
            var target = new StringBuilder(1024);
            ((IShellLinkW)link).GetPath(target, target.Capacity, 0, 0);
            return target.Length > 0 ? target.ToString() : null;
        }
        catch (Exception e) when (e is COMException or UnauthorizedAccessException or FileNotFoundException)
        {
            return null;
        }
        finally
        {
            if (link is not null) Marshal.ReleaseComObject(link);
        }
    }

    /// <summary>The user's Screenshots folder (Pictures\Screenshots by default, honouring redirection).</summary>
    public static string ScreenshotsDirectory() =>
        KnownFolder(ScreenshotsFolder)
        ?? Path.Combine(KnownFolder(PicturesFolder) ?? Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");

    private static string? KnownFolder(Guid id)
    {
        if (SHGetKnownFolderPath(id, 0, 0, out var path) != 0) return null;
        try
        {
            return Marshal.PtrToStringUni(path);
        }
        finally
        {
            Marshal.FreeCoTaskMem(path);
        }
    }

    /// <summary>Copies a 32-bit premultiplied DIB section into a frozen WPF bitmap, keeping alpha.</summary>
    private static BitmapSource? ToBitmapSource(nint hbitmap)
    {
        DIBSECTION dib;
        if (GetObjectW(hbitmap, sizeof(DIBSECTION), &dib) == 0 || dib.dsBm.bmBits == 0 || dib.dsBm.bmBitsPixel != 32) return null;
        var width = dib.dsBm.bmWidth;
        var height = Math.Abs(dib.dsBm.bmHeight);
        var stride = dib.dsBm.bmWidthBytes;
        BitmapSource source = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, dib.dsBm.bmBits, stride * height, stride);
        // Bottom-up DIBs (positive height) store the last row first.
        if (dib.dsBmih.biHeight > 0) source = new TransformedBitmap(source, new ScaleTransform(1, -1));
        source.Freeze();
        return source;
    }

    private const int SIIGBF_ICONONLY = 0x4;

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE
    {
        public int cx, cy;
    }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, int flags, out nint phbm);
    }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        // Only the first method of the vtable is used.
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, nint pfd, uint fFlags);
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLinkCoClass;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHCreateItemFromParsingName(
        string pszPath, nint pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory? ppv);
}
