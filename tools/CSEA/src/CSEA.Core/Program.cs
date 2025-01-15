﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using CommandLine;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.MSBuild;
using CSEA.Core.Extractors;
using CSEA.Core.Models;
using CSEA.Core.Output;

namespace CSEA.Core;

class Program
{
    static async Task Main(string[] args)
    {
        await Parser.Default.ParseArguments<CommandLineOptions>(args)
            .WithParsedAsync(async options => await RunAnalysis(options));
    }

    private static async Task RunAnalysis(CommandLineOptions options)
    {
        var structure = new ExtractedStructure();
        
        try
        {
            // Convert to absolute path
            var absolutePath = Path.GetFullPath(options.Path);
            
            if (!options.IncludeTests && ContainsTest(absolutePath))
            {
                Console.WriteLine($"Skipping test path: {absolutePath}");
                return;
            }

            if (Path.GetExtension(absolutePath) == ".cs")
            {
                AnalyzeFile(absolutePath, structure, options);
                
                if (options.StripCode)
                {
                    string strippedCode = StripCode(options.Path);
                    string outputPath = Path.Combine(
                        options.OutputDirectory ?? Path.GetDirectoryName(options.Path) ?? string.Empty,
                        Path.GetFileNameWithoutExtension(options.Path) + ".stripped.cs");
                    
                    File.WriteAllText(outputPath, strippedCode);
                    Console.WriteLine($"Stripped code saved to: {outputPath}");
                }
            }
            else if (Path.GetExtension(absolutePath) == ".csproj" || Path.GetExtension(absolutePath) == ".sln")
            {
                var workspace = MSBuildWorkspace.Create();
                string outputDirectory = options.OutputDirectory ?? Path.Combine(
                    Path.GetDirectoryName(options.Path) ?? string.Empty,
                    "stripped"
                );
                
                if (Path.GetExtension(options.Path) == ".csproj")
                {
                    var project = await workspace.OpenProjectAsync(absolutePath);
                    await AnalyzeProject(project, structure, options);
                    
                    if (options.StripCode)
                    {
                        await StripProject(project, outputDirectory);
                        Console.WriteLine($"Stripped project saved to: {outputDirectory}");
                    }
                }
                else // .sln file
                {
                    var solution = await workspace.OpenSolutionAsync(absolutePath);
                    foreach (var project in solution.Projects)
                    {
                        if (options.IncludeTests || !IsTestProject(project))
                        {
                            await AnalyzeProject(project, structure, options);
                        }
                    }
                    
                    if (options.StripCode)
                    {
                        await StripSolution(solution, outputDirectory);
                        Console.WriteLine($"Stripped solution saved to: {outputDirectory}");
                    }
                }
            }
            
            OutputStructure(structure, options);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.Message}");
            if (options.Verbose)
            {
                Console.WriteLine(ex.StackTrace);
            }
        }
    }

    private static string StripCode(string path)
    {
        string sourceCode = File.ReadAllText(path);
        SyntaxTree tree = CSharpSyntaxTree.ParseText(sourceCode);
        var root = tree.GetRoot();
        
        var stripper = new CodeStripper();
        var strippedRoot = stripper.Visit(root);
        
        return strippedRoot?.NormalizeWhitespace().ToFullString() ?? string.Empty;
    }

    private static async Task StripProject(Project project, string outputDirectory)
    {
        // Create project directory in output
        string projectName = Path.GetFileNameWithoutExtension(project.FilePath ?? "Unknown");
        string projectOutputPath = Path.Combine(outputDirectory, projectName);
        Directory.CreateDirectory(projectOutputPath);

        // Copy and modify project file
        if (project.FilePath != null)
        {
            string projFileName = Path.GetFileName(project.FilePath);
            string outputProjPath = Path.Combine(projectOutputPath, projFileName);
            File.Copy(project.FilePath, outputProjPath, true);
        }

        // Process each document
        foreach (var document in project.Documents)
        {
            if (document.FilePath == null) continue;

            // Preserve relative path structure
            string relativePath = project.FilePath != null 
                ? Path.GetRelativePath(Path.GetDirectoryName(project.FilePath)!, document.FilePath)
                : Path.GetFileName(document.FilePath);
            
            string outputPath = Path.Combine(projectOutputPath, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);

            var syntaxTree = await document.GetSyntaxTreeAsync();
            if (syntaxTree == null) continue;

            var root = await syntaxTree.GetRootAsync();
            var stripper = new CodeStripper();
            var strippedRoot = stripper.Visit(root);

            if (strippedRoot != null)
            {
                File.WriteAllText(outputPath, strippedRoot.NormalizeWhitespace().ToFullString());
            }
        }
    }

    private static async Task StripSolution(Solution solution, string outputDirectory)
    {
        // Create solution directory
        string solutionName = Path.GetFileNameWithoutExtension(solution.FilePath ?? "Unknown");
        string solutionOutputPath = Path.Combine(outputDirectory, solutionName);
        Directory.CreateDirectory(solutionOutputPath);

        // Copy and modify solution file
        if (solution.FilePath != null)
        {
            string slnFileName = Path.GetFileName(solution.FilePath);
            string outputSlnPath = Path.Combine(solutionOutputPath, slnFileName);
            File.Copy(solution.FilePath, outputSlnPath, true);
        }

        // Process each project
        foreach (var project in solution.Projects)
        {
            await StripProject(project, solutionOutputPath);
        }
    }

    private static async Task AnalyzeProject(Project project, ExtractedStructure structure, CommandLineOptions options)
    {
        foreach (var document in project.Documents)
        {
            if (document.FilePath == null) continue;
            
            var syntaxTree = await document.GetSyntaxTreeAsync();
            if (syntaxTree == null) continue;
            
            var root = await syntaxTree.GetRootAsync();
            string projectPath = project.FilePath ?? throw new InvalidOperationException("Project file path is null");
            string relativePath = Path.GetRelativePath(projectPath, document.FilePath);
            
            var compilation = await document.Project.GetCompilationAsync();
            if (compilation == null) continue;
            
            var extractors = CreateExtractors(structure, document.FilePath, relativePath, compilation, options);
            
            foreach (var extractor in extractors)
            {
                extractor.Visit(root);
            }
        }
    }

    private static void OutputStructure(ExtractedStructure structure, CommandLineOptions options)
    {
        var analysisPath = Path.Combine(options.OutputDirectory, "solution_analysis.md");
        var sb = new StringBuilder();

        // Add header
        sb.AppendLine("# Solution Analysis");
        sb.AppendLine();

        // Add abstract classes section
        sb.AppendLine("## Abstract Classes");
        sb.AppendLine();
        var abstractClasses = structure.Classes.Where(c => c.IsAbstract).ToList();
        foreach (var abstractClass in abstractClasses)
        {
            sb.AppendLine($"### {abstractClass.Name}");
            sb.AppendLine($"- Namespace: `{abstractClass.Namespace}`");
            sb.AppendLine($"- Location: `{abstractClass.RelativePath}`");
            
            if (abstractClass.BaseTypes.Any())
            {
                sb.AppendLine($"- Inherits from: `{string.Join("`, `", abstractClass.BaseTypes)}`");
            }

            if (abstractClass.ImplementedInterfaces.Any())
            {
                sb.AppendLine("- Implements:");
                foreach (var interfaceName in abstractClass.ImplementedInterfaces)
                {
                    sb.AppendLine($"  - `{interfaceName}`");
                }
            }

            if (abstractClass.Methods.Any())
            {
                sb.AppendLine("- Methods:");
                foreach (var method in abstractClass.Methods)
                {
                    var modifiers = new List<string>();
                    modifiers.Add(method.AccessModifier);
                    if (method.IsAbstract) modifiers.Add("abstract");
                    if (method.IsVirtual) modifiers.Add("virtual");
                    
                    sb.AppendLine($"  - `{string.Join(" ", modifiers)} {method.ReturnType} {method.Name}({string.Join(", ", method.Parameters.Select(p => $"{p.Type} {p.Name}"))})`");
                }
            }
            sb.AppendLine();
        }

        // Add interfaces section
        sb.AppendLine("## Interfaces");
        sb.AppendLine();
        foreach (var interfaceDef in structure.Interfaces)
        {
            sb.AppendLine($"### {interfaceDef.Name}");
            sb.AppendLine($"- Namespace: `{interfaceDef.Namespace}`");
            sb.AppendLine($"- Location: `{interfaceDef.RelativePath}`");

            if (interfaceDef.Methods.Any())
            {
                sb.AppendLine("- Methods:");
                foreach (var method in interfaceDef.Methods)
                {
                    sb.AppendLine($"  - `{method.ReturnType} {method.Name}({string.Join(", ", method.Parameters.Select(p => $"{p.Type} {p.Name}"))})`");
                }
            }
            sb.AppendLine();
        }

        // Add method call graph
        sb.AppendLine("## Method Call Graph");
        sb.AppendLine();
        sb.AppendLine(structure.CallGraph.ToMermaidFlowchart());

        // Write the analysis file
        Directory.CreateDirectory(Path.GetDirectoryName(analysisPath)!);
        File.WriteAllText(analysisPath, sb.ToString());
        Console.WriteLine($"Analysis saved to: {analysisPath}");
    }

    private static void AnalyzeFile(string path, ExtractedStructure structure, CommandLineOptions options)
    {
        string sourceCode = File.ReadAllText(path);
        SyntaxTree tree = CSharpSyntaxTree.ParseText(sourceCode);
        var root = tree.GetRoot();
        
        string currentDir = Directory.GetCurrentDirectory() ?? throw new InvalidOperationException("Could not determine current directory");
        string relativePath = Path.GetRelativePath(currentDir, path);
        
        var compilation = CSharpCompilation.Create("TempCompilation")
            .AddSyntaxTrees(tree)
            .AddReferences(MetadataReference.CreateFromFile(typeof(object).Assembly.Location));

        var extractors = CreateExtractors(structure, path, relativePath, compilation, options);
        
        foreach (var extractor in extractors)
        {
            extractor.Visit(root);
        }
    }

    private static bool ContainsTest(string path)
    {
        return path.ToLowerInvariant().Contains("test");
    }

    private static bool IsTestProject(Project project)
    {
        // Check project name and path
        if (ContainsTest(project.Name) || ContainsTest(project.FilePath ?? string.Empty))
            return true;

        // Check project references for common test frameworks
        var testFrameworks = new[] { "xunit", "nunit", "mstest" };
        return project.MetadataReferences
            .Any(r => testFrameworks.Any(f => r.Display?.ToLowerInvariant().Contains(f) == true));
    }

    private static CSharpSyntaxWalker[] CreateExtractors(
        ExtractedStructure structure,
        string filePath,
        string relativePath,
        Compilation compilation,
        CommandLineOptions options)
    {
        return new CSharpSyntaxWalker[] 
        {
            new AbstractClassExtractor(structure, filePath, relativePath, compilation),
            new InterfaceExtractor(structure, filePath, relativePath),
            new MethodCallExtractor(structure, filePath, relativePath, compilation, options)
        };
    }
}
