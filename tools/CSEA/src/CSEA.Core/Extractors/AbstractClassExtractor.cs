using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using CSEA.Core.Models;

namespace CSEA.Core.Extractors;

public class AbstractClassExtractor : CSharpSyntaxWalker
{
    private readonly ExtractedStructure _structure;
    private readonly string _filePath;
    private readonly string _relativePath;
    private readonly Compilation _compilation;

    public AbstractClassExtractor(ExtractedStructure structure, string filePath, string relativePath, Compilation compilation)
    {
        _structure = structure;
        _filePath = filePath;
        _relativePath = relativePath;
        _compilation = compilation;
    }

    public override void VisitClassDeclaration(ClassDeclarationSyntax node)
    {
        if (node.Modifiers.Any(SyntaxKind.AbstractKeyword))
        {
            var extractedClass = new ExtractedClass
            {
                Name = node.Identifier.Text,
                Namespace = GetNamespace(node),
                IsAbstract = true,
                FilePath = _filePath,
                RelativePath = _relativePath
            };

            // Extract methods
            var methods = node.Members.OfType<MethodDeclarationSyntax>();
            foreach (var method in methods)
            {
                extractedClass.Methods.Add(new ExtractedMethod
                {
                    Name = method.Identifier.Text,
                    ReturnType = method.ReturnType.ToString(),
                    AccessModifier = GetAccessModifier(method.Modifiers),
                    Parameters = method.ParameterList.Parameters
                        .Select(p => new ExtractedParameter
                        {
                            Name = p.Identifier.Text,
                            Type = p.Type?.ToString() ?? string.Empty
                        })
                        .ToList(),
                    IsAbstract = method.Modifiers.Any(SyntaxKind.AbstractKeyword),
                    IsVirtual = method.Modifiers.Any(SyntaxKind.VirtualKeyword)
                });
            }

            // Extract properties
            var properties = node.Members.OfType<PropertyDeclarationSyntax>();
            foreach (var property in properties)
            {
                extractedClass.Properties.Add(new ExtractedProperty
                {
                    Name = property.Identifier.Text,
                    Type = property.Type.ToString(),
                    HasGetter = property.AccessorList?.Accessors
                        .Any(a => a.Kind() == SyntaxKind.GetAccessorDeclaration) ?? false,
                    HasSetter = property.AccessorList?.Accessors
                        .Any(a => a.Kind() == SyntaxKind.SetAccessorDeclaration) ?? false,
                    Initializer = property.Initializer?.Value.ToString()
                });
            }

            // Extract fields
            var fields = node.Members.OfType<FieldDeclarationSyntax>();
            foreach (var field in fields)
            {
                foreach (var variable in field.Declaration.Variables)
                {
                    extractedClass.Fields.Add(new ExtractedField
                    {
                        Name = variable.Identifier.Text,
                        Type = field.Declaration.Type.ToString(),
                        IsStatic = field.Modifiers.Any(SyntaxKind.StaticKeyword),
                        IsReadonly = field.Modifiers.Any(SyntaxKind.ReadOnlyKeyword),
                        AccessModifier = GetAccessModifier(field.Modifiers)
                    });
                }
            }

            // Handle base types and interface implementations
            if (node.BaseList != null)
            {
                var semanticModel = _compilation.GetSemanticModel(node.SyntaxTree);
                if (semanticModel != null)
                {
                    foreach (var baseType in node.BaseList.Types)
                    {
                        if (baseType.Type != null)
                        {
                            var typeName = baseType.Type.ToString();
                            extractedClass.BaseTypes.Add(typeName);
                            
                            var typeInfo = semanticModel.GetTypeInfo(baseType.Type);
                            var type = typeInfo.Type;
                            if (type != null && type.TypeKind == TypeKind.Interface)
                            {
                                extractedClass.ImplementedInterfaces.Add(typeName);
                            }
                        }
                    }
                }
            }

            _structure.Classes.Add(extractedClass);
        }
        
        base.VisitClassDeclaration(node);
    }

    private static string GetAccessModifier(SyntaxTokenList modifiers)
    {
        if (modifiers.Any(SyntaxKind.PublicKeyword)) return "public";
        if (modifiers.Any(SyntaxKind.PrivateKeyword)) return "private";
        if (modifiers.Any(SyntaxKind.ProtectedKeyword)) return "protected";
        if (modifiers.Any(SyntaxKind.InternalKeyword)) return "internal";
        return "private"; // Default if no access modifier specified
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
