using System;

namespace Sample
{
    public abstract class AbstractClassWithFields
    {
        // Instance fields
        protected string? _protectedField;
        public readonly DateTime _readonlyField;
        
        // Static fields
        public static int StaticField;
        protected static readonly double StaticReadonlyField = 3.14;
        
        public abstract void AbstractMethod();
        
        public virtual void VirtualMethod()
        {
            Console.WriteLine("Virtual implementation");
        }
    }
}
