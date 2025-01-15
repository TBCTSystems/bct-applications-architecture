# CSEA - C# Structural Extraction and Analysis

CSEA is a command-line tool for analyzing and extracting structural information from C# codebases. It provides insights into code organization, relationships, and patterns.

## Features

- **Abstract Class Analysis**: Extract detailed information about abstract classes including methods, properties, fields, and inheritance
- **Interface Analysis**: Extract interface definitions with methods and properties
- **Method Call Graph**: Generate a call graph showing relationships between methods
- **Code Stripping**: Create a stripped version of code by removing implementation details while preserving structure
- **Namespace Filtering**: Include/exclude specific namespaces from analysis
- **Test Project Handling**: Option to include/exclude test projects

## Installation

1. Clone the repository
2. Navigate to the tools/CSEA directory
3. Build the solution:
   ```bash
   dotnet build
   ```

## Usage

```bash
csea [path] -o [output_directory] [options]
```

### Required Parameters
- `path`: Path to C# file (.cs), project (.csproj), or solution (.sln)
- `-o|--output`: Output directory for analysis results and stripped code

### Options
- `-v|--verbose`: Enable verbose output
- `-s|--strip`: Generate stripped version of code (default: true)
- `--include-namespaces`: Comma-separated list of namespaces to include in call graph
- `--exclude-namespaces`: Comma-separated list of namespaces to exclude from call graph
- `--include-tests`: Include test projects in analysis

## Examples

1. Analyze a solution and generate stripped code:
   ```bash
   csea MySolution.sln -o ./output
   ```

2. Analyze a project excluding test projects:
   ```bash
   csea MyProject.csproj -o ./output --include-namespaces MyCompany,MyProject
   ```

3. Analyze a single file with verbose output:
   ```bash
   csea MyClass.cs -o ./output -v
   ```

## Output

The tool generates two types of output:

1. **Stripped Code** (if enabled):
   - Preserves class/interface structure
   - Removes method bodies and implementation details
   - Maintains type signatures and attributes

2. **Analysis Report** (solution_analysis.md):
   - Abstract classes with methods, properties, and inheritance
   - Interfaces with method signatures
   - Method call graph in Mermaid format
   - File locations and line numbers

## License

[MIT License](LICENSE)
