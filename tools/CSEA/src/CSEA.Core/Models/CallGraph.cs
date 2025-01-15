using System.Collections.Generic;
using Microsoft.CodeAnalysis;

namespace CSEA.Core.Models;

public class MethodNode
{
    public string Name { get; }
    public string ContainingType { get; }
    public string Namespace { get; }
    public string FilePath { get; }
    public int LineNumber { get; }
    public bool IsAbstract { get; }
    public bool IsVirtual { get; }
    public bool IsInterface { get; }

    public MethodNode(
        string name,
        string containingType,
        string @namespace,
        string filePath,
        int lineNumber,
        bool isAbstract = false,
        bool isVirtual = false,
        bool isInterface = false)
    {
        Name = name;
        ContainingType = containingType;
        Namespace = @namespace;
        FilePath = filePath;
        LineNumber = lineNumber;
        IsAbstract = isAbstract;
        IsVirtual = isVirtual;
        IsInterface = isInterface;
    }

    public string FullName => $"{Namespace}.{ContainingType}.{Name}";
}

public class MethodCall
{
    public MethodNode Caller { get; }
    public MethodNode Callee { get; }
    public string FilePath { get; }
    public int LineNumber { get; }
    public CallType Type { get; }

    public MethodCall(
        MethodNode caller,
        MethodNode callee,
        string filePath,
        int lineNumber,
        CallType type)
    {
        Caller = caller;
        Callee = callee;
        FilePath = filePath;
        LineNumber = lineNumber;
        Type = type;
    }
}

public enum CallType
{
    Direct,
    Virtual,
    Interface,
    Constructor,
    Delegate,
    Event
}

public class CallGraph
{
    private readonly Dictionary<string, MethodNode> _nodes = new();
    private readonly List<MethodCall> _calls = new();

    public void AddNode(MethodNode node)
    {
        if (!_nodes.ContainsKey(node.FullName))
        {
            _nodes[node.FullName] = node;
        }
    }

    public void AddCall(MethodCall call)
    {
        AddNode(call.Caller);
        AddNode(call.Callee);
        _calls.Add(call);
    }

    public IEnumerable<MethodNode> GetNodes() => _nodes.Values;
    public IEnumerable<MethodCall> GetCalls() => _calls;

    public IEnumerable<MethodCall> GetCallsFrom(string callerFullName)
    {
        return _calls.Where(c => c.Caller.FullName == callerFullName);
    }

    public IEnumerable<MethodCall> GetCallsTo(string calleeFullName)
    {
        return _calls.Where(c => c.Callee.FullName == calleeFullName);
    }

    public string ToMermaidFlowchart()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("```mermaid");
        sb.AppendLine("flowchart TD");

        // Add edges (only showing method names for clarity)
        foreach (var call in _calls)
        {
            string callerName = $"{call.Caller.ContainingType}.{call.Caller.Name}";
            string calleeName = $"{call.Callee.ContainingType}.{call.Callee.Name}";
            
            string arrow = call.Type switch
            {
                CallType.Virtual => "-.->",
                CallType.Interface => "==>",
                _ => "-->"
            };
            
            sb.AppendLine($"    {SanitizeId(callerName)} --> {SanitizeId(calleeName)}");
        }

        sb.AppendLine("```");
        return sb.ToString();
    }

    private static string SanitizeId(string id)
    {
        // Replace characters that Mermaid doesn't like in IDs
        return id.Replace(".", "_").Replace("<", "_").Replace(">", "_");
    }
}
