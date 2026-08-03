from __future__ import annotations

from pathlib import Path

SOURCE = Path("source/grzyClothTool/Helpers/BuildResourceHelper.cs")

NEW_BUILD_META = r'''    private (string, byte[]) BuildMeta(SexType sex)
    {
        static string SanitizeHashToken(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return "PACK";
            }

            var chars = value
                .ToUpperInvariant()
                .Select(c => char.IsLetterOrDigit(c) ? c : '_')
                .ToArray();

            return new string(chars);
        }

        static string GetAnchorPoint(int typeNumeric)
        {
            return typeNumeric switch
            {
                0 => "ANCHOR_HEAD",
                1 => "ANCHOR_EYES",
                2 => "ANCHOR_EARS",
                3 => "ANCHOR_MOUTH",
                4 => "ANCHOR_LEFT_HAND",
                5 => "ANCHOR_RIGHT_HAND",
                6 => "ANCHOR_LEFT_WRIST",
                7 => "ANCHOR_RIGHT_WRIST",
                8 => "ANCHOR_HIP",
                9 => "ANCHOR_LEFT_FOOT",
                10 => "ANCHOR_RIGHT_FOOT",
                11 => "ANCHOR_PH_L_HAND",
                12 => "ANCHOR_PH_R_HAND",
                _ => "ANCHOR_HEAD"
            };
        }

        static void AppendComponentItem(
            StringBuilder sb,
            string uniqueNameHash,
            int drawableIndex,
            int localDrawableIndex,
            string componentType,
            int textureIndex)
        {
            sb.AppendLine("        <Item>");
            sb.AppendLine("            <lockHash />");
            sb.AppendLine("            <cost value=\"0\"/>");
            sb.AppendLine("            <textLabel />");
            sb.AppendLine($"            <uniqueNameHash>{uniqueNameHash}</uniqueNameHash>");
            sb.AppendLine("            <eShopEnum>CLO_SHOP_NONE</eShopEnum>");
            sb.AppendLine("            <locate value=\"-99\" />");
            sb.AppendLine("            <scriptSaveData value=\"0\" />");
            sb.AppendLine("            <restrictionTags>");
            sb.AppendLine("            </restrictionTags>");
            sb.AppendLine("            <forcedComponents />");
            sb.AppendLine("            <variantComponents />");
            sb.AppendLine($"            <drawableIndex value=\"{drawableIndex}\" />");
            sb.AppendLine($"            <localDrawableIndex value=\"{localDrawableIndex}\" />");
            sb.AppendLine($"            <eCompType>{componentType}</eCompType>");
            sb.AppendLine($"            <textureIndex value=\"{textureIndex}\" />");
            sb.AppendLine("            <isInOutfit value=\"false\" />");
            sb.AppendLine("        </Item>");
        }

        static void AppendPropItem(
            StringBuilder sb,
            string uniqueNameHash,
            int propIndex,
            int localPropIndex,
            string anchorPoint,
            int textureIndex)
        {
            sb.AppendLine("        <Item>");
            sb.AppendLine("            <lockHash />");
            sb.AppendLine("            <cost value=\"0\"/>");
            sb.AppendLine("            <textLabel />");
            sb.AppendLine($"            <uniqueNameHash>{uniqueNameHash}</uniqueNameHash>");
            sb.AppendLine("            <eShopEnum>CLO_SHOP_NONE</eShopEnum>");
            sb.AppendLine("            <locate value=\"-99\" />");
            sb.AppendLine("            <scriptSaveData value=\"0\" />");
            sb.AppendLine("            <restrictionTags>");
            sb.AppendLine("            </restrictionTags>");
            sb.AppendLine("            <forcedComponents />");
            sb.AppendLine("            <forcedProps />");
            sb.AppendLine("            <variantComponents />");
            sb.AppendLine("            <variantProps />");
            sb.AppendLine($"            <propIndex value=\"{propIndex}\" />");
            sb.AppendLine($"            <localPropIndex value=\"{localPropIndex}\" />");
            sb.AppendLine($"            <eAnchorPoint>{anchorPoint}</eAnchorPoint>");
            sb.AppendLine($"            <textureIndex value=\"{textureIndex}\" />");
            sb.AppendLine("            <isInOutfit value=\"false\" />");
            sb.AppendLine("        </Item>");
        }

        var eCharacter = sex == SexType.male ? "SCR_CHAR_MULTIPLAYER" : "SCR_CHAR_MULTIPLAYER_F";
        var genderLetter = GetGenderLetter(sex);
        var genderHashLetter = sex == SexType.male ? "M" : "F";
        var pedName = GetPedName(sex);
        var projectName = GetProjectName();
        var projectHashToken = SanitizeHashToken(projectName);

        var drawables = _addon.Drawables
            .Where(x => x.Sex == sex && !x.IsReserved)
            .OrderBy(x => x.IsProp)
            .ThenBy(x => x.TypeNumeric)
            .ThenBy(x => x.Number)
            .ToList();

        StringBuilder sb = new();
        sb.AppendLine(MetaXmlBase.XmlHeader);

        MetaXmlBase.OpenTag(sb, 0, "ShopPedApparel");
        MetaXmlBase.StringTag(sb, 4, "pedName", pedName);
        MetaXmlBase.StringTag(sb, 4, "dlcName", projectName);
        MetaXmlBase.StringTag(sb, 4, "fullDlcName", pedName + "_" + projectName);
        MetaXmlBase.StringTag(sb, 4, "eCharacter", eCharacter);
        MetaXmlBase.StringTag(sb, 4, "creatureMetaData", "mp_creaturemetadata_" + genderLetter + "_" + projectName);

        MetaXmlBase.OpenTag(sb, 4, "pedOutfits");
        MetaXmlBase.CloseTag(sb, 4, "pedOutfits");

        MetaXmlBase.OpenTag(sb, 4, "pedComponents");
        foreach (var drawable in drawables.Where(x => !x.IsProp))
        {
            var drawableIndex = drawable.Number / GlobalConstants.MAX_DRAWABLES_IN_ADDON;
            var localDrawableIndex = drawable.Number % GlobalConstants.MAX_DRAWABLES_IN_ADDON;
            var componentType = "PV_COMP_" + drawable.TypeName.ToUpperInvariant();
            var typeHashToken = SanitizeHashToken(drawable.TypeName);

            for (var textureIndex = 0; textureIndex < drawable.Textures.Count; textureIndex++)
            {
                var uniqueNameHash = $"GCT_{projectHashToken}_{genderHashLetter}_COMP_{typeHashToken}_{drawable.Number}_{textureIndex}";
                AppendComponentItem(
                    sb,
                    uniqueNameHash,
                    drawableIndex,
                    localDrawableIndex,
                    componentType,
                    textureIndex);
            }
        }
        MetaXmlBase.CloseTag(sb, 4, "pedComponents");

        MetaXmlBase.OpenTag(sb, 4, "pedProps");
        foreach (var drawable in drawables.Where(x => x.IsProp))
        {
            var propIndex = drawable.Number / GlobalConstants.MAX_DRAWABLES_IN_ADDON;
            var localPropIndex = drawable.Number % GlobalConstants.MAX_DRAWABLES_IN_ADDON;
            var anchorPoint = GetAnchorPoint(drawable.TypeNumeric);
            var typeHashToken = SanitizeHashToken(drawable.TypeName);

            for (var textureIndex = 0; textureIndex < drawable.Textures.Count; textureIndex++)
            {
                var uniqueNameHash = $"GCT_{projectHashToken}_{genderHashLetter}_PROP_{typeHashToken}_{drawable.Number}_{textureIndex}";
                AppendPropItem(
                    sb,
                    uniqueNameHash,
                    propIndex,
                    localPropIndex,
                    anchorPoint,
                    textureIndex);
            }
        }
        MetaXmlBase.CloseTag(sb, 4, "pedProps");

        MetaXmlBase.CloseTag(sb, 0, "ShopPedApparel");

        var xml = sb.ToString();
        var name = pedName + "_" + projectName + ".meta";
        var bytes = Encoding.UTF8.GetBytes(xml);
        return (name, bytes);
    }
'''


