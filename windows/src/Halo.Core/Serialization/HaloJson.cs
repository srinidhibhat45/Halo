using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Halo.Core.Serialization;

/// <summary>
/// Reads and writes Halo's config JSON in exactly the shape the macOS app uses, so configs can be
/// exported on one platform and imported on the other.
/// </summary>
/// <remarks>
/// <list type="bullet">
/// <item>Actions are <c>{"type": "media", "value": "mute"}</c>; enum payloads are camelCase strings.</item>
/// <item>Icons and colours use Swift's enum encoding: <c>{"symbol": {"name": "lock.fill"}}</c>,
/// <c>{"emoji": {"_0": "🙂"}}</c>, <c>{"preset": {"_0": "blue"}}</c>.</item>
/// <item>UUIDs are upper-case, keys are sorted, absent optionals are omitted (a cleared trigger is <c>null</c>).</item>
/// <item>Decoding is tolerant: a slot whose action, icon, title or tint can't be read keeps its
/// place but loses that part; settings fall back to defaults key by key; unreadable app rings are
/// skipped. Only a missing or unreadable <c>globalRing</c> fails the whole config.</item>
/// </list>
/// </remarks>
public static class HaloJson
{
    private static readonly JsonWriterOptions WriterOptions = new()
    {
        Indented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private static readonly JsonDocumentOptions DocumentOptions = new()
    {
        AllowTrailingCommas = true,
        CommentHandling = JsonCommentHandling.Skip,
    };

    public static byte[] Encode(HaloConfig config) => Write(JsonWriters.Config(config));

    /// <exception cref="JsonException">The data is not JSON, or has no readable global ring.</exception>
    public static HaloConfig Decode(ReadOnlyMemory<byte> json) => Read(json, JsonReaders.Config);

    public static byte[] EncodeAction(HaloAction action) => Write(JsonWriters.Action(action));

    /// <exception cref="JsonException">Unknown action type or unreadable payload.</exception>
    public static HaloAction DecodeAction(ReadOnlyMemory<byte> json) => Read(json, JsonReaders.Action);

    public static byte[] EncodeSettings(AppSettings settings) => Write(JsonWriters.Settings(settings));

    public static AppSettings DecodeSettings(ReadOnlyMemory<byte> json) => Read(json, JsonReaders.Settings);

    public static byte[] EncodeRing(Ring ring) => Write(JsonWriters.Ring(ring));

    public static Ring DecodeRing(ReadOnlyMemory<byte> json) => Read(json, JsonReaders.Ring);

    private static T Read<T>(ReadOnlyMemory<byte> json, Func<JsonElement, T> read)
    {
        using var document = JsonDocument.Parse(json, DocumentOptions);
        try
        {
            return read(document.RootElement);
        }
        catch (Exception e) when (JsonReaders.IsDecodeError(e) && e is not JsonException)
        {
            throw new JsonException(e.Message, e);
        }
    }

    /// <summary>Writes a node tree with object keys in ordinal order (like Swift's <c>.sortedKeys</c>).</summary>
    private static byte[] Write(JsonNode node)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, WriterOptions))
        {
            WriteSorted(writer, node);
        }
        return stream.ToArray();
    }

    private static void WriteSorted(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject obj:
                writer.WriteStartObject();
                foreach (var (key, value) in obj.OrderBy(p => p.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(key);
                    WriteSorted(writer, value);
                }
                writer.WriteEndObject();
                break;
            case JsonArray array:
                writer.WriteStartArray();
                foreach (var item in array) WriteSorted(writer, item);
                writer.WriteEndArray();
                break;
            default:
                node.WriteTo(writer);
                break;
        }
    }
}
