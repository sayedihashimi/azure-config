﻿namespace MyWebApi.Controllers {
    using Microsoft.WindowsAzure;
    using Microsoft.WindowsAzure.Storage;
    using Microsoft.WindowsAzure.Storage.Queue;
    using AzureHelpers;
    using System;
    using System.Collections.Generic;
    using System.Configuration;
    using System.Diagnostics;
    using System.IO;
    using System.Linq;
    using System.Net;
    using System.Net.Http;
    using System.Web;
    using System.Web.Hosting;
    using System.Web.Http;

    public class OrdersController : ApiController {
        private AzureConfig AzureConfig;

        public OrdersController() {
            this.AzureConfig = new AzureConfig();

            this.AzureConfig = new AzureConfig();

            var result = this.AzureConfig.GetStorageAcctNames();

            string conString = this.AzureConfig.GetSqlDatabaseConnectionString("sayeddb");


        }

        // PUT api/orders/5
        public void Put([FromBody]Order order) {
            // insert the order here

            string name = order.Name;

            this.AddOrderToQueue(order);

            this.AddOrderToQueue2(order);
        }

        // DELETE api/orders/5
        public void Delete(int id) {
        }

        private void AddOrderToQueue(Order order) {
            if (order == null) { throw new ArgumentNullException("order"); }

            Trace.TraceInformation("AddOrderToQueue called");

            //string storageConnectionString = ConfigurationManager.ConnectionStrings["hummingbird"].ConnectionString;
            string storageConnectionString = CloudConfigurationManager.GetSetting("hummingbird");
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

        private void AddOrderToQueue2(Order order) {
            // pseudo code
            string storageConnectionString = this.AzureConfig.GetStorageAccountConnectionString("hummingbird");
            var storageAccount = CloudStorageAccount.Parse(storageConnectionString);
            CloudQueueClient queueClient = storageAccount.CreateCloudQueueClient();
            var ordersQueue = queueClient.GetQueueReference("orders");
            Trace.TraceInformation("    Creating table [orders] if not exists");
            ordersQueue.CreateIfNotExists();

            // add the message to the queue
            string orderJson = Newtonsoft.Json.JsonConvert.SerializeObject(order);
            Trace.TraceInformation("    Adding new order to the queue: [{0}]", orderJson);
            CloudQueueMessage message = new CloudQueueMessage(orderJson);
            ordersQueue.AddMessage(message);
            Trace.TraceInformation("    Order added to the queue", orderJson);
        }
    }
}