def replace_method(source: str, signature: str, replacement: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise RuntimeError(f"Could not find method signature: {signature}")

    brace_start = source.find("{", start)
    if brace_start < 0:
        raise RuntimeError("Could not find opening brace")

    depth = 0
    end = None
    for index in range(brace_start, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break

    if end is None:
        raise RuntimeError("Could not find matching closing brace")

    return source[:start] + replacement.rstrip() + source[end:]


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8-sig")

    source = replace_method(
        source,
        "    private (string, byte[]) BuildMeta(SexType sex)",
        NEW_BUILD_META,
    )

    old_wait = """            Task finishedTask = await Task.WhenAny(runningTasks);\n            completedTasks++;"""
    new_wait = """            Task finishedTask = await Task.WhenAny(runningTasks);\n            runningTasks.Remove(finishedTask);\n            await finishedTask;\n            completedTasks++;"""

    occurrence_count = source.count(old_wait)
    if occurrence_count != 2:
        raise RuntimeError(
            f"Expected two exporter wait loops, found {occurrence_count}. "
            "Upstream source may have changed."
        )

    source = source.replace(old_wait, new_wait)
    SOURCE.write_text(source, encoding="utf-8")

    if "GCT_{projectHashToken}" not in source:
        raise RuntimeError("Meta generator patch validation failed")

    if source.count("runningTasks.Remove(finishedTask);") != 2:
        raise RuntimeError("Exporter completion patch validation failed")

    print("Patched BuildMeta and exporter completion loops successfully.")


if __name__ == "__main__":
    main()
