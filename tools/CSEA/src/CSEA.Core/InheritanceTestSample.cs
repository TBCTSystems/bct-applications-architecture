using System;

namespace CSEA.Core.Tests
{
    public interface IBaseInterface
    {
        void InterfaceMethod();
    }

    public interface IDerivedInterface : IBaseInterface
    {
        void DerivedInterfaceMethod();
    }

    public abstract class BaseClass
    {
        public abstract void BaseMethod();
    }

    public abstract class DerivedClass : BaseClass, IBaseInterface
    {
        public string? TestString { get; set; }
        public override void BaseMethod() { }
        public void InterfaceMethod() { }
    }

    public class ConcreteClass : DerivedClass, IDerivedInterface
    {
        public void DerivedInterfaceMethod() { }
    }

    public class StandaloneClass
    {
        public void Method() { }
    }
}
