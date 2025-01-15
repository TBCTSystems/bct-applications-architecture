using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using CSEA.Core.Models;

namespace CSEA.Core.Extractors;

public class InterfaceExtractor : CSharpSyntaxWalker
{
    private readonly ExtractedStructure _structure;
    private readonly string _filePath;
    private readonly string _relativePath;

    public InterfaceExtractor(ExtractedStructure structure, string filePath, string relativePath)
    {
        _structure = structure;
        _filePath = filePath;
        _relativePath = relativePath;
    }

public override void VisitInterfaceDeclaration(InterfaceDeclarationSyntax node)
    {
        var extractedInterface = new ExtractedInterface
        {
            Name = node.Identifier.Text,
            Namespace = GetNamespace(node),
            FilePath = _filePath,
            RelativePath = _relativePath
        };

        // Extract methods
        var methods = node.Members.OfType<MethodDeclarationSyntax>();
        foreach (var method in methods)
        {
            extractedInterface.Methods.Add(new ExtractedMethod
            {
                Name = method.Identifier.Text,
                ReturnType = method.ReturnType.ToString(),
                AccessModifier = "public", // Interface methods are always public
                Parameters = method.ParameterList.Parameters
                    .Select(p => new ExtractedParameter
                    {
                        Name = p.Identifier.Text,
                        Type = p.Type?.ToString() ?? string.Empty
                    })
                    .ToList(),
                IsAbstract = true, // Interface methods are always abstract
                IsVirtual = false
            });
        }

        // Extract properties
        var properties = node.Members.OfType<PropertyDeclarationSyntax>();
        foreach (var property in properties)
        {
            extractedInterface.Properties.Add(new ExtractedProperty
            {
                Name = property.Identifier.Text,
                Type = property.Type.ToString(),
                HasGetter = property.AccessorList?.Accessors
                    .Any(a => a.Kind() == SyntaxKind.GetAccessorDeclaration) ?? false,
                HasSetter = property.AccessorList?.Accessors
                    .Any(a => a.Kind() == SyntaxKind.SetAccessorDeclaration) ?? false
            });
        }

        _structure.Interfaces.Add(extractedInterface);
        base.VisitInterfaceDeclaration(node);
    }

    private static string GetNamespace(SyntaxNode node)
    {
        var namespaceNodes = node.Ancestors()
            .OfType<NamespaceDeclarationSyntax>()
            .ToList();
            
        if (!namespaceNodes.Any())
            return string.Empty;
            
        // Handle nested namespaces
        return string.Join(".", namespaceNodes
            .OrderBy(n => n.SpanStart)
            .Select(n => n.Name.ToString()));
    }
}
