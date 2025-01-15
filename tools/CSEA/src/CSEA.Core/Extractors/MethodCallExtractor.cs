using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using CSEA.Core.Models;

namespace CSEA.Core.Extractors;

public class MethodCallExtractor : CSharpSyntaxWalker
{
    private readonly ExtractedStructure _structure;
    private readonly string _filePath;
    private readonly string _relativePath;
    private readonly Compilation _compilation;
    private readonly IEnumerable<string> _includedNamespaces;
    private readonly IEnumerable<string> _excludedNamespaces;
    private SemanticModel? _semanticModel;
    private SyntaxNode? _currentMethod;

    public MethodCallExtractor(
        ExtractedStructure structure,
        string filePath,
        string relativePath,
        Compilation compilation,
        CommandLineOptions options) : base(SyntaxWalkerDepth.Node)
    {
        _structure = structure;
        _filePath = filePath;
        _relativePath = relativePath;
        _compilation = compilation;
        _includedNamespaces = options.GetIncludedNamespaces();
        _excludedNamespaces = options.GetExcludedNamespaces();
    }

    public override void Visit(SyntaxNode? node)
    {
        if (node == null) return;

        // Get semantic model for the current syntax tree if needed
        if (_semanticModel == null || _semanticModel.SyntaxTree != node.SyntaxTree)
        {
            _semanticModel = _compilation.GetSemanticModel(node.SyntaxTree);
        }

        base.Visit(node);
    }

    public override void VisitMethodDeclaration(MethodDeclarationSyntax node)
    {
        _currentMethod = node;
        var methodSymbol = _semanticModel?.GetDeclaredSymbol(node);
        if (methodSymbol != null)
        {
            var caller = CreateMethodNode(methodSymbol, node);
            ProcessMethodBody(node, caller);
        }
        base.VisitMethodDeclaration(node);
        _currentMethod = null;
    }

    private void ProcessMethodBody(MethodDeclarationSyntax node, MethodNode caller)
    {
        foreach (var invocation in node.DescendantNodes().OfType<InvocationExpressionSyntax>())
        {
            var symbolInfo = _semanticModel?.GetSymbolInfo(invocation);
            if (symbolInfo?.Symbol is IMethodSymbol calledMethod)
            {
                // Skip system library calls
                if (IsSystemLibraryCall(calledMethod))
                    continue;

                var callee = CreateMethodNode(calledMethod, invocation);
                var callType = DetermineCallType(calledMethod);
                
                var call = new MethodCall(
                    caller,
                    callee,
                    _filePath,
                    invocation.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                    callType
                );
                
                _structure.CallGraph.AddCall(call);
            }
        }
    }

    private bool IsSystemLibraryCall(IMethodSymbol method)
    {
        var containingNamespace = method.ContainingNamespace?.ToDisplayString() ?? string.Empty;

        // If specific namespaces are included, only allow those
        if (_includedNamespaces.Any())
        {
            return !_includedNamespaces.Any(ns => containingNamespace.StartsWith(ns));
        }

        // Otherwise, exclude specified namespaces
        return _excludedNamespaces.Any(ns => containingNamespace.StartsWith(ns));
    }

    private MethodNode CreateMethodNode(IMethodSymbol method, SyntaxNode node)
    {
        var containingType = method.ContainingType;
        var location = node.GetLocation();
        var lineSpan = location.GetLineSpan();

        return new MethodNode(
            name: method.Name,
            containingType: containingType.Name,
            @namespace: containingType.ContainingNamespace.ToDisplayString(),
            filePath: _filePath,
            lineNumber: lineSpan.StartLinePosition.Line + 1,
            isAbstract: method.IsAbstract,
            isVirtual: method.IsVirtual,
            isInterface: containingType.TypeKind == TypeKind.Interface
        );
    }

    private static CallType DetermineCallType(IMethodSymbol method)
    {
        if (method.ContainingType.TypeKind == TypeKind.Interface)
            return CallType.Interface;
        if (method.IsVirtual || method.IsOverride || method.IsAbstract)
            return CallType.Virtual;
        if (method.MethodKind == MethodKind.Constructor)
            return CallType.Constructor;
        if (method.MethodKind == MethodKind.DelegateInvoke)
            return CallType.Delegate;
        if (method.MethodKind == MethodKind.EventRaise)
            return CallType.Event;
        return CallType.Direct;
    }
}
