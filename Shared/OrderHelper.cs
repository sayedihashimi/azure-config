namespace AzureHelpers {
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Text;
    using System.Threading.Tasks;

    public class OrderHelper {
        public IList<Order> GetFakeOrders() {
            int numOrders = new Random(DateTime.Now.Millisecond).Next(3, 10);
            IList<Order> orders = new List<Order>();

            for (int i = 0; i < numOrders; i++) {
                orders.Add(CreateFakeOrder());
            }

            return orders;
        }

        private Order CreateFakeOrder() {
            Random random = new Random(DateTime.Now.Millisecond);
            return new Order {
                Id = random.Next(1, 100000),
                Name = new RandomStringGenerator().NextString(10),
                Total = (random.NextDouble() * random.Next(1, 1000))
            };
        }
    }
}
