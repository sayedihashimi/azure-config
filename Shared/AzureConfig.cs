namespace Shared {
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Text;
    using System.Threading.Tasks;
    using System.Xml.Linq;

    public class AzureConfig {
        private string ConfigXmlPath { get; set; }
        private XDocument ConfigXml { get; set; }
        private string DefaultEnvironmentName { get; set; }

        public AzureConfig(string configXmlPath, string envName) {
            if (string.IsNullOrEmpty(configXmlPath)) { throw new ArgumentNullException("configXmlPath"); }
            if (envName == null) { throw new ArgumentNullException("envName"); }

            this.DefaultEnvironmentName = envName;
            this.LoadConfig(configXmlPath);
        }
        
        private void LoadConfig(string configXmlPath) {
            if (configXmlPath == null) { throw new ArgumentNullException("configXmlPath"); }

            this.ConfigXmlPath = configXmlPath;

            ConfigXml = XDocument.Load(configXmlPath);
        }

        public string GetStorageAccountConnectionString(string storageAccountName) {
            return this.GetStorageAccountConnectionString(storageAccountName, this.DefaultEnvironmentName);
        }

        public string GetStorageAccountConnectionString(string storageAccountName, string envName) {
            if (storageAccountName == null) { throw new ArgumentNullException("storageAccountName"); }
            if (envName == null) { throw new ArgumentNullException("envName"); }

            var connectionStringResult = from n in ConfigXml.Root.Elements("Environment")
                                      where n.Attribute("Name") != null
                                      where n.Attribute("Name").Value != null
                                      where string.Compare(envName, n.Attribute("Name").Value) == 0
                                      //where "prod".Equals(n.Attribute("Name"))
                                      from storage in n.Elements("StorageAccount")
                                      where storage.Attribute("Name") != null && storage.Attribute("Name").Value != null
                                      where string.Compare(storage.Attribute("Name").Value, storageAccountName) == 0
                                      select storage.Attribute("ConnectionString").Value;

            string conString = connectionStringResult.FirstOrDefault();
            return conString;
        }
    }
}
