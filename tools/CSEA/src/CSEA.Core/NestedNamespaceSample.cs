namespace OuterNamespace
{
    namespace InnerNamespace
    {
        public abstract class NestedAbstractClass
        {
            public abstract void AbstractMethod();
            public virtual void VirtualMethod() { }
        }

        public interface INestedInterface
        {
            void InterfaceMethod();
            string InterfaceProperty { get; set; }
        }
    }
}
