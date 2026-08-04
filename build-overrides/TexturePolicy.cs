using CodeWalker.GameFiles;
using DexClothingOptimizer.Models;

namespace DexClothingOptimizer.Services;

public static class TexturePolicy
{
    public static TexturePlan CreatePlan(Texture texture, int index, OptimizationSettings settings)
    {
        var name = texture.Name ?? $"texture_{index}";
        var format = texture.Format.ToString();
        var role = DetectRole(name);
        var isScriptRt = name.Contains("script_rt", StringComparison.OrdinalIgnoreCase);
        var scriptCompressed = isScriptRt && IsBlockCompressed(format);

        var sourceWidth = Math.Max(1, (int)texture.Width);
        var sourceHeight = Math.Max(1, (int)texture.Height);
        var (targetWidth, targetHeight) = DetermineTargetSize(sourceWidth, sourceHeight, settings.MaxTextureDimension);

        var targetFormat = DetermineTargetFormat(format, role, settings, scriptCompressed);
        var formatChanged = !EquivalentFormat(format, targetFormat);
        var sizeChanged = targetWidth != sourceWidth || targetHeight != sourceHeight;
        var regenerateMips = settings.GenerateFullMipChain && texture.Levels <= 1;
        var shouldProcess = settings.Preset != OptimizationPreset.PreserveOriginal
                            && (scriptCompressed || sizeChanged || formatChanged || regenerateMips);

        if (!IsSupportedTargetFormat(targetFormat))
        {
            targetFormat = MapOriginalFormat(format);
            shouldProcess = false;
        }

        var reasonParts = new List<string>();
        if (scriptCompressed) reasonParts.Add("repair compressed script render target");
        if (sizeChanged) reasonParts.Add($"resize to {targetWidth}×{targetHeight}");
        if (formatChanged) reasonParts.Add($"{format} → {targetFormat}");
        if (regenerateMips) reasonParts.Add("generate full mip chain");
        if (reasonParts.Count == 0) reasonParts.Add("preserve original texture");

        return new TexturePlan
        {
            Index = index,
            Name = name,
            SourceFormat = format,
            TargetFormat = targetFormat,
            SourceWidth = sourceWidth,
            SourceHeight = sourceHeight,
            TargetWidth = targetWidth,
            TargetHeight = targetHeight,
            RegenerateMipmaps = settings.GenerateFullMipChain,
            UncompressScriptTexture = scriptCompressed,
            ShouldProcess = shouldProcess,
            Reason = string.Join(", ", reasonParts),
            EstimatedInputBytes = EstimateBytes(sourceWidth, sourceHeight, format, Math.Max(1, (int)texture.Levels)),
            EstimatedOutputBytes = EstimateBytes(targetWidth, targetHeight, targetFormat, settings.GenerateFullMipChain ? 0 : Math.Max(1, (int)texture.Levels))
        };
    }

    public static TextureInfo CreateTextureInfo(Texture texture, int index, TexturePlan plan)
    {
        var format = texture.Format.ToString();
        return new TextureInfo
        {
            Index = index,
            Name = texture.Name ?? $"texture_{index}",
            Width = texture.Width,
            Height = texture.Height,
            Levels = texture.Levels,
            Format = format,
            Role = DetectRole(texture.Name ?? string.Empty),
            EstimatedBytes = plan.EstimatedInputBytes,
            EstimatedOutputBytes = plan.EstimatedOutputBytes,
            WillChange = plan.ShouldProcess,
            PlannedAction = plan.Reason
        };
    }

    public static string DetectRole(string name)
    {
        var lower = name.ToLowerInvariant();
        if (lower.Contains("normal") || lower.Contains("_n_") || lower.EndsWith("_n") || lower.Contains("norm")) return "Normal map";
        if (lower.Contains("mask") || lower.Contains("rough") || lower.Contains("metal") || lower.Contains("spec") || lower.Contains("_m_") || lower.EndsWith("_m")) return "Mask/specular";
        if (lower.Contains("script_rt")) return "Render target";
        return "Diffuse/color";
    }

    private static string DetermineTargetFormat(string sourceFormat, string role, OptimizationSettings settings, bool scriptCompressed)
    {
        if (scriptCompressed) return "R8G8B8A8_UNORM";
        if (!settings.SmartFormatOptimization) return MapOriginalFormat(sourceFormat);

        var alpha = HasLikelyAlpha(sourceFormat);
        return settings.Preset switch
        {
            OptimizationPreset.SafeQuality when role == "Normal map" => "BC5_UNORM",
            OptimizationPreset.SafeQuality when role == "Mask/specular" => alpha ? "BC7_UNORM" : "BC4_UNORM",
            OptimizationPreset.SafeQuality => "BC7_UNORM",
            OptimizationPreset.Balanced when role == "Normal map" => "BC5_UNORM",
            OptimizationPreset.Balanced when role == "Mask/specular" => alpha ? "BC3_UNORM" : "BC4_UNORM",
            OptimizationPreset.Balanced => alpha ? "BC3_UNORM" : "BC1_UNORM",
            OptimizationPreset.Aggressive when role == "Normal map" => "BC5_UNORM",
            OptimizationPreset.Aggressive when role == "Mask/specular" => alpha ? "BC3_UNORM" : "BC4_UNORM",
            OptimizationPreset.Aggressive => alpha ? "BC3_UNORM" : "BC1_UNORM",
            _ => MapOriginalFormat(sourceFormat)
        };
    }

