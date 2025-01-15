using System;
using System.Linq;
using System.Text;
using CSEA.Core.Models;

namespace CSEA.Core.Output;

public static class OutputFormatter
{
    public static string GenerateMermaidDiagrams(ExtractedStructure structure)
    {
        var sb = new StringBuilder();
        sb.AppendLine("# Method Call Graph");
        sb.AppendLine();
        sb.AppendLine(structure.CallGraph.ToMermaidFlowchart());
        return sb.ToString();
    }

    public static void FormatBasicStructure(ExtractedStructure structure)
    {
        var abstractClasses = structure.Classes.Where(c => c.IsAbstract).ToList();
        Console.WriteLine("=== Code Structure Overview ===");
        Console.WriteLine($"Abstract Classes: {abstractClasses.Count}");
        Console.WriteLine($"Interfaces: {structure.Interfaces.Count}");
        Console.WriteLine($"Total Methods: {abstractClasses.Sum(c => c.Methods.Count)}");
        Console.WriteLine($"Total Properties: {abstractClasses.Sum(c => c.Properties.Count)}");
    }

    public static void FormatFullStructure(ExtractedStructure structure)
    {
        var abstractClasses = structure.Classes.Where(c => c.IsAbstract).ToList();
        Console.WriteLine("=== Abstract Classes ===");
        foreach (var abstractClass in abstractClasses)
        {
            Console.WriteLine($"- {abstractClass.Name}");
            Console.WriteLine($"  Location: {abstractClass.FilePath}");
            Console.WriteLine($"  Namespace: {abstractClass.Namespace}");
            
            if (abstractClass.BaseTypes.Any())
            {
                Console.WriteLine($"  Inherits from: {string.Join(", ", abstractClass.BaseTypes)}");
            }

            if (abstractClass.ImplementedInterfaces.Any())
            {
                Console.WriteLine("  Implements:");
                foreach (var interfaceName in abstractClass.ImplementedInterfaces)
                {
                    Console.WriteLine($"    - {interfaceName}");
                }
            }

            Console.WriteLine("  Methods:");
            foreach (var method in abstractClass.Methods)
            {
                var modifiers = new List<string>();
                modifiers.Add(method.AccessModifier);
                if (method.IsAbstract) modifiers.Add("abstract");
                if (method.IsVirtual) modifiers.Add("virtual");
                
                Console.WriteLine($"    - {string.Join(" ", modifiers)} {method.ReturnType} {method.Name}({string.Join(", ", method.Parameters.Select(p => $"{p.Type} {p.Name}"))})");
            }

            Console.WriteLine("  Properties:");
            foreach (var property in abstractClass.Properties)
            {
                var accessors = new List<string>();
                if (property.HasGetter) accessors.Add("get");
                if (property.HasSetter) accessors.Add("set");
                Console.WriteLine($"    - {property.Type} {property.Name} {{ {string.Join("; ", accessors)} }}");
            }

            Console.WriteLine("  Fields:");
            foreach (var field in abstractClass.Fields)
            {
                var modifiers = new List<string>();
                if (field.IsStatic) modifiers.Add("static");
                if (field.IsReadonly) modifiers.Add("readonly");
                var modifierStr = modifiers.Any() ? $"{string.Join(" ", modifiers)} " : "";
                
                Console.WriteLine($"    - {field.AccessModifier} {modifierStr}{field.Type} {field.Name}");
            }
        }

        Console.WriteLine("\n=== Interfaces ===");
        foreach (var interfaceDef in structure.Interfaces)
        {
            Console.WriteLine($"- {interfaceDef.Name}");
            Console.WriteLine($"  Location: {interfaceDef.FilePath}");
            Console.WriteLine($"  Namespace: {interfaceDef.Namespace}");

            Console.WriteLine("  Methods:");
            foreach (var method in interfaceDef.Methods)
            {
                Console.WriteLine($"    - {method.ReturnType} {method.Name}({string.Join(", ", method.Parameters.Select(p => $"{p.Type} {p.Name}"))})");
            }
        }
    }

    public static void FormatStructureOnly(ExtractedStructure structure)
    {
        var abstractClasses = structure.Classes.Where(c => c.IsAbstract).ToList();
        Console.WriteLine("=== Abstract Class Structure ===");
        foreach (var abstractClass in abstractClasses)
        {
            Console.WriteLine($"- {abstractClass.Name}");
            Console.WriteLine($"  Inherits: {string.Join(", ", abstractClass.BaseTypes) ?? "None"}");
            Console.WriteLine($"  Implements: {string.Join(", ", abstractClass.ImplementedInterfaces) ?? "None"}");
        }

        Console.WriteLine("\n=== Interface Structure ===");
        foreach (var interfaceDef in structure.Interfaces)
        {
            Console.WriteLine($"- {interfaceDef.Name}");
        }
    }

    private static string SanitizeId(string id)
    {
        // Replace characters that Mermaid doesn't like in IDs
        return id.Replace(".", "_")
                .Replace("<", "_")
                .Replace(">", "_")
                .Replace(" ", "_");
    }
}
