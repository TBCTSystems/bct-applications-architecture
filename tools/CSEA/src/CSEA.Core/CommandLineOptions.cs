using CommandLine;

namespace CSEA.Core;

public class CommandLineOptions
{
    [Value(0, Required = true, HelpText = "Path to C# file, project, or solution to analyze")]
    public string Path { get; set; } = string.Empty;

    [Option('o', "output", Required = true, HelpText = "Output directory for stripped code and analysis")]
    public string OutputDirectory { get; set; } = string.Empty;

    [Option('v', "verbose", HelpText = "Enable verbose output")]
    public bool Verbose { get; set; }

    [Option('s', "strip", Default = true, HelpText = "Generate stripped version of the code")]
    public bool StripCode { get; set; } = true;

    [Option("include-namespaces", HelpText = "Comma-separated list of namespaces to include in call graph (e.g., 'MyCompany,MyProject')")]
    public string? IncludeNamespaces { get; set; }

    [Option("exclude-namespaces", HelpText = "Comma-separated list of namespaces to exclude from call graph (e.g., 'System,Microsoft')")]
    public string? ExcludeNamespaces { get; set; }

    [Option("include-tests", HelpText = "Include test projects in analysis (by default, projects with 'test' in their name are excluded)")]
    public bool IncludeTests { get; set; }

    public IEnumerable<string> GetIncludedNamespaces() =>
        IncludeNamespaces?.Split(',').Select(n => n.Trim()) ?? Enumerable.Empty<string>();

    public IEnumerable<string> GetExcludedNamespaces() =>
        ExcludeNamespaces?.Split(',').Select(n => n.Trim())
        .Concat(new[] { "System", "Microsoft", "CommandLine" }) ?? 
        new[] { "System", "Microsoft", "CommandLine" };
}
