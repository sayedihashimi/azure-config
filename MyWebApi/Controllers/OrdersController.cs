namespace MyWebApi.Controllers {
    using Microsoft.WindowsAzure.Storage;
    using Microsoft.WindowsAzure.Storage.Queue;
    using Shared;
    using System;
    using System.Collections.Generic;
    using System.Configuration;
    using System.Diagnostics;
    using System.Linq;
    using System.Net;
    using System.Net.Http;
    using System.Web.Http;

    public class OrdersController : ApiController {
        // GET api/orders
        public IEnumerable<string> Get() {
            return new string[] { "value1", "value2" };
        }

        // GET api/orders/5
        public string Get(int id) {
            return "value";
        }

        // POST api/orders
        public void Post([FromBody]string value) {
        }

        // PUT api/orders/5
        public void Put([FromBody]Order order) {
            // insert the order here

            string name = order.Name;

            this.AddOrderToQueue(order);
        }

        // DELETE api/orders/5
        public void Delete(int id) {
        }

        private void AddOrderToQueue(Order order) {
            if (order == null) { throw new ArgumentNullException("order"); }

            Trace.TraceInformation("AddOrderToQueue called");

            string storageConnectionString = ConfigurationManager.ConnectionStrings["Storage.Hummingbird"].ConnectionString;
            var storageAccount = CloudStorageAccount.Parse(storageConnectionString);
            CloudQueueClient queueClient = storageAccount.CreateCloudQueueClient();
            var ordersQueue = queueClient.GetQueueReference("orders");
            Trace.TraceInformation("    Creating table [orders] if not exists");
            ordersQueue.CreateIfNotExists();

            // add the message to the queue
            string orderJson = Newtonsoft.Json.JsonConvert.SerializeObject(order);
            Trace.TraceInformation("    Adding new order to the queue: [{0}]",orderJson);
            CloudQueueMessage message = new CloudQueueMessage(orderJson);
            ordersQueue.AddMessage(message);
            Trace.TraceInformation("    Order added to the queue", orderJson);
        }

        private void AddOrderNew(Order order) {
            // pseudo code
            // CloudStorageAccount storageAccount = CloudStorageAccount.
        }

    }
}
