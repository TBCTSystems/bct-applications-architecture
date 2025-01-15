using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace CSEA.Core.Extractors;

public class CodeStripper : CSharpSyntaxRewriter
{
    public override SyntaxTrivia VisitTrivia(SyntaxTrivia trivia)
    {
        // Remove all comments (single-line and multi-line)
        if (trivia.IsKind(SyntaxKind.SingleLineCommentTrivia) ||
            trivia.IsKind(SyntaxKind.MultiLineCommentTrivia) ||
            trivia.IsKind(SyntaxKind.SingleLineDocumentationCommentTrivia) ||
            trivia.IsKind(SyntaxKind.MultiLineDocumentationCommentTrivia) ||
            trivia.IsKind(SyntaxKind.XmlComment))
        {
            return default;
        }
        return trivia;
    }

    public override SyntaxNode? VisitCompilationUnit(CompilationUnitSyntax node)
    {
        // Preserve using directives and visit the rest of the tree
        var visitedMembers = node.Members.Select(member => Visit(member))
                                       .Where(member => member != null)
                                       .Cast<MemberDeclarationSyntax>();
        
        return node.WithUsings(node.Usings)
                  .WithMembers(SyntaxFactory.List(visitedMembers));
    }

    public override SyntaxNode? VisitClassDeclaration(ClassDeclarationSyntax node)
    {
        // Preserve all class declarations with their signatures
        var result = node.WithTypeParameterList(node.TypeParameterList)
                        .WithConstraintClauses(node.ConstraintClauses);

        // Preserve attributes
        if (node.AttributeLists.Any())
        {
            result = result.WithAttributeLists(node.AttributeLists);
        }

        return base.VisitClassDeclaration(result);
    }

    public override SyntaxNode? VisitInterfaceDeclaration(InterfaceDeclarationSyntax node)
    {
        // Preserve interface declarations with their type parameters and constraints
        var result = node.WithTypeParameterList(node.TypeParameterList)
                        .WithConstraintClauses(node.ConstraintClauses);

        // Preserve attributes
        if (node.AttributeLists.Any())
        {
            result = result.WithAttributeLists(node.AttributeLists);
        }

        return base.VisitInterfaceDeclaration(result);
    }

    public override SyntaxNode? VisitMethodDeclaration(MethodDeclarationSyntax node)
    {
        // Remove method bodies but preserve signatures, type parameters, and constraints
        var result = node.WithBody(null)
                        .WithSemicolonToken(SyntaxFactory.Token(SyntaxKind.SemicolonToken))
                        .WithTypeParameterList(node.TypeParameterList)
                        .WithConstraintClauses(node.ConstraintClauses);

        // Preserve attributes
        if (node.AttributeLists.Any())
        {
            result = result.WithAttributeLists(node.AttributeLists);
        }

        return result;
    }

    public override SyntaxNode? VisitPropertyDeclaration(PropertyDeclarationSyntax node)
    {
        // Remove property accessor bodies but preserve the rest
        if (node.AccessorList == null)
            return node;
            
        var accessors = node.AccessorList.Accessors
            .Select(a => a.WithBody(null)
                         .WithSemicolonToken(SyntaxFactory.Token(SyntaxKind.SemicolonToken)))
            .ToArray();
            
        var result = node.WithAccessorList(
            SyntaxFactory.AccessorList(
                SyntaxFactory.List(accessors)
            )
        );

        // Preserve attributes
        if (node.AttributeLists.Any())
        {
            result = result.WithAttributeLists(node.AttributeLists);
        }

        return result;
    }

    public override SyntaxNode? VisitFieldDeclaration(FieldDeclarationSyntax node)
    {
        // Remove field initializers but preserve attributes
        var result = node.WithDeclaration(
            node.Declaration.WithVariables(
                SyntaxFactory.SeparatedList(
                    node.Declaration.Variables.Select(v => 
                        v.WithInitializer(null)
                    )
                )
            )
        );

        // Preserve attributes
        if (node.AttributeLists.Any())
        {
            result = result.WithAttributeLists(node.AttributeLists);
        }

        return result;
    }
}
