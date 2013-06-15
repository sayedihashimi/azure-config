namespace WorkerRole1 {
    using Microsoft.WindowsAzure;
    using Microsoft.WindowsAzure.Storage;
    using Microsoft.WindowsAzure.Storage.Table;
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Text;
    using System.Threading.Tasks;

    public class TypicalWorker : IWorker {
        public void DoWork() {

            // get the connection string from the config
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(
                CloudConfigurationManager.GetSetting("Storage.Hummingbird"));

            CloudTableClient tableClient = storageAccount.CreateCloudTableClient();
            CloudTable table = tableClient.GetTableReference("orders");
            table.CreateIfNotExists();






            throw new NotImplementedException();
        }
    }
}
