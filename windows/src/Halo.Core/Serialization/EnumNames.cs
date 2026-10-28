using System.Text.Json;

namespace Halo.Core.Serialization;

/// <summary>
/// JSON names of enum cases: the camelCase case name (<c>PlayPause</c> → <c>playPause</c>), except
/// where the Swift name differs from C# casing (<c>ChatGpt</c> → <c>chatGPT</c>).
/// </summary>
public static class EnumNames
{
    private static readonly Dictionary<Enum, string> Overrides = new()
    {
        [AiService.ChatGpt] = "chatGPT",
    };

    public static string Name<T>(T value) where T : struct, Enum
    {
        if (Overrides.TryGetValue(value, out var name)) return name;
        var text = value.ToString();
        return char.ToLowerInvariant(text[0]) + text[1..];
    }

    /// <exception cref="JsonException">No case has that name.</exception>
    public static T Parse<T>(string name) where T : struct, Enum
    {
        foreach (var value in Enum.GetValues<T>())
        {
            if (Name(value) == name) return value;
        }
        throw new JsonException($"Unknown {typeof(T).Name} \"{name}\".");
    }
}
