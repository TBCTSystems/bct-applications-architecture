using System.Collections.Generic;

namespace CSEA.Core.Models;

public class ExtractedStructure
{
    public List<ExtractedClass> Classes { get; } = new();
    public List<ExtractedInterface> Interfaces { get; } = new();
    public List<ExtractedMethodCall> MethodCalls { get; } = new();
    public List<ExtractedNuGetPackage> NuGetPackages { get; } = new();
    public CallGraph CallGraph { get; } = new();
}

public class ExtractedNuGetPackage
{
    public string PackageName { get; set; } = string.Empty;
    public string ProjectPath { get; set; } = string.Empty;
}

public class ExtractedMethodCall
{
    public string CallerMethod { get; set; } = string.Empty;
    public string CalledMethod { get; set; } = string.Empty;
}

public class ExtractedClass
{
    public string Name { get; set; } = string.Empty;
    public string Namespace { get; set; } = string.Empty;
    public bool IsAbstract { get; set; }
    public string FilePath { get; set; } = string.Empty;
    public string RelativePath { get; set; } = string.Empty;
    public List<ExtractedMethod> Methods { get; } = new();
    public List<ExtractedProperty> Properties { get; } = new();
    public List<ExtractedField> Fields { get; } = new();
    public List<string> BaseTypes { get; set; } = new();
    public List<string> ImplementedInterfaces { get; set; } = new();
}

public class ExtractedInterface
{
    public string Name { get; set; } = string.Empty;
    public string Namespace { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public string RelativePath { get; set; } = string.Empty;
    public List<ExtractedMethod> Methods { get; } = new();
    public List<ExtractedProperty> Properties { get; } = new();
}

public class ExtractedMethod
{
    public string Name { get; set; } = string.Empty;
    public string ReturnType { get; set; } = string.Empty;
    public string AccessModifier { get; set; } = string.Empty;
    public List<ExtractedParameter> Parameters { get; set; } = new();
    public bool IsAbstract { get; set; }
    public bool IsVirtual { get; set; }
}

public class ExtractedProperty
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public bool HasGetter { get; set; }
    public bool HasSetter { get; set; }
    public string Initializer { get; set; } = string.Empty;
}

public class ExtractedParameter
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
}

public class ExtractedField
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string AccessModifier { get; set; } = string.Empty;
    public bool IsStatic { get; set; }
    public bool IsReadonly { get; set; }
}
