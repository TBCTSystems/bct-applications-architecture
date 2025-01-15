using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Xunit;

namespace CSEA.Core.Tests;

using CSEA.Core.Extractors;
using CSEA.Core.Output;

public class CodeStripperTests
{
    [Fact]
    public void PreservesConcreteClassSignature()
    {
        string code = @"
            public class ConcreteClass
            {
                public void Method() { Console.WriteLine(""Hello""); }
                
                public string GetValue(int param1, string param2)
                {
                    return param2 + param1.ToString();
                }
            }";
        
        string expected = @"
            public class ConcreteClass
            {
                public void Method();
                
                public string GetValue(int param1, string param2);
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesAbstractClass()
    {
        string code = @"
            public abstract class AbstractClass
            {
                public abstract void Method();
            }";
        
        string expected = @"
            public abstract class AbstractClass
            {
                public abstract void Method();
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void RemovesMethodBodies()
    {
        string code = @"
            public abstract class TestClass
            {
                public void Method() 
                {
                    Console.WriteLine(""Hello"");
                }
            }";
        
        string expected = @"
            public abstract class TestClass
            {
                public void Method();
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesPropertyDeclarations()
    {
        string code = @"
            public abstract class TestClass
            {
                public int Property { get; set; }
            }";
        
        string expected = @"
            public abstract class TestClass
            {
                public int Property { get; set; }
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void RemovesFieldInitializers()
    {
        string code = @"
            public abstract class TestClass
            {
                private int field = 42;
            }";
        
        string expected = @"
            public abstract class TestClass
            {
                private int field;
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesInterface()
    {
        string code = @"
            public interface ITestInterface
            {
                void Method();
                int Property { get; set; }
            }";
        
        string expected = @"
            public interface ITestInterface
            {
                void Method();
                int Property { get; set; }
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesGenericConstraints()
    {
        string code = @"
            public abstract class GenericClass<T> where T : class, new()
            {
                public abstract T Method<U>() where U : struct;
            }";
        
        string expected = @"
            public abstract class GenericClass<T> where T : class, new()
            {
                public abstract T Method<U>() where U : struct;
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesAttributes()
    {
        string code = @"
            [Serializable]
            public abstract class AttributedClass
            {
                [Obsolete]
                public abstract void Method();

                [Required]
                public string Property { get; set; }
            }";
        
        string expected = @"
            [Serializable]
            public abstract class AttributedClass
            {
                [Obsolete]
                public abstract void Method();

                [Required]
                public string Property { get; set; }
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void RemovesComments()
    {
        string code = @"
            // Single line comment
            public class TestClass
            {
                /* Multi-line
                   comment */
                public void Method() { }

                /// <summary>
                /// Documentation comment
                /// </summary>
                public string Property { get; set; }
            }";
        
        string expected = @"
            public class TestClass
            {
                public void Method();

                public string Property { get; set; }
            }";
        
        AssertStrippedCode(code, expected);
    }

    [Fact]
    public void PreservesUsingDirectives()
    {
        string code = @"
            using System;
            using System.Collections.Generic;
            using static System.Math;

            public abstract class TestClass
            {
                public abstract void Method();
            }";
        
        string expected = @"
            using System;
            using System.Collections.Generic;
            using static System.Math;

            public abstract class TestClass
            {
                public abstract void Method();
            }";
        
        AssertStrippedCode(code, expected);
    }

    private static void AssertStrippedCode(string inputCode, string expectedCode)
    {
        var tree = CSharpSyntaxTree.ParseText(inputCode);
        var root = tree.GetRoot();
        
        var stripper = new CodeStripper();
        var strippedRoot = stripper.Visit(root);
        
        string actual = strippedRoot?.NormalizeWhitespace().ToFullString() ?? string.Empty;
        string expected = CSharpSyntaxTree.ParseText(expectedCode)
            .GetRoot()
            .NormalizeWhitespace()
            .ToFullString();
        
        Assert.Equal(expected, actual);
    }
}