    public static string MapOriginalFormat(string sourceFormat) => sourceFormat switch
    {
        "D3DFMT_DXT1" => "BC1_UNORM",
        "D3DFMT_DXT3" => "BC2_UNORM",
        "D3DFMT_DXT5" => "BC3_UNORM",
        "D3DFMT_ATI1" => "BC4_UNORM",
        "D3DFMT_ATI2" => "BC5_UNORM",
        "D3DFMT_BC7" => "BC7_UNORM",
        "D3DFMT_A1R5G5B5" => "B5G5R5A1_UNORM",
        "D3DFMT_A8" => "A8_UNORM",
        "D3DFMT_A8B8G8R8" => "R8G8B8A8_UNORM",
        "D3DFMT_L8" => "R8_UNORM",
        "D3DFMT_A8R8G8B8" => "B8G8R8A8_UNORM",
        _ => string.Empty
    };

    private static bool HasLikelyAlpha(string sourceFormat) => sourceFormat is
        "D3DFMT_DXT3" or "D3DFMT_DXT5" or "D3DFMT_BC7" or
        "D3DFMT_A1R5G5B5" or "D3DFMT_A8" or "D3DFMT_A8B8G8R8" or "D3DFMT_A8R8G8B8";

    private static bool IsBlockCompressed(string sourceFormat) =>
        sourceFormat.Contains("DXT", StringComparison.OrdinalIgnoreCase)
        || sourceFormat.Contains("ATI", StringComparison.OrdinalIgnoreCase)
        || sourceFormat.Contains("BC", StringComparison.OrdinalIgnoreCase);

    private static bool EquivalentFormat(string sourceFormat, string targetFormat) =>
        string.Equals(MapOriginalFormat(sourceFormat), targetFormat, StringComparison.OrdinalIgnoreCase);

    private static bool IsSupportedTargetFormat(string targetFormat) => !string.IsNullOrWhiteSpace(targetFormat);

    private static (int Width, int Height) DetermineTargetSize(int width, int height, int maxDimension)
    {
        if (maxDimension == int.MaxValue || Math.Max(width, height) <= maxDimension) return (width, height);
        var scale = (double)maxDimension / Math.Max(width, height);
        var newWidth = ClosestPowerOfTwo(Math.Max(4, (int)Math.Round(width * scale)));
        var newHeight = ClosestPowerOfTwo(Math.Max(4, (int)Math.Round(height * scale)));
        return (Math.Min(width, newWidth), Math.Min(height, newHeight));
    }

    private static int ClosestPowerOfTwo(int value)
    {
        if (value <= 1) return 1;
        var lower = 1;
        while (lower <= value / 2) lower <<= 1;
        var upper = lower << 1;
        return value - lower <= upper - value ? lower : upper;
    }

    public static long EstimateBytes(int width, int height, string format, int levels)
    {
        var bytesPerPixel = format switch
        {
            var f when f.Contains("BC1", StringComparison.OrdinalIgnoreCase) || f.Contains("DXT1", StringComparison.OrdinalIgnoreCase) || f.Contains("BC4", StringComparison.OrdinalIgnoreCase) || f.Contains("ATI1", StringComparison.OrdinalIgnoreCase) => 0.5,
            var f when f.Contains("BC2", StringComparison.OrdinalIgnoreCase) || f.Contains("BC3", StringComparison.OrdinalIgnoreCase) || f.Contains("BC5", StringComparison.OrdinalIgnoreCase) || f.Contains("BC7", StringComparison.OrdinalIgnoreCase) || f.Contains("DXT3", StringComparison.OrdinalIgnoreCase) || f.Contains("DXT5", StringComparison.OrdinalIgnoreCase) || f.Contains("ATI2", StringComparison.OrdinalIgnoreCase) => 1.0,
            var f when f.Contains("A8_UNORM", StringComparison.OrdinalIgnoreCase) || f.Contains("R8_UNORM", StringComparison.OrdinalIgnoreCase) || f.Contains("D3DFMT_A8", StringComparison.OrdinalIgnoreCase) || f.Contains("D3DFMT_L8", StringComparison.OrdinalIgnoreCase) => 1.0,
            var f when f.Contains("B5G5R5A1", StringComparison.OrdinalIgnoreCase) || f.Contains("A1R5G5B5", StringComparison.OrdinalIgnoreCase) => 2.0,
            _ => 4.0
        };

        var total = 0d;
        var w = Math.Max(1, width);
        var h = Math.Max(1, height);
        var remaining = levels <= 0 ? int.MaxValue : levels;
        while (remaining-- > 0)
        {
            total += Math.Max(16, w * h * bytesPerPixel);
            if (w == 1 && h == 1) break;
            w = Math.Max(1, w / 2);
            h = Math.Max(1, h / 2);
        }
        return (long)Math.Ceiling(total);
    }
}
