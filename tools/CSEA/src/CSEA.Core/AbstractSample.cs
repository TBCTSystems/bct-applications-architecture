using System;

namespace Sample
{
    public abstract class AbstractClass
    {
        public abstract void AbstractMethod();
        
        public virtual void VirtualMethod()
        {
            Console.WriteLine("Virtual implementation");
        }
        
        public void ConcreteMethod()
        {
            Console.WriteLine("Concrete implementation");
        }
    }
}
